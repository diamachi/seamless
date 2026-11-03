import Foundation

struct PhoneCallingOptions: Codable {
    var bluetoothAddress = ""
    var microphoneUID = "system"
    var speakerUID = "system"
    var phoneInputUID = ""
    var phoneOutputUID = ""
}

@MainActor
final class CallsPreferences {
    private let key = "dev.seamless.calls.options"
    private var phones: [String: PhoneCallingOptions]
    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: PhoneCallingOptions].self, from: data) {
            phones = decoded
        } else {
            phones = [:]
        }
    }
    func options(for phoneID: String) -> PhoneCallingOptions { phones[phoneID] ?? PhoneCallingOptions() }
    func save(_ options: PhoneCallingOptions, for phoneID: String) {
        phones[phoneID] = options
        persist()
    }
    func remove(phoneID: String) { phones.removeValue(forKey: phoneID); persist() }
    private func persist() {
        if let data = try? JSONEncoder().encode(phones) { UserDefaults.standard.set(data, forKey: key) }
    }
}
