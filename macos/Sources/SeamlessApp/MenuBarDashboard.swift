// Owns the status item, dashboard and incoming-share popovers. Staged files remain local until Send; transfer completion updates the dashboard without opening a window.

import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class MenuBarDashboard {
    static let shared = MenuBarDashboard()
    private let shelf = MenuBarFileShelf()
    private var subscriptions: Set<AnyCancellable> = []
    private var incomingPopover: NSPopover?
    private var item: NSStatusItem?
    private var popover: NSPopover?
    private var dropView: MenuBarDropView?

    func configure(preferencesStore: PreferencesStore, openMainWindow: @escaping () -> Void) {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: 32)
        let symbol = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: "Seamless")
        symbol?.isTemplate = true
        item.button?.image = symbol
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarDashboardView(preferencesStore: preferencesStore,
            connections: preferencesStore.connections, bulk: preferencesStore.connections.bulk, shelf: shelf, openMainWindow: { [weak popover] in
                popover?.performClose(nil)
                openMainWindow()
            }))
        if let hosting = popover.contentViewController as? NSHostingController<MenuBarDashboardView> {
            hosting.sizingOptions = [.preferredContentSize]
        }
        let view = MenuBarDropView(frame: NSRect(x: 0, y: 0, width: 32, height: 24))
        view.open = { [weak popover, weak view] in
            guard let popover, let view else { return }
            if popover.isShown { popover.performClose(nil) }
            else { popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY) }
        }
        view.receiveFiles = { [weak self] urls in
            self?.shelf.add(urls)
            return true
        }
        view.dragEntered = { [weak popover, weak view] in
            guard let popover, let view else { return }
            if !popover.isShown {
                popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
        }
        item.button?.addSubview(view)
        view.autoresizingMask = [.width, .height]
        view.frame = item.button?.bounds ?? view.frame
        self.item = item
        self.popover = popover
        dropView = view
        let incoming = NSPopover()
        incoming.behavior = .transient
        incoming.contentViewController = NSHostingController(rootView: IncomingSharePopup(
            bulk: preferencesStore.connections.bulk, texts: preferencesStore.connections.clipboardHistory, dismiss: { [weak incoming] in incoming?.performClose(nil) }))
        if let hosting = incoming.contentViewController as? NSHostingController<IncomingSharePopup> {
            hosting.sizingOptions = [.preferredContentSize]
        }
        incomingPopover = incoming
        view.open = { [weak popover, weak incoming, weak view] in
            guard let popover, let incoming, let view else { return }
            if incoming.isShown {
                incoming.performClose(nil)
            } else if !preferencesStore.connections.bulk.offers.isEmpty {
                popover.performClose(nil)
                incoming.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            } else if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
        }
        let showIncoming = { [weak incoming, weak view] in
            guard let incoming, let view else { return }
            incoming.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        var previousOfferIDs = Set<String>()
        var previousTextIDs = Set<UUID>()
        preferencesStore.connections.bulk.$offers.sink { offers in
            let currentIDs = Set(offers.map(\.id))
            let hasNewOffers = !currentIDs.subtracting(previousOfferIDs).isEmpty
            previousOfferIDs = currentIDs
            if hasNewOffers { Task { @MainActor in showIncoming() } }
        }.store(in: &subscriptions)
        preferencesStore.connections.clipboardHistory.$items.sink { items in
            let currentIDs = Set(items.map(\.id))
            let hasNewText = !currentIDs.subtracting(previousTextIDs).isEmpty
            previousTextIDs = currentIDs
            if hasNewText { Task { @MainActor in showIncoming() } }
        }.store(in: &subscriptions)

    }
}

private final class MenuBarDropView: NSView {
    var dragEntered: (() -> Void)?
    var open: (() -> Void)?
    var receiveFiles: (([URL]) -> Bool)?
    private var highlighted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Seamless dashboard. Drop files to send to the selected phone.")
        toolTip = "Seamless · drop files to send to your phone"
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        if highlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 5, yRadius: 5).fill()
        }

    }
    override func mouseDown(with event: NSEvent) { open?() }
    override func accessibilityPerformPress() -> Bool { open?(); return true }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        highlighted = true
        needsDisplay = true
        dragEntered?()
        return .copy
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { highlighted = false; needsDisplay = true }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        highlighted = false
        needsDisplay = true
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return !urls.isEmpty && receiveFiles?(urls) == true
    }
}

private struct MenuBarDashboardView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var connections: PhoneConnections
    @ObservedObject var bulk: BulkTransfers
    @ObservedObject var shelf: MenuBarFileShelf
    let openMainWindow: () -> Void
    @StateObject private var editor = ClipboardEditor()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.phoneThemeColor) private var phoneThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Seamless").font(.title3.weight(.semibold))
                Spacer()
                Button("Open app", action: openMainWindow)
            }
            Menu {
                ForEach(preferencesStore.preferences.rememberedPhones) { phone in
                    Button(phone.displayName) { preferencesStore.selectPhone(id: phone.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "iphone")
                    Text(preferencesStore.preferences.selectedPhone?.displayName ?? "Choose phone").lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption)
                }.padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.quaternary, in: Capsule())
            }.menuStyle(.borderlessButton)

            if let phoneID = preferencesStore.preferences.selectedPhoneID {
                HStack {
                    ConnectionBadge(isConnected: connections.sessions.state(for: phoneID) == .connected)
                    Spacer()
                    Button {
                        connections.ring(phoneID: phoneID, stop: connections.ringingPhones.contains(phoneID))
                    } label: {
                        Label(connections.ringingPhones.contains(phoneID) ? "Stop ringing" : "Find phone",
                              systemImage: connections.ringingPhones.contains(phoneID) ? "bell.slash" : "bell")
                    }.disabled(connections.sessions.state(for: phoneID) != .connected)
                    if let status = connections.statuses[phoneID] { Label("\(status.batteryPercent)%", systemImage: "battery.100percent") }
                }
                MenuBarFileShelfView(shelf: shelf, bulk: bulk, phoneID: phoneID)
                ForEach(bulk.activities.filter { $0.phoneID == phoneID }.prefix(3)) { activity in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activity.name).font(.caption).lineLimit(1)
                        ProgressView(value: Double(activity.completed), total: Double(max(1, activity.size)))
                    }
                }
                HStack {
                    TextField("Send text to phone", text: $editor.text).textFieldStyle(WorkspaceTextFieldStyle())
                    Button("Send") { connections.sendText(editor.text, phoneID: phoneID); editor.text = "" }
                        .disabled(editor.text.isEmpty || editor.text.utf16.count > 32_000 || connections.sessions.state(for: phoneID) != .connected)
                }
                if let result = bulk.latestTransferResult {
                    Label(result, systemImage: "checkmark.circle")
                        .font(.caption).lineLimit(3)
                }
                LatestReceivedText(history: connections.clipboardHistory, phoneID: phoneID)
                if let status = connections.clipboardStatus[phoneID] {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                if !bulk.activities.isEmpty {
                    Text(bulk.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Divider()
            HStack {
                Spacer()
                QuitApplicationButton(compact: true).font(.caption)
            }
        }
        .padding(16).frame(width: 440)
        .background(TranslucentSurface(material: .popover, tint: InterfacePalette(scheme: colorScheme, colorName: phoneThemeColor).canvas))
        .tint(InterfacePalette(scheme: colorScheme, colorName: phoneThemeColor).accent)
        .buttonStyle(WorkspaceButtonStyle(compact: true))

        .environment(\.phoneThemeColor, preferencesStore.preferences.selectedPhone?.preferences.previewColor ?? "sage")
        .preferredColorScheme(appearance)
    }

    private var appearance: ColorScheme? {
        switch preferencesStore.preferences.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}


private struct IncomingSharePopup: View {
    @ObservedObject var bulk: BulkTransfers
    @ObservedObject var texts: ClipboardHistory
    let dismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Incoming shares", systemImage: "arrow.down.circle").font(.headline)
                    Spacer()
                    Button(action: dismiss) { Image(systemName: "xmark") }.help("Close")
                }
                ForEach(bulk.offers) { offer in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(offer.name, systemImage: "doc.fill").font(.callout.weight(.medium)).lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount: offer.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                        Button("Downloads") { bulk.accept(offer); if bulk.offers.isEmpty { dismiss() } }
                        Button("Choose folder…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let directory = panel.url {
                                bulk.accept(offer, directory: directory)
                                if bulk.offers.isEmpty { dismiss() }
                            }
                        }
                        Button("Decline") {
                            bulk.reject(id: offer.id, phoneID: offer.phoneID)
                            if bulk.offers.isEmpty { dismiss() }
                        }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8).padding(.bottom, 6)
                    }
                    Divider()
                }
                ForEach(texts.items.prefix(5)) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(item.source, systemImage: "text.bubble")
                        Text(item.text).lineLimit(5)
                        HStack {
                            Button("Copy") { texts.copy(item) }
                            Button("Delete") { texts.delete(item) }
                        }
                    }
                }
                if bulk.offers.isEmpty && texts.items.isEmpty {
                    Text("No incoming shares")
                }
            }.padding(20)
        }.frame(width: 440, height: min(420, CGFloat(72 + bulk.offers.count * 140 + min(5, texts.items.count) * 150)))
            .buttonStyle(WorkspaceButtonStyle(compact: true))
    }
}

@MainActor
private final class MenuBarFileShelf: ObservableObject {
    @Published private(set) var files: [URL] = []

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !files.contains(url) {
            files.append(url)
        }
    }

    func clear() { files = [] }
    func remove(_ url: URL) { files.removeAll { $0 == url } }

    func send(to phoneID: String, using bulk: BulkTransfers) {
        guard bulk.supportedPhones.contains(phoneID) else { return }
        let availableSlots = max(0, 8 - bulk.activities.count)
        guard availableSlots > 0 else { return }
        let pending = Array(files.prefix(availableSlots))
        files.removeFirst(pending.count)
        for url in pending { bulk.offer(url: url, phoneID: phoneID) }
    }
}

private struct MenuBarFileShelfView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var shelf: MenuBarFileShelf
    @ObservedObject var bulk: BulkTransfers
    let phoneID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "tray")
                Spacer()
                Button {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK { shelf.add(panel.urls) }
                } label: { Image(systemName: "plus").frame(width: 18, height: 18) }
                .help("Add files")
                Button("Clear") { shelf.clear() }
            }
            if shelf.files.isEmpty {
                Text("Drop files from Finder here").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 62)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(shelf.files, id: \.self) { url in
                        VStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 32, height: 32)
                            Text(url.lastPathComponent).font(.caption).lineLimit(2)
                            Button("Remove") { shelf.remove(url) }.font(.caption)
                        }.frame(width: 92).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }.frame(height: shelf.files.isEmpty ? 0 : 116)
            if !shelf.files.isEmpty {
                Button("Send files to phone") { shelf.send(to: phoneID, using: bulk) }
                    .disabled(!bulk.supportedPhones.contains(phoneID) || bulk.activities.count >= 8)
            }
        }.padding(12).background(InterfacePalette(scheme: colorScheme).surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(InterfacePalette(scheme: colorScheme).border))
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else { return }
                    Task { @MainActor in shelf.add([url]) }
                }
            }
            return !providers.isEmpty
        }
    }
}

private struct LatestReceivedText: View {
    @ObservedObject var history: ClipboardHistory
    let phoneID: String

    var body: some View {
        if let item = history.items.first(where: { $0.phoneID == phoneID }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From phone").font(.caption).foregroundStyle(.secondary)
                    Text(item.text).font(.callout).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { history.copy(item) } label: {
                    Image(systemName: "doc.on.doc")
                }.help("Copy received text").accessibilityLabel("Copy received text")
                Button { history.clear(phoneID: phoneID) } label: {
                    Image(systemName: "xmark")
                }.help("Clear received text").accessibilityLabel("Clear received text")
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
