import Foundation
import Darwin
import IOKit
import SeamlessCore

struct MacDetailsSnapshot {
    static func payload() -> JSONValue {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "Apple silicon"
        #else
        let architecture = "Intel"
        #endif
        let model = systemString("hw.model") ?? "Mac"
        let storage = storageCapacity()
        return .object([
            "operatingSystem": .string("macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"),
            "model": .string(model), "deviceFamily": .string(deviceFamily(model: model)),
            "processor": .string(systemString("machdep.cpu.brand_string") ?? architecture),
            "architecture": .string(architecture), "ramBytes": .number(Double(ProcessInfo.processInfo.physicalMemory)),
            "storageTotalBytes": .number(Double(storage.total)), "storageUsedBytes": .number(Double(storage.used)),
            "appVersion": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
        ])
    }

    private static func systemString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size < 256 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }

    private static func deviceFamily(model: String) -> String {
        if model.hasPrefix("MacBookPro") { return "MacBook Pro" }
        if model.hasPrefix("MacBookAir") { return "MacBook Air" }
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if battery != 0 {
            IOObjectRelease(battery)
            return "MacBook"
        }
        return "Mac"
    }

    private static func storageCapacity() -> (total: Int64, used: Int64) {
        let values = try? URL.homeDirectory.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        guard let total = values?.volumeTotalCapacity, let available = values?.volumeAvailableCapacity, total > 0 else { return (0, 0) }
        return (Int64(total), Int64(max(0, total - available)))
    }
}
