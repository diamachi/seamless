import AppKit
import SwiftUI

@MainActor
final class MenuBarDashboard {
    static let shared = MenuBarDashboard()
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
        popover.contentSize = NSSize(width: 360, height: 460)
        popover.contentViewController = NSHostingController(rootView: MenuBarDashboardView(preferencesStore: preferencesStore,
            connections: preferencesStore.connections, bulk: preferencesStore.connections.bulk, openMainWindow: { [weak popover] in
                popover?.performClose(nil)
                openMainWindow()
            }))
        let view = MenuBarDropView(frame: NSRect(x: 0, y: 0, width: 32, height: 24))
        view.open = { [weak popover, weak view] in
            guard let popover, let view else { return }
            if popover.isShown { popover.performClose(nil) }
            else { popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY) }
        }
        view.receiveFiles = { urls in
            guard let phoneID = preferencesStore.preferences.selectedPhoneID,
                  preferencesStore.connections.bulk.supportedPhones.contains(phoneID) else { return false }
            for url in urls.prefix(8) { preferencesStore.connections.bulk.offer(url: url, phoneID: phoneID) }
            return true
        }
        item.button?.addSubview(view)
        view.autoresizingMask = [.width, .height]
        view.frame = item.button?.bounds ?? view.frame
        self.item = item
        self.popover = popover
        dropView = view
    }
}

private final class MenuBarDropView: NSView {
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
        highlighted = true
        needsDisplay = true
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
    let openMainWindow: () -> Void
    @StateObject private var editor = ClipboardEditor()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Seamless").font(.title3.weight(.semibold))
                Spacer()
                Button("Open app", action: openMainWindow)
            }
            PhoneSwitcherView(preferencesStore: preferencesStore)
            if let phoneID = preferencesStore.preferences.selectedPhoneID {
                HStack {
                    ConnectionBadge(isConnected: connections.sessions.state(for: phoneID) == .connected)
                    Spacer()
                    if let status = connections.statuses[phoneID] { Label("\(status.batteryPercent)%", systemImage: "battery.100percent") }
                }
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 26, weight: .light)).foregroundStyle(.tint)
                    Text("Drop files here or on the menu-bar icon").font(.callout).multilineTextAlignment(.center)
                    Button("Choose files…") { bulk.choose(phoneID: phoneID) }
                        .disabled(!bulk.supportedPhones.contains(phoneID))
                }.frame(maxWidth: .infinity).padding(20)
                    .background(InterfacePalette(scheme: colorScheme).raisedSurface, in: RoundedRectangle(cornerRadius: 16))
                ForEach(bulk.activities.filter { $0.phoneID == phoneID }.prefix(3)) { activity in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(activity.name).font(.caption).lineLimit(1)
                        ProgressView(value: Double(activity.completed), total: Double(max(1, activity.size)))
                    }
                }
                HStack {
                    Button("Find phone") { connections.ring(phoneID: phoneID) }
                    Button("Send clipboard") { connections.sendClipboard(phoneID: phoneID) }
                }.disabled(connections.sessions.state(for: phoneID) != .connected)
                HStack {
                    TextField("Send text to phone", text: $editor.text).textFieldStyle(WorkspaceTextFieldStyle())
                    Button("Send") { connections.sendText(editor.text, phoneID: phoneID); editor.text = "" }
                        .disabled(editor.text.isEmpty || editor.text.count > 32_000 || connections.sessions.state(for: phoneID) != .connected)
                }
                Text(bulk.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Divider()
            QuitApplicationButton()
        }
        .padding(20).frame(width: 360)
        .background(TranslucentSurface(material: .popover, tint: InterfacePalette(scheme: colorScheme).canvas))
        .tint(InterfacePalette(scheme: colorScheme).accent)
        .buttonStyle(WorkspaceButtonStyle())
        .modifier(FileDropTarget(phoneID: preferencesStore.preferences.selectedPhoneID, bulk: bulk))
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
