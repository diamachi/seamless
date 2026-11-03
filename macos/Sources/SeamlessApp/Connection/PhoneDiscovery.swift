import Darwin
import Foundation
import SeamlessCore

@MainActor
final class PhoneDiscovery: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    var onEndpoint: ((String, DiscoveredPhoneEndpoint?) -> Void)?
    var onReconnectRequest: ((String) -> Void)?
    private var reconnectRequestGate = ReconnectRequestGate()
    private let browser = NetServiceBrowser()
    private var services: [String: NetService] = [:]
    private var endpoints: [String: DiscoveredPhoneEndpoint] = [:]
    private var endpointServiceNames: [String: String] = [:]
    private var knownPhoneIDs: Set<String> = []
    private var started = false

    func start(knownPhoneIDs: Set<String>) {
        self.knownPhoneIDs = knownPhoneIDs
        guard !started else { return }
        started = true
        // Foundation delivers these delegate calls on the main run loop used to start browsing.
        browser.delegate = self
        browser.searchForServices(ofType: "_seamless._tcp.", inDomain: "local.")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard services.count < 32, let phoneID = phoneID(for: service), knownPhoneIDs.contains(phoneID) else { return }
        services[service.name] = service
        service.delegate = self
        service.startMonitoring()
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ service: NetService) {
        guard let host = ipv4Address(for: service) ?? service.hostName,
              let endpoint = DiscoveredPhoneEndpoint(serviceName: service.name, host: host, port: service.port),
              knownPhoneIDs.contains(endpoint.phoneID) else { return }
        let phoneID = endpoint.phoneID
        endpointServiceNames[phoneID] = service.name
        if endpoints[phoneID] != endpoint {
            endpoints[phoneID] = endpoint
            onEndpoint?(phoneID, endpoint)
        }
        if let record = service.txtRecordData() {
            receiveReconnectRequest(service: service, record: record)
        }
    }

    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        receiveReconnectRequest(service: sender, record: data)
    }

    private func receiveReconnectRequest(service: NetService, record: Data) {
        guard let phoneID = phoneID(for: service), knownPhoneIDs.contains(phoneID),
              endpointServiceNames[phoneID] == service.name else { return }
        let attributes = NetService.dictionary(fromTXTRecord: record)
        guard let data = attributes["reconnect"], let requestID = String(data: data, encoding: .utf8),
              reconnectRequestGate.accept(phoneID: phoneID, requestID: requestID) else { return }
        onReconnectRequest?(phoneID)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        if let removed = services.removeValue(forKey: service.name) {
            removed.stopMonitoring()
            removed.stop()
        }
        guard let phoneID = phoneID(for: service), endpointServiceNames[phoneID] == service.name else { return }
        endpointServiceNames.removeValue(forKey: phoneID)
        endpoints.removeValue(forKey: phoneID)
        onEndpoint?(phoneID, nil)
    }

    func netService(_ service: NetService, didNotResolve errorDict: [String: NSNumber]) {
        if let removed = services.removeValue(forKey: service.name) {
            removed.stopMonitoring()
            removed.stop()
        }
    }

    private func ipv4Address(for service: NetService) -> String? {
        for address in service.addresses ?? [] {
            guard address.count >= MemoryLayout<sockaddr_in>.size,
                  address.count <= MemoryLayout<sockaddr_storage>.size else { continue }
            var storage = sockaddr_storage()
            _ = withUnsafeMutableBytes(of: &storage) { address.copyBytes(to: $0) }
            guard Int32(storage.ss_family) == AF_INET else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = withUnsafePointer(to: &storage) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    getnameinfo(socketAddress, socklen_t(address.count), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                }
            }
            if result == 0 { return String(cString: host) }
        }
        return nil
    }

    private func phoneID(for service: NetService) -> String? {
        DiscoveredPhoneEndpoint.phoneIdentifier(serviceName: service.name)
    }
}
