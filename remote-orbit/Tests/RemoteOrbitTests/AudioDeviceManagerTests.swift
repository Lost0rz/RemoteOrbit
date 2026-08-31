import XCTest
@testable import RemoteOrbit

final class AudioDeviceManagerTests: XCTestCase {
    private let remote = SystemAudioDevice(
        id: 1,
        uid: "remote-orbit",
        name: "RemoteOrbit Mic 2ch",
        hasInput: true,
        hasOutput: true
    )
    private let speakers = SystemAudioDevice(
        id: 2,
        uid: "speakers",
        name: "Mac mini Speakers",
        hasInput: false,
        hasOutput: true
    )
    private let microphone = SystemAudioDevice(
        id: 3,
        uid: "microphone",
        name: "USB Microphone",
        hasInput: true,
        hasOutput: false
    )
    private let loopback = SystemAudioDevice(
        id: 4,
        uid: "blackhole",
        name: "BlackHole 2ch",
        hasInput: true,
        hasOutput: true
    )

    func testInputDevicesKeepRemoteOrbitAndPhysicalMicrophones() {
        let devices = SystemAudioDeviceManager.inputDevices(
            from: [remote, speakers, microphone, loopback]
        )

        XCTAssertEqual(devices.map(\.name), [remote.name, microphone.name])
    }

    func testOutputDevicesExcludeVirtualLoopbackDevices() {
        let devices = SystemAudioDeviceManager.outputDevices(
            from: [remote, speakers, microphone, loopback]
        )

        XCTAssertEqual(devices.map(\.name), [speakers.name])
    }

    func testRemoteOrbitInputIsMarkedAsLoopbackButAllowedAsInput() {
        XCTAssertTrue(remote.isLoopback)
        XCTAssertTrue(remote.isRemoteOrbit)
        XCTAssertFalse(loopback.isRemoteOrbit)
    }
}
