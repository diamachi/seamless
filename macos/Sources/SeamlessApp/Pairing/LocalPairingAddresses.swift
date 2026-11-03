import Darwin
import Foundation

struct LocalPairingAddresses {
    static func available() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return [] }
        defer { freeifaddrs(interfaces) }
        var addresses: [String] = []
        var current = interfaces
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0,
                  let socketAddress = entry.pointee.ifa_addr, Int32(socketAddress.pointee.sa_family) == AF_INET else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(socketAddress, socklen_t(socketAddress.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: host)
                if !value.hasPrefix("169.254."), !addresses.contains(value) { addresses.append(value) }
            }
        }
        return Array(addresses.prefix(8))
    }
}
