import Foundation

struct AndroidToolFailure: LocalizedError {
    let description: String
    var errorDescription: String? { description }
}

struct AndroidToolRunner {
    static func find(_ name: String) -> URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)")
        let paths = [bundled.path, "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)",
                     "/opt/homebrew/share/android-commandlinetools/platform-tools/\(name)"]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    static func run(_ executable: URL, arguments: [String], timeout: TimeInterval = 15) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try process.run()
                let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                defer { deadline.cancel(); try? pipe.fileHandleForReading.close() }
                var output = Data()
                while let bytes = try pipe.fileHandleForReading.read(upToCount: 16_384), !bytes.isEmpty {
                    if output.count + bytes.count > 1_048_576 {
                        if process.isRunning { process.terminate() }
                        throw AndroidToolFailure(description: "Android tool returned too much output.")
                    }
                    output.append(bytes)
                }
                process.waitUntilExit()
                let text = String(decoding: output, as: UTF8.self)
                guard process.terminationStatus == 0 else { throw AndroidToolFailure(description: String(text.suffix(600)).isEmpty ? "Android tool stopped or timed out." : String(text.suffix(600))) }
                return text
            }.value
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
