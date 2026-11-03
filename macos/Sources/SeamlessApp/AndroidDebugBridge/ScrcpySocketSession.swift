import Foundation
import Network
import SeamlessCore

@MainActor
final class ScrcpySocketSession {
    var onRecord: ((MediaRecord) -> Void)?
    var onFailure: ((String) -> Void)?
    private var video: NWConnection?
    private var control: NWConnection?
    private var generation = UUID()
    private var decoder = ScrcpyVideoDecoder()
    private var hasDummyByte = false
    private var controlIsReady = false
    private var hasStartedApplication = false
    private var dimensions: (width: Int, height: Int)?
    private var port: UInt16 = 0
    private var packageName = ""
    private var deadline = Date()
    private var startupTimeout: Task<Void, Never>?
    private var pointerIsDown = false
    private var gestureTask: Task<Void, Never>?

    func connect(port: UInt16, packageName: String) {
        close()
        self.port = port
        self.packageName = packageName
        deadline = Date().addingTimeInterval(20)
        let expected = generation
        startupTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard let self, generation == expected, !hasStartedApplication else { return }
            fail("The ADB app stream did not start. Check the phone and USB authorization.")
        }
        connectVideo(expected)
    }

    func close() {
        generation = UUID()
        startupTimeout?.cancel()
        gestureTask?.cancel()
        video?.cancel()
        control?.cancel()
        video = nil
        control = nil
        decoder = ScrcpyVideoDecoder()
        hasDummyByte = false
        controlIsReady = false
        hasStartedApplication = false
        dimensions = nil
        pointerIsDown = false
    }

    func input(kind: String, coordinates: [String: Double], text: String) {
        guard controlIsReady else { return }
        switch kind {
        case "back": sendKey(4)
        case "home": sendKey(3)
        case "recents": sendKey(187)
        case "forward": sendKey(125)
        case "text": send(ScrcpyControlMessage.text(text))
        case "touchDown": sendPointer(action: 0, coordinates: coordinates)
        case "touchMove": sendPointer(action: 2, coordinates: coordinates)
        case "touchUp": sendPointer(action: 1, coordinates: coordinates)
        case "tap", "swipe": startGesture(kind: kind, coordinates: coordinates)
        default: break
        }
    }

    private func makeSocket() -> NWConnection {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        return NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: nil, tcp: tcp))
    }

    private func connectVideo(_ expected: UUID) {
        let socket = makeSocket()
        video = socket
        socket.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, generation == expected, video === socket else { return }
                switch state {
                case .ready: receiveVideo(socket, expected)
                case .failed(let error): retryOrFail(socket, expected, error.localizedDescription)
                default: break
                }
            }
        }
        socket.start(queue: .global(qos: .userInteractive))
    }

    private func receiveVideo(_ socket: NWConnection, _ expected: UUID) {
        socket.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, generation == expected, video === socket else { return }
                do {
                    if let data, !data.isEmpty {
                        var payload = data
                        if !hasDummyByte {
                            guard payload.first == 0 else { throw ConnectionProtocolError.invalidMessage }
                            hasDummyByte = true
                            payload.removeFirst()
                            connectControl(expected)
                        }
                        for event in try decoder.append(payload) {
                            switch event {
                            case let .dimensions(width, height):
                                dimensions = (width, height)
                                launchApplicationWhenReady()
                            case let .record(record): onRecord?(record)
                            }
                        }
                    }
                    if let error { retryOrFail(socket, expected, error.localizedDescription) }
                    else if complete { retryOrFail(socket, expected, "ADB app stream ended.") }
                    else { receiveVideo(socket, expected) }
                } catch { fail(error.localizedDescription) }
            }
        }
    }

    private func retryOrFail(_ socket: NWConnection, _ expected: UUID, _ description: String) {
        guard !hasDummyByte, Date() < deadline else { fail(description); return }
        socket.cancel()
        video = nil
        Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, generation == expected, video == nil else { return }
            connectVideo(expected)
        }
    }

    private func connectControl(_ expected: UUID) {
        let socket = makeSocket()
        control = socket
        socket.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, generation == expected, control === socket else { return }
                switch state {
                case .ready:
                    controlIsReady = true
                    launchApplicationWhenReady()
                    drainControl(socket, expected)
                case .failed(let error): fail(error.localizedDescription)
                default: break
                }
            }
        }
        socket.start(queue: .global(qos: .userInteractive))
    }

    private func launchApplicationWhenReady() {
        guard controlIsReady, dimensions != nil, !hasStartedApplication else { return }
        do {
            let request = try ScrcpyControlMessage.startApp(packageName: packageName)
            hasStartedApplication = true
            startupTimeout?.cancel()
            send(request)
        } catch { fail(error.localizedDescription) }
    }

    private func drainControl(_ socket: NWConnection, _ expected: UUID) {
        // Clipboard autosync is disabled; drain bounded server events without retaining content.
        socket.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] _, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, generation == expected, control === socket else { return }
                if let error { fail(error.localizedDescription) }
                else if complete { fail("ADB app controls disconnected.") }
                else { drainControl(socket, expected) }
            }
        }
    }

    private func send(_ data: Data) {
        let expected = generation
        control?.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                guard let self, generation == expected else { return }
                fail(error.localizedDescription)
            }
        })
    }

    private func sendKey(_ code: UInt32) {
        send(ScrcpyControlMessage.key(code: code, isDown: true))
        send(ScrcpyControlMessage.key(code: code, isDown: false))
    }

    private func sendPointer(action: UInt8, coordinates: [String: Double]) {
        guard let dimensions, gestureTask == nil else { return }
        if action != 0 && !pointerIsDown { return }
        do {
            let message = try ScrcpyControlMessage.touch(action: action,
                x: coordinates["x"] ?? 0.5, y: coordinates["y"] ?? 0.5,
                width: dimensions.width, height: dimensions.height)
            send(message)
            pointerIsDown = action != 1
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func startGesture(kind: String, coordinates: [String: Double]) {
        guard gestureTask == nil, !pointerIsDown, let dimensions else { return }
        let x = coordinates["x"] ?? 0.5
        let y = coordinates["y"] ?? 0.5
        let endX = coordinates["endX"] ?? x
        let endY = coordinates["endY"] ?? y
        let expected = generation
        gestureTask = Task { [weak self] in
            guard let self else { return }
            defer { gestureTask = nil }
            do {
                send(try ScrcpyControlMessage.touch(action: 0, x: x, y: y, width: dimensions.width, height: dimensions.height))
                if kind == "swipe" {
                    for step in 1...12 {
                        try await Task.sleep(for: .milliseconds(16))
                        guard generation == expected else { return }
                        let fraction = Double(step) / 12
                        send(try ScrcpyControlMessage.touch(action: 2, x: x + (endX - x) * fraction, y: y + (endY - y) * fraction, width: dimensions.width, height: dimensions.height))
                    }
                }
                send(try ScrcpyControlMessage.touch(action: 1, x: endX, y: endY, width: dimensions.width, height: dimensions.height))
            } catch { }
        }
    }

    private func fail(_ message: String) {
        close()
        onFailure?(message)
    }
}
