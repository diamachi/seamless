import AppKit
import Foundation
import Combine
import SeamlessCore

private struct USBPhoneTunnel {
    let serial: String
    let profile: ConnectionProfile
    var isVerified = false
}

@MainActor
final class USBConnectionController: ObservableObject {
    @Published private(set) var devices: [AndroidDebugDevice] = []
    @Published var selectedSerial = ""
    @Published private(set) var isBusy = false
    @Published private(set) var message = "Optional USB transport requires USB debugging. Wi-Fi remains available with debugging off."
    @Published private var tunnels: [String: USBPhoneTunnel] = [:]
    var useTunnel: ((String, ConnectionProfile) -> Void)?
    var removeTunnel: ((String, Bool) -> Void)?

    func shutdown() {
        guard let adb = AndroidToolRunner.find("adb") else { return }
        for tunnel in tunnels.values {
            guard let arguments = try? AndroidDebugBridgePlan.removeForward(serial: tunnel.serial, localPort: tunnel.profile.port) else { continue }
            let cleanup = Process()
            cleanup.executableURL = adb
            cleanup.arguments = arguments
            cleanup.standardOutput = FileHandle.nullDevice
            cleanup.standardError = FileHandle.nullDevice
            // The short-lived ADB cleanup process may finish after our app exits.
            try? cleanup.run()
        }
        tunnels.removeAll()
    }

    func refresh() {
        guard !isBusy else { return }
        guard let adb = AndroidToolRunner.find("adb") else {
            message = "ADB is unavailable. Install Android platform-tools to enable this optional mode."
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let output = try await AndroidToolRunner.run(adb, arguments: ["devices", "-l"])
                devices = AndroidDebugDevice.parseList(output).filter(\.isUSB)
                if !devices.contains(where: { $0.serial == selectedSerial }) { selectedSerial = "" }
                message = devices.isEmpty ? "No USB devices found. Connect your test phone, enable USB debugging and approve this Mac on the phone." : "Choose the intended phone explicitly. Unauthorized devices require approval on that phone."
            } catch { message = error.localizedDescription }
        }
    }

    func connect(_ phone: RememberedPhone) {
        guard !isBusy, let device = devices.first(where: { $0.serial == selectedSerial }), device.state == "device",
              let savedProfile = phone.connection, let adb = AndroidToolRunner.find("adb") else {
            message = "Choose an authorized USB device and a paired phone first."
            return
        }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                await close(phoneID: phone.id, reconnectWiFi: false)
                let arguments = try AndroidDebugBridgePlan.forward(serial: device.serial, remotePort: savedProfile.port)
                let output = try await AndroidToolRunner.run(adb, arguments: arguments)
                guard let port = UInt16(output.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else {
                    throw AndroidToolFailure(description: "ADB did not return a valid local tunnel port.")
                }
                let profile = ConnectionProfile(host: "127.0.0.1", port: port, certificatePin: savedProfile.certificatePin)
                tunnels[phone.id] = USBPhoneTunnel(serial: device.serial, profile: profile)
                message = "USB tunnel created. Verifying this is your paired phone over pinned TLS…"
                useTunnel?(phone.id, profile)
            } catch { message = error.localizedDescription }
        }
    }

    func markVerified(phoneID: String, profile: ConnectionProfile) {
        guard var tunnel = tunnels[phoneID], tunnel.profile == profile else { return }
        tunnel.isVerified = true
        tunnels[phoneID] = tunnel
        message = "USB connected and paired identity verified. Screen, camera, files and controls use the cable."
    }

    func verifiedSerial(phoneID: String) -> String? {
        guard let tunnel = tunnels[phoneID], tunnel.isVerified else { return nil }
        return tunnel.serial
    }

    func hasTunnel(phoneID: String) -> Bool { tunnels[phoneID] != nil }

    func stopTunnel(phoneID: String) {
        if var tunnel = tunnels[phoneID] {
            tunnel.isVerified = false
            tunnels[phoneID] = tunnel
        }
        Task { await close(phoneID: phoneID, reconnectWiFi: false) }
    }

    func useWiFi(phoneID: String) {
        Task { await close(phoneID: phoneID, reconnectWiFi: true) }
    }

    func connectionLost(phoneID: String, reason: String?) {
        guard tunnels[phoneID] != nil else { return }
        Task {
            await close(phoneID: phoneID, reconnectWiFi: true)
            message = "USB connection ended" + (reason.map { ": " + $0 } ?? ".") + " Returning to the saved Wi-Fi connection."
        }
    }

    private func close(phoneID: String, reconnectWiFi: Bool) async {
        guard let tunnel = tunnels.removeValue(forKey: phoneID) else { return }
        removeTunnel?(phoneID, reconnectWiFi)
        if let adb = AndroidToolRunner.find("adb"), let arguments = try? AndroidDebugBridgePlan.removeForward(serial: tunnel.serial, localPort: tunnel.profile.port) {
            do { _ = try await AndroidToolRunner.run(adb, arguments: arguments, timeout: 5) }
            catch { message = "Tunnel closed in Seamless; ADB cleanup failed: \(error.localizedDescription)" }
        }
    }
}
