import Foundation

struct PhoneCallingOptions: Codable {
    var bluetoothAddress = ""
    var microphoneUID = "system"
    var speakerUID = "system"
    var phoneInputUID = ""
    var phoneOutputUID = ""
    var reconnectOnLaunch = false

    private enum CodingKeys: String, CodingKey {
        case bluetoothAddress, microphoneUID, speakerUID, phoneInputUID, phoneOutputUID, reconnectOnLaunch
    }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bluetoothAddress = try values.decodeIfPresent(String.self, forKey: .bluetoothAddress) ?? ""
        microphoneUID = try values.decodeIfPresent(String.self, forKey: .microphoneUID) ?? "system"
        speakerUID = try values.decodeIfPresent(String.self, forKey: .speakerUID) ?? "system"
        phoneInputUID = try values.decodeIfPresent(String.self, forKey: .phoneInputUID) ?? ""
        phoneOutputUID = try values.decodeIfPresent(String.self, forKey: .phoneOutputUID) ?? ""
        reconnectOnLaunch = try values.decodeIfPresent(Bool.self, forKey: .reconnectOnLaunch) ?? false
    }
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
