#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { ROHIDKeyboardReportLength = 67 };

typedef struct ROHIDKeyboardReportABI {
    uint32_t size;
    uint32_t alignment;
    uint32_t modifier_offset;
    uint32_t keys_offset;
    uint32_t key_slot_count;
    uint32_t client_protocol_version;
} ROHIDKeyboardReportABI;

typedef struct ROHIDClient ROHIDClient;
typedef void (*ROHIDStateCallback)(void *context, uint64_t connection_generation, bool keyboard_ready, bool service_connected);

void rohid_get_keyboard_report_abi(ROHIDKeyboardReportABI *result);
bool rohid_build_modifier_report(uint8_t modifier_bitmap, uint8_t *output, size_t output_length);
bool rohid_build_keyboard_report(
    uint8_t modifier_bitmap,
    const uint16_t *key_usages,
    size_t key_usage_count,
    uint8_t *output,
    size_t output_length
);
uint16_t rohid_client_protocol_version(void);
uint64_t rohid_client_connection_generation(const ROHIDClient *client);
bool rohid_client_keyboard_ready(const ROHIDClient *client);
bool rohid_client_service_connected(const ROHIDClient *client);

ROHIDClient *rohid_client_create(void);
void rohid_client_destroy(ROHIDClient *client);
void rohid_client_set_state_callback(ROHIDClient *client, ROHIDStateCallback callback, void *context);
void rohid_client_start(ROHIDClient *client);
void rohid_client_stop(ROHIDClient *client);
bool rohid_client_post_modifier_bitmap(ROHIDClient *client, uint8_t modifier_bitmap);
bool rohid_client_post_keyboard_report(
    ROHIDClient *client,
    uint8_t modifier_bitmap,
    const uint16_t *key_usages,
    size_t key_usage_count
);

#ifdef __cplusplus
}
#endif
