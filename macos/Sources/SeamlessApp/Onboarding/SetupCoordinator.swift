// Tracks resumable Mac onboarding and system permission status. Restarting the guide preserves existing trust and OS grants.

import AppKit
import AVFoundation
import Combine
import CoreBluetooth
import UserNotifications

@MainActor
final class SetupCoordinator: ObservableObject {
    @Published var isPresented = false
    @Published var step = 0 { didSet { defaults.set(step, forKey: "seamless.setup.step") } }
    @Published private(set) var microphoneStatus = "Not requested"
    @Published private(set) var bluetoothStatus = "Not requested"
    @Published private(set) var notificationStatus = "Checking…"
    @Published private(set) var message = ""
    @Published private(set) var isRequestingAccess = false
    private let defaults = UserDefaults.standard

    /// Returns onboarding to Welcome without revoking trust, changing feature choices or resetting OS permissions.
    func restart() {
        step = 0
        isPresented = true
        refresh()
    }

    /// Performs present for setup coordinator.
    func present() { step = min(5, max(0, defaults.integer(forKey: "seamless.setup.step"))); isPresented = true; refresh() }
    /// Performs offer first run for setup coordinator.
    func offerFirstRun(hasSavedPhone: Bool) {
        if !hasSavedPhone && !defaults.bool(forKey: "seamless.setup.presented") {
            defaults.set(true, forKey: "seamless.setup.presented")
            present()
        }
    }
    /// Completes the current workflow and publishes its resulting state.
    func finish() {
        defaults.set(true, forKey: "seamless.setup.completed")
        defaults.set(0, forKey: "seamless.setup.step")
        isPresented = false
    }

    /// Refreshes the model from its current system or transport source.
    func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphoneStatus = "Allowed"
        case .denied, .restricted: microphoneStatus = "Not allowed"
        default: microphoneStatus = "Not requested"
        }
        switch CBManager.authorization {
        case .allowedAlways: bluetoothStatus = "Allowed"
        case .denied, .restricted: bluetoothStatus = "Not allowed"
        default: bluetoothStatus = "Not requested"
        }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: notificationStatus = "Allowed"
            case .denied: notificationStatus = "Not allowed"
            default: notificationStatus = "Not requested"
            }
        }
    }

    /// Performs request recommended access for setup coordinator.
    func requestRecommendedAccess(calls: CallsCoordinator) {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        Task {
            let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
            if notificationSettings.authorizationStatus == .notDetermined {
                _ = await MacNotificationDelivery.shared.requestAuthorization()
            }
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            }
            if CBManager.authorization == .notDetermined { calls.discoverPairedPhones() }
            message = "Available one-time prompts were requested. Previously denied access must be changed with Review access in System Settings."
            isRequestingAccess = false
            refresh()
        }
    }

    /// Performs request microphone for setup coordinator.
    func requestMicrophone() {
        Task {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else { openSettings("Privacy_Microphone") }
            refresh()
        }
    }

    /// Performs request notifications for setup coordinator.
    func requestNotifications() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                if !granted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") { NSWorkspace.shared.open(url) }
            } catch { message = error.localizedDescription }
            refresh()
        }
    }

    /// Performs open settings for setup coordinator.
    func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) { NSWorkspace.shared.open(url) }
    }
}
