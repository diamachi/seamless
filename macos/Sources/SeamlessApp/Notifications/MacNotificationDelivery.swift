import AppKit
import Combine
import UserNotifications

@MainActor
final class MacNotificationDelivery: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = MacNotificationDelivery()
    @Published private(set) var status = "Checking notification access…"
    @Published private(set) var lastError = ""
    @Published private(set) var canShowBanners = false
    var onCallAction: ((String, String, String) -> Void)?

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        let answer = UNNotificationAction(identifier: "answer-call", title: "Answer on Mac", options: [.foreground])
        let decline = UNNotificationAction(identifier: "decline-call", title: "Decline", options: [.destructive])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "incoming-call", actions: [answer, decline], intentIdentifiers: [])
        ])
        Task { await refresh() }
    }

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        canShowBanners = settings.authorizationStatus == .authorized && settings.alertSetting == .enabled && settings.alertStyle != .none
        if settings.authorizationStatus == .notDetermined { status = "Mac notification access has not been requested." }
        else if settings.authorizationStatus == .denied { status = "Mac notification banners are not allowed. Enable Seamless in System Settings." }
        else if !canShowBanners { status = "Alerts are quiet or banners are disabled in macOS notification settings." }
        else if settings.soundSetting != .enabled { status = "Banners are enabled; notification sounds are off in macOS. Enable Play sound for Seamless in System Settings." }
        else { status = "Mac notification banners and sounds are enabled." }
    }

    @discardableResult func requestAuthorization() async -> Bool {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refresh()
            return allowed
        } catch {
            lastError = error.localizedDescription
            await refresh()
            return false
        }
    }

    func reviewAccess() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined { _ = await requestAuthorization() }
            else { openSettings() }
        }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") { NSWorkspace.shared.open(url) }
    }

    func deliver(identifier: String, title: String, body: String, quiet: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if !quiet { content.sound = .default }
        if quiet { content.interruptionLevel = .passive }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                await refresh()
                return
            }
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
                lastError = ""
            } catch { lastError = error.localizedDescription }
        }
    }

    func incomingCall(phoneID: String, caller: String, token: String) {
        let content = UNMutableNotificationContent()
        content.title = "Incoming phone call"
        content.body = caller.isEmpty ? "Unknown caller" : caller
        content.categoryIdentifier = "incoming-call"
        content.userInfo = ["phoneID": phoneID, "callToken": token]
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "incoming-call-" + phoneID,
                                                                     content: content, trigger: nil))
    }

    func clearIncomingCall(phoneID: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["incoming-call-" + phoneID])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let phoneID = info["phoneID"] as? String, let token = info["callToken"] as? String else { return }
        let action = response.actionIdentifier
        await handleCallAction(phoneID: phoneID, token: token, action: action)
    }

    private func handleCallAction(phoneID: String, token: String, action: String) {
        onCallAction?(phoneID, token, action)
    }

    func postLocalTest() {
        deliver(identifier: "seamless-local-test", title: "Seamless notifications are ready", body: "This is a local Mac test. No message was sent to anyone.")
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // macOS otherwise suppresses alerts while our own window is in the foreground.
        if notification.request.content.interruptionLevel == .passive { return [.list] }
        return [.banner, .list, .sound]
    }
}
