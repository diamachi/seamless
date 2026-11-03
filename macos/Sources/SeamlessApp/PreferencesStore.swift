import Foundation
import SwiftUI
import SeamlessCore
import Combine

@MainActor
final class PreferencesStore: ObservableObject {
    @Published private(set) var preferences = AppPreferences()
    @Published private(set) var errorMessage: String?
    @Published private(set) var canSave = false
    let connections = PhoneConnections()
    let calls = CallsCoordinator()
    let setup = SetupCoordinator()
    let wallpapers = PhoneWallpaperStore()
    var sessions: PhoneSessionDirectory { connections.sessions }
    private var connectionObservation: AnyCancellable?
    private var hasStartedConnections = false
    private let repository: PreferencesRepository

    init() {
        let supportDirectory = URL.applicationSupportDirectory
            .appending(path: "Seamless", directoryHint: .isDirectory)
        repository = PreferencesRepository(
            fileURL: supportDirectory.appending(path: "preferences.json")
        )
        do {
            preferences = try repository.load()
            canSave = true
        } catch {
            // Preserve unreadable or newer settings until the user can recover them.
            errorMessage = error.localizedDescription
        }
        connections.onPaired = { [weak self] phoneID, name, profile in
            guard let self else { return }
            try self.preferences.rememberPhone(id: phoneID, displayName: name)
            try self.preferences.updateConnection(profile, for: phoneID)
            self.save()
        }
        connections.onEndpointChanged = { [weak self] phoneID, profile in
            guard let self else { return }
            try self.preferences.updateConnection(profile, for: phoneID)
            self.save()
        }
        connections.onForgotten = { [weak self] phoneID in
            guard let self else { return }
            self.calls.forget(phoneID: phoneID)
            self.wallpapers.remove(phoneID: phoneID)
            self.preferences.removePhoneMetadata(id: phoneID)
            self.save()
        }
        connections.synchronize(with: preferences)
        connectionObservation = connections.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func save(synchronizeConnections: Bool = true) {
        guard canSave else { return }
        do {
            try repository.save(preferences)
            if synchronizeConnections { connections.synchronize(with: preferences) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startConnections() {
        guard !hasStartedConnections else { return }
        hasStartedConnections = true
        applyAppearance()
        connections.reconnectSavedPhones()
        if let phoneID = preferences.selectedPhoneID, calls.options(for: phoneID).reconnectOnLaunch {
            calls.connect(phoneID: phoneID)
        }
        let arguments = CommandLine.arguments
        if let option = arguments.firstIndex(of: "--pairing-file"), option + 1 < arguments.count {
            do {
                let url = URL(fileURLWithPath: arguments[option + 1])
                let data = try Data(contentsOf: url)
                guard data.count <= 16_384, let code = String(data: data, encoding: .utf8) else {
                    throw ConnectionProtocolError.invalidInvitation
                }
                connections.pairingCode = code
                connections.pair()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func setNotificationApplication(_ application: AndroidApplicationIdentity, enabled: Bool) {
        do {
            let phoneID = preferences.selectedPhoneID
            var settings = try preferences.featurePreferences(for: phoneID)
            if enabled { settings.notifications.allowedApplications.insert(application) }
            else { settings.notifications.allowedApplications.remove(application) }
            try preferences.updateFeaturePreferences(settings, for: phoneID)
            save()
        } catch { errorMessage = error.localizedDescription }
    }

    func setAppearance(_ appearance: AppAppearance) {
        guard canSave else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { preferences.appearance = appearance }
        applyAppearance()
        save(synchronizeConnections: false)
    }

    func renamePhone(id: String, name: String) {
        do { try preferences.renamePhone(id: id, name: name); save() }
        catch { errorMessage = error.localizedDescription }
    }

    func applyAppearance() {
        let appearance: NSAppearance?
        switch preferences.appearance {
        case .system: appearance = nil
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        }
        NSApplication.shared.appearance = appearance
        AppIconController.shared.update()
        // AppKit propagates one appearance to all windows; avoid competing window and SwiftUI overrides.
    }

    func selectPhone(id: String?) {
        guard canSave else { return }
        do {
            try preferences.selectPhone(id: id)
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var featurePreferences: Binding<PhonePreferences> {
        // Keep delayed edits addressed to their original phone when selection changes.
        let phoneID = preferences.selectedPhoneID
        return Binding(
            get: {
                do {
                    return try self.preferences.featurePreferences(for: phoneID)
                } catch {
                    return PhonePreferences()
                }
            },
            set: { updated in
                guard self.canSave else { return }
                do {
                    try self.preferences.updateFeaturePreferences(updated, for: phoneID)
                    self.save()
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        )
    }
}
