import Foundation
import SwiftUI
import AppKit
import UserNotifications
import SeamlessCore

struct ConnectedPhoneStatus {
    let model: String
    let androidVersion: String
    let batteryPercent: Int
    let isCharging: Bool
    let receivedAt: Date
    let deviceDetails: DeviceDetails
}

struct PhoneApplication: Identifiable {
    let identity: AndroidApplicationIdentity
    let name: String
    let icon: NSImage?
    var id: String { identity.packageName + ":" + identity.profileIdentifier }
}

struct RelayedNotification: Identifiable {
    let id: String
    let phoneID: String
    let application: AndroidApplicationIdentity
    let title: String
    let text: String
    let actions: [JSONValue]
    let icon: NSImage?
}

@MainActor
final class PhoneConnections: ObservableObject {
    @Published private(set) var sessions = PhoneSessionDirectory()
    @Published private(set) var statuses: [String: ConnectedPhoneStatus] = [:]
    @Published private(set) var applications: [String: [PhoneApplication]] = [:]
    @Published private(set) var notifications: [RelayedNotification] = []
    @Published private(set) var phonePermissions: [String: [String: Bool]] = [:]
    private var metadataSentPhones = Set<String>()
    private var metadataLastSent: [String: Date] = [:]
    @Published private(set) var ringingPhones: Set<String> = []
    private var ringTasks: [String: Task<Void, Never>] = [:]
    @Published var pairingCode = ""
    @Published var hostOverride = ""
    @Published private(set) var message = "Pair a phone to get started."
    var onPaired: ((String, String, ConnectionProfile) throws -> Void)?
    var onEndpointChanged: ((String, ConnectionProfile) throws -> Void)?
    var onForgotten: ((String) -> Void)?
    let usb = USBConnectionController()
    let advancedMirroring = AdvancedMirroringController()
    private var usbProfiles: [String: ConnectionProfile] = [:]
    let clipboardHistory = ClipboardHistory()
    let files = FileTransfers()
    let bulk = BulkTransfers()
    let storage = PhoneStorageBrowser()
    private var activeProfiles: [String: ConnectionProfile] = [:]
    let screen = PhoneVideoStreamController()
    let camera = PhoneVideoStreamController(purpose: .camera)
    private let discovery = PhoneDiscovery()
    private var discoveredEndpoints: [String: DiscoveredPhoneEndpoint] = [:]
    private let credentials = PeerCredentialStore()
    private var clients: [String: PhoneControlClient] = [:]
    private var savedPhones: [String: RememberedPhone] = [:]
    private var pendingInvitations: [String: PairingInvitation] = [:]
    private var reconnectTasks: [String: Task<Void, Never>] = [:]
    private var reconnectAttempts: [String: Int] = [:]
    private var reconnectEnabled: Set<String> = []
    private var activePhoneID: String?
    private var clipboardTimer: Timer?
    private var lastPasteboardChange = NSPasteboard.general.changeCount
    private var pendingUnpair: Set<String> = []
    private var sessionCredentials: [String: String] = [:]
    private var authenticationAttempts: [String: UUID] = [:]

    init() {
        advancedMirroring.onBegin = { [weak self] phoneID in
            guard let self else { return }
            self.screen.beginExternal(phoneID: phoneID,
                stop: { [weak self] in self?.advancedMirroring.stop(phoneID: phoneID) },
                input: { [weak self] kind, coordinates, text in self?.advancedMirroring.input(kind: kind, coordinates: coordinates, text: text) })
        }
        advancedMirroring.onRecord = { [weak self] record in self?.screen.receiveExternal(record) }
        advancedMirroring.onEnd = { [weak self] phoneID in self?.screen.ended(phoneID: phoneID) }
        usb.useTunnel = { [weak self] phoneID, profile in
            guard let self, let phone = self.savedPhones[phoneID] else { return }
            self.usbProfiles[phoneID] = profile
            self.reconnect(phone)
        }
        usb.removeTunnel = { [weak self] phoneID, reconnectWiFi in
            guard let self else { return }
            self.usbProfiles.removeValue(forKey: phoneID)
            if reconnectWiFi, let phone = self.savedPhones[phoneID] { self.reconnect(phone) }
        }
        discovery.onEndpoint = { [weak self] phoneID, endpoint in
            guard let self else { return }
            self.discoveredEndpoints[phoneID] = endpoint
            if endpoint != nil, self.reconnectEnabled.contains(phoneID),
               self.sessions.state(for: phoneID) != .connected,
               let phone = self.savedPhones[phoneID] {
                self.reconnect(phone)
            }
        }
        discovery.onReconnectRequest = { [weak self] phoneID in
            guard let self, let phone = self.savedPhones[phoneID],
                  self.sessions.state(for: phoneID) != .connected else { return }
            self.reconnect(phone)
        }
        screen.send = { [weak self] phoneID, packet in self?.send(phoneID: phoneID, packet: packet) }
        camera.send = { [weak self] phoneID, packet in self?.send(phoneID: phoneID, packet: packet) }
        bulk.automaticallyAccept = { [weak self] phoneID in self?.savedPhones[phoneID]?.preferences.automaticallyAcceptFiles == true }
        bulk.send = { [weak self] phoneID, packet in self?.send(phoneID: phoneID, packet: packet) }
        storage.folderDownloads.send = { [weak self] phoneID, packet in self?.send(phoneID: phoneID, packet: packet) }
        storage.send = { [weak self] phoneID, packet in self?.send(phoneID: phoneID, packet: packet) }
        bulk.authentication = { [weak self] phoneID, transferID, direction in
            guard let self, self.sessions.state(for: phoneID) == .connected,
                  let profile = self.activeProfiles[phoneID], let credential = self.sessionCredentials[phoneID] else { throw ConnectionProtocolError.invalidMessage }
            return (profile, ControlPacket(type: "bulkAuthenticate", payload: .object([
                "macID": .string(self.macID), "credential": .string(credential),
                "transferID": .string(transferID), "direction": .string(direction)
            ])))
        }
        files.send = { [weak self] phoneID, packet in self?.send(phoneID: phoneID, packet: packet) }
        files.sendAndWait = { [weak self] phoneID, packet in
            guard let self else { throw ConnectionProtocolError.invalidMessage }
            _ = try self.sessions.requireConnectedPhone(id: phoneID)
            guard let client = self.clients[phoneID] else { throw ConnectionProtocolError.invalidMessage }
            try await client.sendAndWait(packet)
        }
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollClipboard() }
        }
    }

    func synchronize(with preferences: AppPreferences) {
        let previous = savedPhones
        savedPhones = Dictionary(uniqueKeysWithValues: preferences.rememberedPhones.map { ($0.id, $0) })
        discovery.start(knownPhoneIDs: Set(savedPhones.keys))
        if activePhoneID != preferences.selectedPhoneID {
            screen.stop()
            lastPasteboardChange = NSPasteboard.general.changeCount
        }
        activePhoneID = preferences.selectedPhoneID
        for phone in preferences.rememberedPhones {
            if previous[phone.id]?.preferences.notifications != phone.preferences.notifications {
                sendNotificationPolicy(phoneID: phone.id)
            }
        }
        let removedNotifications = notifications.filter { notification in
            guard let phone = savedPhones[notification.phoneID] else { return true }
            return !phone.preferences.notifications.permits(notification.application)
        }
        let removedIDs = removedNotifications.map { $0.phoneID + $0.id }
        notifications.removeAll { notification in removedNotifications.contains { $0.phoneID == notification.phoneID && $0.id == notification.id } }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: removedIDs)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: removedIDs)
    }

    func pair() {
        do {
            let invitation = try PairingInvitation.parse(pairingCode)
            let host = hostOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = ConnectionProfile(host: host.isEmpty ? invitation.addresses[0] : host,
                port: invitation.port, certificatePin: invitation.certificatePin)
            pendingInvitations[invitation.phoneID] = invitation
            let client = makeClient(phoneID: invitation.phoneID, profile: profile)
            client.connect(profile: profile, authentication: ControlPacket(type: "pair", payload: .object([
                "macID": .string(macID), "macName": .string(Host.current().localizedName ?? "Mac"), "secret": .string(invitation.secret)
            ])))
            pairingCode = ""
            message = "Approve the pairing request on \(invitation.name)."
        } catch { message = error.localizedDescription }
    }

    func reconnect(_ phone: RememberedPhone) {
        guard let savedProfile = phone.connection else { message = "Pair this phone again."; return }
        let profile: ConnectionProfile
        if let usbProfile = usbProfiles[phone.id] {
            profile = usbProfile
        } else if let endpoint = discoveredEndpoints[phone.id], let discoveredProfile = endpoint.connectionProfile(for: phone) {
            profile = discoveredProfile
        } else {
            profile = savedProfile
        }
        let attempt = UUID()
        authenticationAttempts[phone.id] = attempt
        reconnectEnabled.insert(phone.id)
        sessions.update(.connecting, for: phone.id)
        Task { [weak self] in
            guard let self else { return }
            do {
                let storedCredential = try await self.credentials.credential(for: phone.id)
                guard self.authenticationAttempts[phone.id] == attempt, self.reconnectEnabled.contains(phone.id) else { return }
                guard let credential = storedCredential else {
                    self.sessions.update(.disconnected, for: phone.id)
                    self.message = "Create a new pairing code on \(phone.displayName)."
                    return
                }
                self.sessionCredentials[phone.id] = credential
                let client = self.makeClient(phoneID: phone.id, profile: profile)
                client.connect(profile: profile, authentication: ControlPacket(type: "authenticate", payload: .object([
                    "macID": .string(self.macID), "macName": .string(Host.current().localizedName ?? "Mac"), "credential": .string(credential)
                ])))
            } catch {
                guard self.authenticationAttempts[phone.id] == attempt else { return }
                self.reconnectEnabled.remove(phone.id)
                self.sessions.update(.disconnected, for: phone.id)
                self.message = error.localizedDescription
            }
        }
    }

    func shutdown() {
        reconnectEnabled.removeAll()
        for task in reconnectTasks.values { task.cancel() }
        reconnectTasks.removeAll()
        advancedMirroring.stopAll()
        screen.stop()
        camera.stop()
        usb.shutdown()
        for client in clients.values { client.onState = nil; client.disconnect() }
    }

    func reconnectSavedPhones() {
        for phone in savedPhones.values { reconnect(phone) }
    }

    func disconnect(phoneID: String) {
        phonePermissions.removeValue(forKey: phoneID)
        metadataSentPhones.remove(phoneID)
        advancedMirroring.stop(phoneID: phoneID)
        usb.stopTunnel(phoneID: phoneID)
        authenticationAttempts.removeValue(forKey: phoneID)
        sessionCredentials.removeValue(forKey: phoneID)
        screen.ended(phoneID: phoneID)
        camera.ended(phoneID: phoneID)
        files.disconnected(phoneID: phoneID)
        bulk.disconnected(phoneID: phoneID)
        storage.disconnected(phoneID: phoneID)
        reconnectEnabled.remove(phoneID)
        reconnectTasks.removeValue(forKey: phoneID)?.cancel()
        if let client = clients.removeValue(forKey: phoneID) {
            client.onState = nil
            client.disconnect()
        }
        sessions.update(.disconnected, for: phoneID)
    }

    func ring(phoneID: String, stop: Bool = false) {
        guard sessions.state(for: phoneID) == .connected else { return }
        ringTasks.removeValue(forKey: phoneID)?.cancel()
        if stop { ringingPhones.remove(phoneID) }
        else {
            ringingPhones.insert(phoneID)
            ringTasks[phoneID] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                self?.ringingPhones.remove(phoneID)
            }
        }
        let expiry = Date().addingTimeInterval(30).timeIntervalSince1970 * 1000
        send(phoneID: phoneID, packet: ControlPacket(type: stop ? "stopRing" : "ring", payload: .object(["expiresAt": .number(expiry)])))
    }



    func forget(phoneID: String) {
        guard sessions.state(for: phoneID) == .connected else {
            message = "Connect this phone before revoking trust on both devices."
            return
        }
        pendingUnpair.insert(phoneID)
        send(phoneID: phoneID, packet: ControlPacket(type: "unpair"))
    }

    func sendClipboard(phoneID: String) {
        guard let text = NSPasteboard.general.string(forType: .string), text.count <= 32_000 else {
            message = "Copy text of up to 32,000 characters first."
            return
        }
        sendText(text, phoneID: phoneID)
    }

    func sendText(_ text: String, phoneID: String) {
        clipboardHistory.record(text: text, source: "Mac", phoneID: phoneID)
        guard text.count <= 32_000 else { message = "Text exceeds 32,000 characters."; return }
        send(phoneID: phoneID, packet: ControlPacket(type: "clipboard", payload: .object(["text": .string(text)])))
    }

    func notificationAction(_ notification: RelayedNotification, index: Int? = nil, reply: String = "", dismiss: Bool = false) {
        send(phoneID: notification.phoneID, packet: ControlPacket(type: "notificationAction", payload: .object([
            "notificationKey": .string(notification.id), "packageName": .string(notification.application.packageName),
            "profileIdentifier": .string(notification.application.profileIdentifier), "index": .number(Double(index ?? 0)),
            "replyText": .string(String(reply.prefix(4000))), "dismiss": .bool(dismiss)
        ])))
        if dismiss { notifications.removeAll { $0.phoneID == notification.phoneID && $0.id == notification.id } }
    }

    func requestNotificationPermission() {
        MacNotificationDelivery.shared.reviewAccess()
    }

    private var macID: String {
        if let existing = UserDefaults.standard.string(forKey: "macIdentity") { return existing }
        let identity = UUID().uuidString
        UserDefaults.standard.set(identity, forKey: "macIdentity")
        return identity
    }

    private func makeClient(phoneID: String, profile: ConnectionProfile) -> PhoneControlClient {
        screen.ended(phoneID: phoneID)
        camera.ended(phoneID: phoneID)
        files.disconnected(phoneID: phoneID)
        bulk.disconnected(phoneID: phoneID)
        storage.disconnected(phoneID: phoneID)
        reconnectTasks.removeValue(forKey: phoneID)?.cancel()
        if let oldClient = clients.removeValue(forKey: phoneID) {
            oldClient.onState = nil
            oldClient.disconnect()
        }
        let client = PhoneControlClient()
        client.onPacket = { [weak self] packet in self?.receive(packet, phoneID: phoneID, profile: profile) }
        client.onState = { [weak self] state, error in
            guard let self else { return }
            self.sessions.update(state, for: phoneID)
            if state == .disconnected { self.files.disconnected(phoneID: phoneID); self.bulk.disconnected(phoneID: phoneID); self.storage.disconnected(phoneID: phoneID) }
            if let error { self.message = "Could not connect to \(profile.host): \(error)" }
            if state == .disconnected {
                self.phonePermissions.removeValue(forKey: phoneID)
                self.metadataSentPhones.remove(phoneID)
                self.advancedMirroring.stop(phoneID: phoneID)
                if self.usbProfiles[phoneID] != nil { self.usb.connectionLost(phoneID: phoneID, reason: error) }
                else { self.scheduleReconnect(phoneID: phoneID) }
            }
        }
        clients[phoneID] = client
        return client
    }

    private func receive(_ packet: ControlPacket, phoneID: String, profile: ConnectionProfile) {
        activeProfiles[phoneID] = profile
        switch packet.type {
        case "bulkOffer", "bulkAccepted", "bulkCancel":
            guard sessions.state(for: phoneID) == .connected else { return }
            bulk.receive(packet, phoneID: phoneID)
        case "browseResult", "browseThumbnail", "browseError":
            guard sessions.state(for: phoneID) == .connected else { return }
            storage.receive(packet, phoneID: phoneID)
        case "unpaired":
            guard pendingUnpair.remove(phoneID) != nil else { return }
            disconnect(phoneID: phoneID)
            Task {
                do {
                    try await credentials.remove(for: phoneID)
                    onForgotten?(phoneID)
                    message = "Phone trust revoked on both devices."
                } catch { message = error.localizedDescription }
            }
        case "cameraEnded": camera.ended(phoneID: phoneID)
        case "cameraError":
            let description = packet.payload["message"].string ?? "Camera could not start."
            camera.reportError(phoneID: phoneID, description: description)
            message = description
        case "notificationRemoved":
            guard let key = packet.payload["notificationKey"].string else { return }
            notifications.removeAll { $0.phoneID == phoneID && $0.id == key }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [phoneID + key])
        case "screenEnded": screen.ended(phoneID: phoneID)
        case "mediaGrant":
            guard sessions.state(for: phoneID) == .connected,
                  let token = packet.payload["token"].string else { return }
            if let credential = sessionCredentials[phoneID] {
                let purpose = packet.payload["purpose"].string
                if purpose == "screen" {
                    screen.acceptGrant(phoneID: phoneID, profile: profile, macID: macID, credential: credential, token: token)
                } else if purpose == "camera" {
                    camera.acceptGrant(phoneID: phoneID, profile: profile, macID: macID, credential: credential, token: token)
                }
            }
        case "fileOffer", "fileAccept", "fileChunk", "fileFinish", "fileCancel", "fileComplete":
            guard sessions.state(for: phoneID) == .connected else { return }
            files.receive(packet, phoneID: phoneID)
        case "pairingPending": message = "Waiting for approval on the phone."
        case "paired": finishPairing(packet, phoneID: phoneID, profile: profile)
        case "authenticated":
            guard packet.payload["phoneID"].string == phoneID else { disconnect(phoneID: phoneID); return }
            markAuthenticated(phoneID: phoneID)
            if usbProfiles[phoneID] == nil && savedPhones[phoneID]?.connection != profile {
                do {
                    try onEndpointChanged?(phoneID, profile)
                } catch {
                    message = "Connected, but could not save the updated phone address."
                }
            }
        case "status": updateStatus(packet.payload, phoneID: phoneID)
        case "applications": updateApplications(packet.payload, phoneID: phoneID)
        case "notification": receiveNotification(packet.payload, phoneID: phoneID)
        case "clipboard":
            guard sessions.state(for: phoneID) == .connected, activePhoneID == phoneID,
                  let text = packet.payload["text"].string, text.count <= 32_000 else { return }
            clipboardHistory.record(text: text, source: savedPhones[phoneID]?.displayName ?? "Phone", phoneID: phoneID)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            lastPasteboardChange = NSPasteboard.general.changeCount
            message = "Text copied from \(savedPhones[phoneID]?.displayName ?? "phone")."
        case "error": message = packet.payload["message"].string ?? "Phone operation failed."
        default: break
        }
    }

    private func finishPairing(_ packet: ControlPacket, phoneID: String, profile: ConnectionProfile) {
        guard let invitation = pendingInvitations.removeValue(forKey: phoneID),
              packet.payload["phoneID"].string == phoneID,
              let credential = packet.payload["credential"].string,
              Data(base64Encoded: credential)?.count == 32,
              let requestingClient = clients[phoneID] else {
            message = ConnectionProtocolError.invalidMessage.localizedDescription
            disconnect(phoneID: phoneID)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.credentials.save(credential, for: phoneID)
                guard self.clients[phoneID] === requestingClient else { return }
                self.sessionCredentials[phoneID] = credential
                try self.onPaired?(phoneID, invitation.name, profile)
                self.reconnectEnabled.insert(phoneID)
                self.markAuthenticated(phoneID: phoneID)
                self.message = "Paired with \(invitation.name)."
                requestingClient.send(ControlPacket(type: "statusRequest"))
                requestingClient.send(ControlPacket(type: "applicationsRequest"))
            } catch {
                self.message = error.localizedDescription
                self.disconnect(phoneID: phoneID)
            }
        }
    }

    private func markAuthenticated(phoneID: String) {
        metadataSentPhones.remove(phoneID)
        reconnectTasks.removeValue(forKey: phoneID)?.cancel()
        if let profile = activeProfiles[phoneID] { usb.markVerified(phoneID: phoneID, profile: profile) }
        clients[phoneID]?.authenticated()
        reconnectAttempts[phoneID] = 0
        message = "Connected to \(savedPhones[phoneID]?.displayName ?? "phone")."
        sendNotificationPolicy(phoneID: phoneID)
    }

    private func updateStatus(_ payload: JSONValue, phoneID: String) {
        guard sessions.state(for: phoneID) == .connected, payload["phoneID"].string == phoneID else { return }
        if payload["macDetailsVersion"].number == 1 { sendMacDetailsIfNeeded(phoneID: phoneID) }
        var permissions: [String: Bool] = [:]
        for (key, title) in [("camera", "Camera"), ("notifications", "Notifications"),
                             ("notificationSharing", "Notification sharing"), ("phoneControl", "Phone control"),
                             ("storage", "Shared storage"), ("battery", "Unrestricted battery")] {
            if let allowed = payload["permissions"][key].boolean { permissions[title] = allowed }
        }
        if !permissions.isEmpty { phonePermissions[phoneID] = permissions }
        if payload["bulkVersion"].number == 1 { bulk.supportedPhones.insert(phoneID) }
        if payload["storageBrowserVersion"].number == 1 { storage.supportedPhones.insert(phoneID) }
        let battery = payload["batteryPercent"].number ?? -1
        guard battery >= -1 && battery <= 100 else { return }
        statuses[phoneID] = ConnectedPhoneStatus(model: payload["model"].string ?? "Android",
            androidVersion: payload["androidVersion"].string ?? "Unknown", batteryPercent: Int(battery),
            isCharging: payload["isCharging"].boolean ?? false, receivedAt: Date(),
            deviceDetails: DeviceDetails(payload: payload["deviceDetails"]))
    }

    private func sendMacDetailsIfNeeded(phoneID: String) {
        let lastSent = metadataLastSent[phoneID] ?? .distantPast
        guard !metadataSentPhones.contains(phoneID) || Date().timeIntervalSince(lastSent) >= 60,
              let client = clients[phoneID] else { return }
        metadataSentPhones.insert(phoneID)
        metadataLastSent[phoneID] = Date()
        Task { [weak self, weak client] in
            // Volume metadata can block; keep it off the UI and tie the result to this authenticated client.
            let details = await Task.detached(priority: .utility) { MacDetailsSnapshot.payload() }.value
            guard let self, let client, self.clients[phoneID] === client,
                  self.sessions.state(for: phoneID) == .connected else { return }
            self.send(phoneID: phoneID, packet: ControlPacket(type: "macDetails", payload: details))
        }
    }

    private func applicationIcon(_ value: JSONValue) -> NSImage? {
        guard let encodedImage = value.string, encodedImage.count <= 8192,
              let imageData = Data(base64Encoded: encodedImage),
              let bitmap = NSBitmapImageRep(data: imageData),
              bitmap.pixelsWide <= 96, bitmap.pixelsHigh <= 96 else { return nil }
        let image = NSImage(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        image.addRepresentation(bitmap)
        return image
    }

    private func updateApplications(_ payload: JSONValue, phoneID: String) {
        guard sessions.state(for: phoneID) == .connected else { return }
        applications[phoneID] = payload["applications"].array.prefix(500).compactMap { entry in
            guard let package = entry["packageName"].string, let profile = entry["profileIdentifier"].string,
                  let name = entry["name"].string else { return nil }
            return PhoneApplication(identity: AndroidApplicationIdentity(packageName: package, profileIdentifier: profile), name: name, icon: applicationIcon(entry["icon"]))
        }
    }

    private func receiveNotification(_ payload: JSONValue, phoneID: String) {
        guard sessions.state(for: phoneID) == .connected, let phone = savedPhones[phoneID],
              let package = payload["packageName"].string, let profile = payload["profileIdentifier"].string,
              let key = payload["notificationKey"].string else { return }
        let application = AndroidApplicationIdentity(packageName: package, profileIdentifier: profile)
        guard phone.preferences.notifications.permits(application) else { return }
        let notification = RelayedNotification(id: key, phoneID: phoneID, application: application,
            title: String((payload["title"].string ?? "Notification").prefix(500)),
            text: String((payload["text"].string ?? "").prefix(4000)), actions: Array(payload["actions"].array.prefix(16)), icon: applicationIcon(payload["icon"]))
        notifications.removeAll { $0.phoneID == phoneID && $0.id == key }
        notifications.insert(notification, at: 0)
        notifications = Array(notifications.prefix(100))
        MacNotificationDelivery.shared.deliver(identifier: phoneID + key,
                                               title: phone.displayName + " · " + notification.title,
                                               body: notification.text)
    }

    private func sendNotificationPolicy(phoneID: String) {
        guard sessions.state(for: phoneID) == .connected, let policy = savedPhones[phoneID]?.preferences.notifications else { return }
        do {
            let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(policy))
            send(phoneID: phoneID, packet: ControlPacket(type: "notificationPolicy", payload: payload))
        } catch { message = error.localizedDescription }
    }

    private func send(phoneID: String, packet: ControlPacket) {
        do {
            _ = try sessions.requireConnectedPhone(id: phoneID)
            clients[phoneID]?.send(packet)
        } catch { message = "Select a connected phone before using this action." }
    }

    private func scheduleReconnect(phoneID: String) {
        guard reconnectEnabled.contains(phoneID), reconnectTasks[phoneID] == nil else { return }
        let attempt = min((reconnectAttempts[phoneID] ?? 0) + 1, 5)
        reconnectAttempts[phoneID] = attempt
        let delay = min(pow(2.0, Double(attempt)), 30) + Double.random(in: 0...1)
        reconnectTasks[phoneID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let phone = self.savedPhones[phoneID] else { return }
            self.reconnectTasks.removeValue(forKey: phoneID)
            self.reconnect(phone)
        }
    }

    private func pollClipboard() {
        let change = NSPasteboard.general.changeCount
        guard change != lastPasteboardChange else { return }
        lastPasteboardChange = change
        let pasteboardTypes = NSPasteboard.general.types ?? []
        guard let phoneID = activePhoneID, savedPhones[phoneID]?.preferences.automaticallyShareMacClipboard == true,
              sessions.state(for: phoneID) == .connected,
              !pasteboardTypes.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) else { return }
        sendClipboard(phoneID: phoneID)
    }
}
