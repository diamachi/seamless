import Foundation

public struct AndroidDebugDevice: Identifiable, Equatable, Sendable {
    public let serial: String
    public let state: String
    public let model: String
    public let isUSB: Bool
    public var id: String { serial }

    public static func parseList(_ output: String) -> [AndroidDebugDevice] {
        var devices: [AndroidDebugDevice] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields[0] != "List", isValidSerial(fields[0]) else { continue }
            let metadata = fields.dropFirst(2)
            let model = metadata.first(where: { $0.hasPrefix("model:") })?.dropFirst(6).replacingOccurrences(of: "_", with: " ") ?? fields[0]
            let isWireless = fields[0].contains(":") || fields[0].contains("_adb-tls-")
            let isUSB = metadata.contains(where: { $0.hasPrefix("usb:") }) || !isWireless
            devices.append(AndroidDebugDevice(serial: fields[0], state: fields[1], model: model, isUSB: isUSB))
        }
        return devices
    }

    public static func isValidSerial(_ serial: String) -> Bool {
        guard !serial.isEmpty, serial.count <= 200, !serial.hasPrefix("-") else { return false }
        return serial.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-").contains(scalar)
        }
    }
}

public enum AndroidDebugBridgePlan {
    public static func forward(serial: String, remotePort: UInt16) throws -> [String] {
        guard AndroidDebugDevice.isValidSerial(serial), remotePort > 0 else { throw PlanError.invalidDevice }
        return ["-s", serial, "forward", "tcp:0", "tcp:\(remotePort)"]
    }

    public static func removeForward(serial: String, localPort: UInt16) throws -> [String] {
        guard AndroidDebugDevice.isValidSerial(serial), localPort > 0 else { throw PlanError.invalidDevice }
        return ["-s", serial, "forward", "--remove", "tcp:\(localPort)"]
    }

    public static func validatePackageName(_ packageName: String) throws {
        if !isValidPackageName(packageName) { throw PlanError.invalidDevice }
    }

    private static func isValidPackageName(_ name: String) -> Bool {
        guard name.count <= 255 else { return false }
        let components = name.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2 else { return false }
        for component in components {
            guard let first = component.unicodeScalars.first, CharacterSet.letters.contains(first) else { return false }
            if !component.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_").contains($0) }) { return false }
        }
        return true
    }

    public enum PlanError: LocalizedError {
        case invalidDevice
        public var errorDescription: String? { "Choose a valid authorized Android device and application." }
    }
}
