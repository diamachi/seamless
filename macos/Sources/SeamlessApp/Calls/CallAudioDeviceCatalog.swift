import Combine
import CoreAudio
import Foundation

struct CallAudioDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
    let isBluetooth: Bool
}

@MainActor
final class CallAudioDeviceCatalog: ObservableObject {
    @Published private(set) var devices: [CallAudioDevice] = []
    var onChange: (() -> Void)?
    private var listener: AudioObjectPropertyListenerBlock?

    func start() {
        guard listener == nil else { refresh(); return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        self.listener = listener
        var property = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, .main, listener)
        refresh()
    }

    func stop() {
        guard let listener else { return }
        var property = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, .main, listener)
        self.listener = nil
    }

    func refresh() {
        var property = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size) == noErr else { return }
        var identifiers = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = identifiers.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { return }
        devices = identifiers.compactMap { identifier in
            guard let uid = Self.string(identifier, selector: kAudioDevicePropertyDeviceUID),
                  let name = Self.string(identifier, selector: kAudioObjectPropertyName) else { return nil }
            let transport = Self.integer(identifier, selector: kAudioDevicePropertyTransportType)
            return CallAudioDevice(id: identifier, uid: uid, name: name,
                hasInput: Self.hasStreams(identifier, scope: kAudioDevicePropertyScopeInput),
                hasOutput: Self.hasStreams(identifier, scope: kAudioDevicePropertyScopeOutput),
                isBluetooth: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        onChange?()
    }

    func resolve(_ uid: String, input: Bool) -> CallAudioDevice? {
        if uid == "system" {
            let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
            let identifier = Self.integer(AudioObjectID(kAudioObjectSystemObject), selector: selector)
            return devices.first { $0.id == identifier && (input ? $0.hasInput : $0.hasOutput) }
        }
        return devices.first { $0.uid == uid && (input ? $0.hasInput : $0.hasOutput) }
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func string(_ device: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func integer(_ device: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32 {
        var property = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        _ = AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value)
        return value
    }

    private static func hasStreams(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var property = address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr && size > 0
    }
}
