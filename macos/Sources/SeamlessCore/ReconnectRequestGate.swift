import Foundation

/// Discovery can request a connection attempt, but cannot authorize a connection.
public struct ReconnectRequestGate {
    private var recentRequests: [String: [String]] = [:]
    private var lastAttemptDates: [String: Date] = [:]

    public init() {}

    public mutating func accept(phoneID: String, requestID: String, now: Date = Date()) -> Bool {
        guard UUID(uuidString: requestID) != nil else { return false }
        let previousRequests = recentRequests[phoneID] ?? []
        guard !previousRequests.contains(requestID) else { return false }
        if let previousDate = lastAttemptDates[phoneID], now.timeIntervalSince(previousDate) < 10 {
            return false
        }
        recentRequests[phoneID] = Array((previousRequests + [requestID]).suffix(16))
        lastAttemptDates[phoneID] = now
        return true
    }
}
