import AppKit
import AVFoundation
import Combine
import CoreBluetooth
import UserNotifications

@MainActor
final class SetupCoordinator: ObservableObject {
    @Published var isPresented = false
    @Published var step = 0
    @Published private(set) var microphoneStatus = "Not requested"
    @Published private(set) var bluetoothStatus = "Not requested"
    @Published private(set) var notificationStatus = "Checking…"
    @Published private(set) var message = ""
    @Published private(set) var isRequestingAccess = false
    private let defaults = UserDefaults.standard

    func present() { step = 0; isPresented = true; refresh() }
    func offerFirstRun(hasSavedPhone: Bool) {
        if !hasSavedPhone && !defaults.bool(forKey: "seamless.setup.presented") {
            defaults.set(true, forKey: "seamless.setup.presented")
            present()
        }
    }
    func finish() {
        defaults.set(true, forKey: "seamless.setup.completed")
        isPresented = false
    }

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

    func requestMicrophone() {
        Task {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else { openSettings("Privacy_Microphone") }
            refresh()
        }
    }

    func requestNotifications() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                if !granted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") { NSWorkspace.shared.open(url) }
            } catch { message = error.localizedDescription }
            refresh()
        }
    }

    func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor) { NSWorkspace.shared.open(url) }
    }
}
