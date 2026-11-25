#include "RemoteOrbitHIDBridge.h"

#include <pqrs/karabiner/driverkit/client_protocol_version.hpp>
#include <pqrs/karabiner/driverkit/virtual_hid_device_driver/hid_report/keyboard_input.hpp>
#include <pqrs/karabiner/driverkit/virtual_hid_device_service/client.hpp>
#include <pqrs/dispatcher.hpp>
#include <type_safe/strong_typedef.hpp>

#include <algorithm>
#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <new>
#include <type_traits>

namespace {
using keyboard_input = pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::keyboard_input;
using modifier = pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::modifier;
using upstream_client = pqrs::karabiner::driverkit::virtual_hid_device_service::client;

std::mutex dispatcher_lifecycle_mutex;
size_t active_client_count = 0;

static_assert(sizeof(keyboard_input) == ROHIDKeyboardReportLength);
static_assert(alignof(keyboard_input) == 1);
static_assert(sizeof(pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::keys) == 64);
static_assert(std::is_trivially_copyable_v<keyboard_input>);

keyboard_input make_report(
    uint8_t modifier_bitmap,
    const uint16_t *key_usages = nullptr,
    size_t key_usage_count = 0) {
    keyboard_input report;
    report.modifiers.clear();
    report.keys.clear();

    constexpr std::array<modifier, 8> modifier_bits = {
        modifier::left_control,
        modifier::left_shift,
        modifier::left_option,
        modifier::left_command,
        modifier::right_control,
        modifier::right_shift,
        modifier::right_option,
        modifier::right_command,
    };
    for (size_t index = 0; index < modifier_bits.size(); ++index) {
        if ((modifier_bitmap & (uint8_t{1} << index)) != 0) {
            report.modifiers.insert(modifier_bits[index]);
        }
    }
    if (key_usages != nullptr) {
        for (size_t index = 0; index < key_usage_count; ++index) {
            if (key_usages[index] != 0) {
                report.keys.insert(key_usages[index]);
            }
        }
    }
    return report;
}
} // namespace

struct ROHIDClient {
    upstream_client client;
    std::atomic<uint64_t> connection_generation{0};
    std::atomic<bool> keyboard_ready{false};
    std::atomic<bool> service_connected{false};
    bool last_driver_connected{false};
    std::mutex callback_mutex;
    bool has_notified_state{false};
    uint64_t last_notified_generation{0};
    bool last_notified_ready{false};
    bool last_notified_connected{false};
    ROHIDStateCallback state_callback{nullptr};
    void *state_callback_context{nullptr};
    nod::scoped_connection connected_connection;
    nod::scoped_connection driver_connected_connection;
    nod::scoped_connection closed_connection;
    nod::scoped_connection error_connection;
    nod::scoped_connection keyboard_ready_connection;

    void notify_state_changed() {
        ROHIDStateCallback cb = nullptr;
        void *ctx = nullptr;
        const uint64_t generation = connection_generation.load(std::memory_order_acquire);
        const bool ready = keyboard_ready.load(std::memory_order_acquire);
        const bool connected = service_connected.load(std::memory_order_acquire);
        {
            std::lock_guard<std::mutex> lock(callback_mutex);
            if (has_notified_state
                && last_notified_generation == generation
                && last_notified_ready == ready
                && last_notified_connected == connected) {
                return;
            }
            has_notified_state = true;
            last_notified_generation = generation;
            last_notified_ready = ready;
            last_notified_connected = connected;
            cb = state_callback;
            ctx = state_callback_context;
        }
        if (cb != nullptr) {
            cb(ctx, generation, ready, connected);
        }
    }

    ROHIDClient() {
        connected_connection = client.connected.connect([this] {
            connection_generation.fetch_add(1, std::memory_order_relaxed);
            last_driver_connected = false;
            service_connected.store(true, std::memory_order_release);
            keyboard_ready.store(false, std::memory_order_release);
            pqrs::karabiner::driverkit::virtual_hid_device_service::virtual_hid_keyboard_parameters parameters;
            parameters.set_country_code(pqrs::hid::country_code::us);
            client.async_virtual_hid_keyboard_initialize(parameters);
            notify_state_changed();
        });
        driver_connected_connection = client.driver_connected.connect([this](bool connected) {
            const bool was_connected = last_driver_connected;
            last_driver_connected = connected;
            if (connected) {
                // Only force-initialize on false -> true driver attach edge; every daemon
                // reply carries driver_connected=true so unconditional force=true loops endlessly.
                if (!was_connected) {
                    pqrs::karabiner::driverkit::virtual_hid_device_service::virtual_hid_keyboard_parameters parameters;
                    parameters.set_country_code(pqrs::hid::country_code::us);
                    client.async_virtual_hid_keyboard_initialize(parameters, true);
                }
            } else {
                keyboard_ready.store(false, std::memory_order_release);
            }
            notify_state_changed();
        });
        closed_connection = client.closed.connect([this] {
            last_driver_connected = false;
            service_connected.store(false, std::memory_order_release);
            keyboard_ready.store(false, std::memory_order_release);
            connection_generation.fetch_add(1, std::memory_order_relaxed);
            notify_state_changed();
        });
        error_connection = client.error_occurred.connect([this](const auto &) {
            last_driver_connected = false;
            service_connected.store(false, std::memory_order_release);
            keyboard_ready.store(false, std::memory_order_release);
            notify_state_changed();
        });
        keyboard_ready_connection = client.virtual_hid_keyboard_ready.connect([this](bool ready) {
            keyboard_ready.store(ready, std::memory_order_release);
            notify_state_changed();
        });
    }
};

extern "C" void rohid_get_keyboard_report_abi(ROHIDKeyboardReportABI *result) {
    if (result == nullptr) {
        return;
    }

    keyboard_input report;
    const auto *bytes = reinterpret_cast<const uint8_t *>(&report);
    const auto *modifier_bytes = reinterpret_cast<const uint8_t *>(&report.modifiers);
    const auto *key_bytes = reinterpret_cast<const uint8_t *>(&report.keys);

    result->size = static_cast<uint32_t>(sizeof(report));
    result->alignment = static_cast<uint32_t>(alignof(keyboard_input));
    result->modifier_offset = static_cast<uint32_t>(modifier_bytes - bytes);
    result->keys_offset = static_cast<uint32_t>(key_bytes - bytes);
    result->key_slot_count = static_cast<uint32_t>(
        sizeof(report.keys.get_raw_value()) / sizeof(uint16_t));
    result->client_protocol_version = rohid_client_protocol_version();
}

extern "C" bool rohid_build_modifier_report(
    uint8_t modifier_bitmap,
    uint8_t *output,
    size_t output_length) {
    return rohid_build_keyboard_report(modifier_bitmap, nullptr, 0, output, output_length);
}

extern "C" bool rohid_build_keyboard_report(
    uint8_t modifier_bitmap,
    const uint16_t *key_usages,
    size_t key_usage_count,
    uint8_t *output,
    size_t output_length) {
    if (output == nullptr || output_length < sizeof(keyboard_input)) {
        return false;
    }
    if (key_usage_count > 32 || (key_usage_count > 0 && key_usages == nullptr)) {
        return false;
    }

    const auto report = make_report(modifier_bitmap, key_usages, key_usage_count);
    const auto *bytes = reinterpret_cast<const uint8_t *>(&report);
    std::copy(bytes, bytes + sizeof(report), output);
    return true;
}

extern "C" uint16_t rohid_client_protocol_version(void) {
    return type_safe::get(
        pqrs::karabiner::driverkit::client_protocol_version::embedded_client_protocol_version);
}

extern "C" uint64_t rohid_client_connection_generation(const ROHIDClient *client) {
    return client == nullptr ? 0 : client->connection_generation.load(std::memory_order_acquire);
}

extern "C" bool rohid_client_keyboard_ready(const ROHIDClient *client) {
    return client != nullptr && client->keyboard_ready.load(std::memory_order_acquire);
}

extern "C" bool rohid_client_service_connected(const ROHIDClient *client) {
    return client != nullptr && client->service_connected.load(std::memory_order_acquire);
}

extern "C" ROHIDClient *rohid_client_create(void) {
    std::lock_guard<std::mutex> lock(dispatcher_lifecycle_mutex);
    try {
        if (active_client_count == 0) {
            pqrs::dispatcher::extra::initialize_shared_dispatcher();
        }
        auto *client = new ROHIDClient{};
        ++active_client_count;
        return client;
    } catch (...) {
        if (active_client_count == 0) {
            pqrs::dispatcher::extra::terminate_shared_dispatcher();
        }
        return nullptr;
    }
}

extern "C" void rohid_client_destroy(ROHIDClient *client) {
    if (client == nullptr) {
        return;
    }

    {
        std::lock_guard<std::mutex> callback_lock(client->callback_mutex);
        client->state_callback = nullptr;
        client->state_callback_context = nullptr;
    }

    // Upstream client::~client detaches synchronously and destroys its
    // dispatcher-owned socket from the detach cleanup callback.
    delete client;
    std::lock_guard<std::mutex> lock(dispatcher_lifecycle_mutex);
    if (active_client_count > 0 && --active_client_count == 0) {
        pqrs::dispatcher::extra::terminate_shared_dispatcher();
    }
}

extern "C" void rohid_client_set_state_callback(
    ROHIDClient *client,
    ROHIDStateCallback callback,
    void *context) {
    if (client == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> lock(client->callback_mutex);
    client->state_callback = callback;
    client->state_callback_context = context;
    client->has_notified_state = false;
}

extern "C" void rohid_client_start(ROHIDClient *client) {
    if (client == nullptr) {
        return;
    }
    pqrs::dispatcher::extra::initialize_shared_dispatcher();
    client->client.async_start();
}

extern "C" void rohid_client_stop(ROHIDClient *client) {
    if (client != nullptr) {
        client->client.async_stop();
    }
}

extern "C" bool rohid_client_post_modifier_bitmap(ROHIDClient *client, uint8_t modifier_bitmap) {
    return rohid_client_post_keyboard_report(client, modifier_bitmap, nullptr, 0);
}

extern "C" bool rohid_client_post_keyboard_report(
    ROHIDClient *client,
    uint8_t modifier_bitmap,
    const uint16_t *key_usages,
    size_t key_usage_count) {
    if (client == nullptr || !rohid_client_keyboard_ready(client)) {
        return false;
    }
    if (key_usage_count > 32 || (key_usage_count > 0 && key_usages == nullptr)) {
        return false;
    }
    client->client.async_post_report(make_report(modifier_bitmap, key_usages, key_usage_count));
    return true;
}
