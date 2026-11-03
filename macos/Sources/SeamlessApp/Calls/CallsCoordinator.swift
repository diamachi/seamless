import AppKit
import Combine
@preconcurrency import IOBluetooth
import SeamlessCore

struct PairedCallingPhone: Identifiable, Sendable {
    let id: String
    let name: String
}

@MainActor
final class CallsCoordinator: ObservableObject {
    @Published private(set) var state = PhoneCallState()
    @Published private(set) var activePhoneID: String?
    @Published private(set) var pairedPhones: [PairedCallingPhone] = []
    @Published private(set) var isDiscovering = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isAudioConnected = false
    @Published private(set) var message = "Pair your phone in macOS Bluetooth settings, then choose it here."
    let devices = CallAudioDeviceCatalog()
    let audio = CallAudioRouter()
    private let preferences = CallsPreferences()
    private var handsFree: IOBluetoothHandsFreeDevice?
    private var delegate: HandsFreeEvents?
    private var generation = UUID()
    private var timeout: Task<Void, Never>?
    private var audioTimeout: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init() {
        devices.onChange = { [weak self] in self?.audioDevicesChanged() }
    }

    func options(for phoneID: String) -> PhoneCallingOptions { preferences.options(for: phoneID) }

    func updateOptions(phoneID: String, change: (inout PhoneCallingOptions) -> Void) {
        var options = preferences.options(for: phoneID)
        change(&options)
        if audio.isRunning || audio.isStarting { usePhoneAudio() }
        if activePhoneID == phoneID && options.bluetoothAddress != preferences.options(for: phoneID).bluetoothAddress {
            disconnect()
        }
        preferences.save(options, for: phoneID)
        objectWillChange.send()
    }

    func discoverPairedPhones() {
        guard !isDiscovering else { return }
        isDiscovering = true
        Task {
            let phones = await Task.detached(priority: .userInitiated) {
                let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
                var seenAddresses = Set<String>()
                var phones: [PairedCallingPhone] = []
                for device in paired {
                    guard device.deviceClassMajor == kBluetoothDeviceClassMajorPhone || device.isHandsFreeAudioGateway,
                          let address = PhoneCallState.normalizedBluetoothAddress(device.addressString),
                          seenAddresses.insert(address).inserted else { continue }
                    phones.append(PairedCallingPhone(id: device.addressString, name: device.nameOrAddress))
                }
                return phones.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }.value
            pairedPhones = phones
            isDiscovering = false
            if phones.isEmpty { message = "No paired phone was found. Pair the intended Android phone in macOS Bluetooth settings first." }
        }
    }

    func connect(phoneID: String) {
        guard !state.hasCall else { message = "Finish the current call before changing the calling phone."; return }
        let options = preferences.options(for: phoneID)
        guard PhoneCallState.normalizedBluetoothAddress(options.bluetoothAddress) != nil,
              let device = IOBluetoothDevice(addressString: options.bluetoothAddress), device.isPaired() else {
            message = "Choose a paired Bluetooth phone explicitly."
            return
        }
        disconnect()
        activePhoneID = phoneID
        isConnecting = true
        let expected = generation
        let delegate = HandsFreeEvents { [weak self] event in
            Task { @MainActor in
                guard let self, self.generation == expected else { return }
                self.receive(event)
            }
        }
        self.delegate = delegate
        handsFree = IOBluetoothHandsFreeDevice(device: device, delegate: delegate)
        guard let handsFree else { disconnect(); message = "The Mac could not create a hands-free session for this phone."; return }
        message = "Connecting Bluetooth call controls…"
        devices.start()
        handsFree.connect()
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, generation == expected, !state.isConnected else { return }
            disconnect()
            message = "Bluetooth call connection timed out. Check pairing and phone call-audio support."
        }
    }

    func disconnect() {
        generation = UUID()
        timeout?.cancel()
        audioTimeout?.cancel()
        refreshTask?.cancel()
        audio.stop()
        handsFree?.delegate = nil
        handsFree?.transferAudioToPhone()
        handsFree?.disconnect()
        handsFree = nil
        delegate = nil
        state.disconnect()
        isConnecting = false
        isAudioConnected = false
        activePhoneID = nil
        message = "Calls disconnected. An existing call stays on the phone."
    }

    func forget(phoneID: String) {
        if activePhoneID == phoneID { disconnect() }
        preferences.remove(phoneID: phoneID)
    }

    func shutdown() { disconnect(); devices.stop() }

    func dial(_ text: String) {
        guard state.isConnected, !state.hasCall, let number = PhoneCallState.dialNumber(text) else { return }
        handsFree?.dialNumber(number)
        message = "Dial request sent. Waiting for the phone's call state."
    }

    func answer() {
        guard state.canAnswer else { return }
        handsFree?.acceptCall()
        message = "Answer requested."
    }

    func end() {
        guard state.isConnected, state.hasCall else { return }
        handsFree?.endCall()
        message = "End call requested."
    }

    func sendTone(_ tone: String) {
        guard state.isConnected, state.isActive, tone.count == 1, "0123456789*#".contains(tone) else { return }
        handsFree?.sendDTMF(tone)
    }

    func useMacAudio() {
        guard state.isConnected, state.hasCall else { return }
        handsFree?.transferAudioToComputer()
        message = "Mac audio requested. Waiting for Bluetooth voice audio…"
        let expected = generation
        audioTimeout?.cancel()
        audioTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, generation == expected, !isAudioConnected else { return }
            message = "The phone did not open Bluetooth voice audio. Continue the call on your phone."
        }
    }

    func usePhoneAudio() {
        audioTimeout?.cancel()
        audio.stop()
        handsFree?.transferAudioToPhone()
        message = "Phone audio requested."
    }

    func applySelectedAudio(phoneID: String) async {
        guard activePhoneID == phoneID, state.hasCall, isAudioConnected else { return }
        let options = preferences.options(for: phoneID)
        guard let microphone = devices.resolve(options.microphoneUID, input: true),
              let speaker = devices.resolve(options.speakerUID, input: false),
              let phoneInput = phoneEndpoint(options: options, input: true),
              let phoneOutput = phoneEndpoint(options: options, input: false) else {
            message = "The phone audio endpoint or a selected device is unavailable. Check Audio routing details."
            return
        }
        await audio.start(microphone: microphone, speaker: speaker, phoneInput: phoneInput, phoneOutput: phoneOutput)
        if !audio.isRunning, activePhoneID == phoneID { handsFree?.transferAudioToPhone() }
    }

    func phoneEndpoint(options: PhoneCallingOptions, input: Bool) -> CallAudioDevice? {
        let explicitUID = input ? options.phoneInputUID : options.phoneOutputUID
        if !explicitUID.isEmpty {
            return devices.devices.first { $0.uid == explicitUID && $0.isBluetooth && (input ? $0.hasInput : $0.hasOutput) }
        }
        guard let address = PhoneCallState.normalizedBluetoothAddress(options.bluetoothAddress) else { return nil }
        let matches = devices.devices.filter {
            let normalizedUID = $0.uid.uppercased().replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
            return $0.isBluetooth && normalizedUID.contains(address) && (input ? $0.hasInput : $0.hasOutput)
        }
        if matches.count == 1 { return matches[0] }
        return nil
    }

    private func receive(_ event: HandsFreeEvent) {
        switch event.kind {
        case .connected:
            timeout?.cancel()
            if event.value == 0 {
                state.isConnected = true
                isConnecting = false
                state.isActive = (handsFree?.indicator(IOBluetoothHandsFreeIndicatorCall) ?? 0) != 0
                state.setupMode = Int(handsFree?.indicator(IOBluetoothHandsFreeIndicatorCallSetup) ?? 0)
                state.heldMode = Int(handsFree?.indicator(IOBluetoothHandsFreeIndicatorCallHeld) ?? 0)
                handsFree?.currentCallList()
                message = "Bluetooth call controls connected. Audio is checked separately during a call."
            } else {
                disconnect()
                message = "Bluetooth call controls failed (\(event.value))."
            }
        case .disconnected:
            disconnect()
            message = "Bluetooth calls disconnected (\(event.value)); continue on the phone."
        case .audioOpened:
            audioTimeout?.cancel()
            isAudioConnected = event.value == 0
            message = isAudioConnected ? "Bluetooth voice link opened. macOS manages its audio route until you apply selected devices." : "Bluetooth voice audio failed (\(event.value))."
            devices.refresh()
            refreshAudioEndpoints()
        case .audioClosed:
            isAudioConnected = false
            audio.stop(reason: "Bluetooth voice audio closed.")
        case .active: state.isActive = event.value != 0; cleanUpEndedCall()
        case .setup: state.setupMode = event.value; cleanUpEndedCall()
        case .held: state.heldMode = event.value; cleanUpEndedCall()
        case .caller: state.caller = event.text
        case .current: receiveCurrentCall(event)
        }
    }

    private func receiveCurrentCall(_ event: HandsFreeEvent) {
        switch event.value {
        case 0: state.isActive = true
        case 1: state.heldMode = 2
        case 2, 3: state.setupMode = event.value
        case 4, 5: state.setupMode = 1
        default: return
        }
        if !event.text.isEmpty { state.caller = event.text }
    }

    private func cleanUpEndedCall() {
        if !state.hasCall {
            state.caller = ""
            audio.stop(reason: "No active call.")
        }
    }

    private func refreshAudioEndpoints() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            for _ in 0..<3 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, isAudioConnected else { return }
                devices.refresh()
            }
        }
    }

    private func audioDevicesChanged() {
        if audio.isRunning && !audio.deviceUIDs.isSubset(of: Set(devices.devices.map(\.uid))) {
            usePhoneAudio()
            message = "An audio device disconnected. Audio returned to the phone; choose devices before restarting."
        }
    }
}
