import AppKit
import Combine
import Foundation
import SeamlessCore

private final class AndroidToolDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    func append(_ data: Data) {
        lock.withLock {
            bytes.append(data)
            if bytes.count > 4096 { bytes = Data(bytes.suffix(4096)) }
        }
    }
    var summary: String { lock.withLock { String(decoding: bytes.suffix(600), as: UTF8.self) } }
}

@MainActor
final class AdvancedMirroringController: ObservableObject {
    @Published private(set) var message = "Connect over USB in Devices to verify the phone before opening an app."
    @Published private(set) var activePhoneID: String?
    var onBegin: ((String) -> Void)?
    var onRecord: ((MediaRecord) -> Void)?
    var onEnd: ((String) -> Void)?
    private let stream = ScrcpySocketSession()
    private var generation = UUID()
    private var startupTask: Task<Void, Never>?
    private var serverProcess: Process?
    private var serial: String?
    private var localPort: UInt16?
    private var remoteServerPath: String?

    init() {
        stream.onRecord = { [weak self] record in
            guard let self else { return }
            if self.message != "App sharing is active inside Seamless. Use Pop out for a separate window." {
                self.message = "App sharing is active inside Seamless. Use Pop out for a separate window."
            }
            self.onRecord?(record)
        }
        stream.onFailure = { [weak self] error in
            guard let self else { return }
            self.message = error
            self.stopAll()
        }
    }

    func open(application: PhoneApplication, phoneID: String, serial: String?, framesPerSecond: Int) {
        guard application.identity.profileIdentifier == "0" else {
            message = "The native ADB backend currently supports the primary Android profile only."
            return
        }
        guard let serial, let adb = AndroidToolRunner.find("adb"), let scrcpy = AndroidToolRunner.find("scrcpy") else {
            message = "Connect this paired phone over USB first. Install scrcpy5.0.1 for the version-pinned native backend."
            return
        }
        do {
            _ = try ScrcpyControlMessage.startApp(packageName: application.identity.packageName)
        } catch { message = error.localizedDescription; return }
        stopAll()
        self.serial = serial
        activePhoneID = phoneID
        generation = UUID()
        let expected = generation
        let token = String(format: "%08x", UInt32.random(in: 1...0x7fff_ffff))
        let remotePath = "/data/local/tmp/seamless-scrcpy-\(token).jar"
        remoteServerPath = remotePath
        onBegin?(phoneID)
        message = "Preparing \(application.name) inside Seamless…"
        startupTask = Task {
            do {
                let version = try await AndroidToolRunner.run(scrcpy, arguments: ["--version"])
                guard generation == expected else { return }
                guard version.split(whereSeparator: \.isWhitespace).dropFirst().first == "5.0.1" else {
                    throw AndroidToolFailure(description: "Native app streaming currently requires scrcpy5.0.1; its private protocol is version-pinned.")
                }
                let candidates = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/scrcpy-server").path,
                                  "/opt/homebrew/share/scrcpy/scrcpy-server", "/usr/local/share/scrcpy/scrcpy-server"]
                guard let server = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0) }) else {
                    throw AndroidToolFailure(description: "The matching scrcpy server file is missing.")
                }
                _ = try await AndroidToolRunner.run(adb, arguments: ["-s", serial, "push", server, remotePath], timeout: 30)
                guard generation == expected else {
                    cleanup(adb: adb, serial: serial, port: nil, path: remotePath)
                    return
                }
                let result = try await AndroidToolRunner.run(adb, arguments: ["-s", serial, "forward", "tcp:0", "localabstract:scrcpy_\(token)"])
                guard let port = UInt16(result.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else {
                    throw AndroidToolFailure(description: "ADB did not return a valid app-stream port.")
                }
                guard generation == expected else {
                    cleanup(adb: adb, serial: serial, port: port, path: remotePath)
                    return
                }
                localPort = port
                try launchServer(adb: adb, serial: serial, remotePath: remotePath, token: token,
                                 framesPerSecond: framesPerSecond, expected: expected)
                stream.connect(port: port, packageName: application.identity.packageName)
                message = "ADB app sharing is starting inside Seamless. Use Pop out to move the same stream."
            } catch {
                guard generation == expected else { return }
                message = error.localizedDescription
                stopAll()
            }
        }
    }

    func input(kind: String, coordinates: [String: Double], text: String) {
        stream.input(kind: kind, coordinates: coordinates, text: text)
    }

    func stop(phoneID: String) {
        if activePhoneID == phoneID { stopAll() }
    }

    func stopAll() {
        let previousPhone = activePhoneID
        activePhoneID = nil
        generation = UUID()
        startupTask?.cancel()
        startupTask = nil
        stream.close()
        serverProcess?.terminationHandler = nil
        if serverProcess?.isRunning == true { serverProcess?.terminate() }
        serverProcess = nil
        if let serial, let adb = AndroidToolRunner.find("adb") {
            cleanup(adb: adb, serial: serial, port: localPort, path: remoteServerPath)
        }
        serial = nil
        localPort = nil
        remoteServerPath = nil
        if let previousPhone { onEnd?(previousPhone) }
    }

    private func launchServer(adb: URL, serial: String, remotePath: String, token: String, framesPerSecond: Int, expected: UUID) throws {
        guard framesPerSecond == 60 else { throw AndroidDebugBridgePlan.PlanError.invalidDevice }
        let process = Process()
        process.executableURL = adb
        process.arguments = ["-s", serial, "shell", "CLASSPATH=\(remotePath)", "app_process", "/", "com.genymobile.scrcpy.Server", "5.0.1",
            "scid=\(token)", "log_level=warn", "tunnel_forward=true", "video=true", "audio=false", "control=true",
            "video_codec=h264", "video_bit_rate=12000000", "max_fps=\(framesPerSecond)", "new_display=", "max_size=1920",
            "vd_system_decorations=false", "clipboard_autosync=false", "cleanup=false", "power_on=false",
            "send_device_meta=true", "send_frame_meta=true", "send_stream_meta=true", "send_dummy_byte=true"]
        let diagnostics = AndroidToolDiagnostics()
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { handle in
            let bytes = handle.availableData
            diagnostics.append(bytes)
            if bytes.isEmpty { handle.readabilityHandler = nil }
        }
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self, generation == expected else { return }
                message = process.terminationStatus == 0 ? "ADB app sharing ended." : "ADB server ended: " + diagnostics.summary
                stopAll()
            }
        }
        try process.run()
        serverProcess = process
    }

    private func cleanup(adb: URL, serial: String, port: UInt16?, path: String?) {
        var commands: [[String]] = []
        if let port, let arguments = try? AndroidDebugBridgePlan.removeForward(serial: serial, localPort: port) { commands.append(arguments) }
        if let path { commands.append(["-s", serial, "shell", "rm", "-f", path]) }
        for arguments in commands {
            let process = Process()
            process.executableURL = adb
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }
}
