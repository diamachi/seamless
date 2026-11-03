import Foundation

public struct CameraPreferences: Codable, Equatable, Sendable {
    public enum Facing: String, Codable, CaseIterable, Sendable {
        case back
        case front
    }

    public var facing: Facing = .back
    public var resolutionHeight: Int = 1080
    public var framesPerSecond: Int = 60
    public var automaticallyAdjustQuality: Bool = true

    public var exposureEV = 0.0
    public var zoom = 1.0
    public var torch = false
    public var whiteBalance = "auto"

    private enum CodingKeys: String, CodingKey { case facing, resolutionHeight, framesPerSecond, automaticallyAdjustQuality, exposureEV, zoom, torch, whiteBalance }
    public init() {}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        facing = try container.decodeIfPresent(Facing.self, forKey: .facing) ?? .back
        resolutionHeight = try container.decodeIfPresent(Int.self, forKey: .resolutionHeight) ?? 1080
        framesPerSecond = try container.decodeIfPresent(Int.self, forKey: .framesPerSecond) ?? 30
        automaticallyAdjustQuality = try container.decodeIfPresent(Bool.self, forKey: .automaticallyAdjustQuality) ?? true
        exposureEV = try container.decodeIfPresent(Double.self, forKey: .exposureEV) ?? 0
        zoom = try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 1
        torch = try container.decodeIfPresent(Bool.self, forKey: .torch) ?? false
        whiteBalance = try container.decodeIfPresent(String.self, forKey: .whiteBalance) ?? "auto"
    }
}

public struct PhonePreferences: Codable, Equatable, Sendable {
    public var notifications = NotificationPolicy()
    public var camera = CameraPreferences()
    public var screenFramesPerSecond: Int = 60
    public var automaticallyShareMacClipboard = false
    public var automaticallyAcceptFiles = true
    public var previewColor = "sage"

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case notifications, camera, screenFramesPerSecond, automaticallyShareMacClipboard, automaticallyAcceptFiles, previewColor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        automaticallyAcceptFiles = try container.decodeIfPresent(Bool.self, forKey: .automaticallyAcceptFiles) ?? true
        previewColor = try container.decodeIfPresent(String.self, forKey: .previewColor) ?? "sage"
        notifications = try container.decode(NotificationPolicy.self, forKey: .notifications)
        camera = try container.decode(CameraPreferences.self, forKey: .camera)
        let savedFrameRate = try container.decode(Int.self, forKey: .screenFramesPerSecond)
        if savedFrameRate == 120 { screenFramesPerSecond = 60 }
        else { screenFramesPerSecond = savedFrameRate }
        automaticallyShareMacClipboard = try container.decodeIfPresent(Bool.self, forKey: .automaticallyShareMacClipboard) ?? false
    }

    public func validate() throws {
        guard screenFramesPerSecond == 60,
              [720, 1080, 1440, 2160].contains(camera.resolutionHeight),
              [24, 30, 60].contains(camera.framesPerSecond), camera.exposureEV.isFinite, (-3...3).contains(camera.exposureEV), camera.zoom.isFinite, (1...4).contains(camera.zoom) else {
            throw PreferencesError.invalidProfile
        }
    }
}

public enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 2
    public var appearance: AppAppearance = .system
    public var defaultPhonePreferences = PhonePreferences()
    public private(set) var rememberedPhones: [RememberedPhone] = []
    public private(set) var selectedPhoneID: String?

    public init() {}

    public var selectedPhone: RememberedPhone? {
        rememberedPhones.first { $0.id == selectedPhoneID }
    }

    public func featurePreferences(for phoneID: String?) throws -> PhonePreferences {
        guard let phoneID else { return defaultPhonePreferences }
        guard let phone = rememberedPhones.first(where: { $0.id == phoneID }) else {
            throw PreferencesError.unknownPhone
        }
        return phone.preferences
    }

    public mutating func updateFeaturePreferences(_ updated: PhonePreferences, for phoneID: String?) throws {
        try updated.validate()
        guard let phoneID else {
            defaultPhonePreferences = updated
            return
        }
        guard let index = rememberedPhones.firstIndex(where: { $0.id == phoneID }) else {
            throw PreferencesError.unknownPhone
        }
        rememberedPhones[index].preferences = updated
    }

    /// Called after authenticated pairing; metadata alone never establishes trust.
    public mutating func rememberPhone(id: String, displayName: String) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PreferencesError.invalidPhone
        }
        if let index = rememberedPhones.firstIndex(where: { $0.id == id }) {
            rememberedPhones[index].displayName = displayName
            return
        }
        let isFirstPhone = rememberedPhones.isEmpty
        rememberedPhones.append(RememberedPhone(id: id, displayName: displayName, preferences: defaultPhonePreferences))
        if isFirstPhone {
            selectedPhoneID = id
        }
    }

    public mutating func renamePhone(id: String, name: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 80,
              let index = rememberedPhones.firstIndex(where: { $0.id == id }) else { throw PreferencesError.invalidPhone }
        rememberedPhones[index].displayName = trimmedName
    }

    public mutating func selectPhone(id: String?) throws {
        if let id, !rememberedPhones.contains(where: { $0.id == id }) {
            throw PreferencesError.unknownPhone
        }
        selectedPhoneID = id
    }

    public mutating func updateConnection(_ profile: ConnectionProfile, for phoneID: String) throws {
        guard let index = rememberedPhones.firstIndex(where: { $0.id == phoneID }) else {
            throw PreferencesError.unknownPhone
        }
        rememberedPhones[index].connection = profile
    }

    public mutating func removePhoneMetadata(id: String) {
        rememberedPhones.removeAll { $0.id == id }
        if selectedPhoneID == id {
            // Never redirect subsequent actions to a different phone implicitly.
            selectedPhoneID = nil
        }
    }

    public func validate() throws {
        guard schemaVersion == 2 else { throw PreferencesError.unsupportedVersion }
        try defaultPhonePreferences.validate()
        let identifiers = rememberedPhones.map(\.id)
        guard Set(identifiers).count == identifiers.count else { throw PreferencesError.invalidPhone }
        for phone in rememberedPhones {
            guard !phone.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !phone.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PreferencesError.invalidPhone
            }
            try phone.preferences.validate()
            if let connection = phone.connection {
                guard !connection.host.isEmpty, connection.host.count <= 255, connection.port > 0,
                      connection.certificatePin.count == 64, connection.certificatePin.allSatisfy(\.isHexDigit) else {
                    throw PreferencesError.invalidPhone
                }
            }
        }
        if let selectedPhoneID, !identifiers.contains(selectedPhoneID) {
            throw PreferencesError.unknownPhone
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, defaultPhonePreferences, rememberedPhones, selectedPhoneID, appearance
        case notifications, camera, screenFramesPerSecond
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        appearance = try container.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        if version == 1 {
            // Preserve original settings as defaults without inventing a paired phone.
            defaultPhonePreferences.notifications = try container.decode(NotificationPolicy.self, forKey: .notifications)
            defaultPhonePreferences.camera = try container.decode(CameraPreferences.self, forKey: .camera)
            let savedFrameRate = try container.decode(Int.self, forKey: .screenFramesPerSecond)
            if savedFrameRate == 120 { defaultPhonePreferences.screenFramesPerSecond = 60 }
            else { defaultPhonePreferences.screenFramesPerSecond = savedFrameRate }
        } else if version == 2 {
            defaultPhonePreferences = try container.decode(PhonePreferences.self, forKey: .defaultPhonePreferences)
            rememberedPhones = try container.decode([RememberedPhone].self, forKey: .rememberedPhones)
            selectedPhoneID = try container.decodeIfPresent(String.self, forKey: .selectedPhoneID)
        } else {
            throw PreferencesError.unsupportedVersion
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(defaultPhonePreferences, forKey: .defaultPhonePreferences)
        try container.encode(rememberedPhones, forKey: .rememberedPhones)
        try container.encodeIfPresent(selectedPhoneID, forKey: .selectedPhoneID)
    }
}

public enum PreferencesError: LocalizedError {
    case unsupportedVersion
    case invalidProfile
    case invalidPhone
    case unknownPhone

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "These preferences were created by a newer version of Seamless."
        case .invalidProfile:
            return "The saved camera or screen profile is invalid."
        case .invalidPhone:
            return "A saved phone has an invalid or duplicate identity."
        case .unknownPhone:
            return "This phone is no longer saved. Select another phone."
        }
    }
}
