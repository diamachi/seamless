import AVFoundation
import AppKit
import SwiftUI
import SeamlessCore

private final class ScreenLayerView: NSView {
    let videoLayer: AVSampleBufferDisplayLayer
    let controller: PhoneVideoStreamController
    private var pointerStart: CGPoint?
    private var lastPointerPoint: CGPoint?
    private var lastPointerSentAt = Date.distantPast
    private var lastScrollAt = Date.distantPast
    init(controller: PhoneVideoStreamController) {
        self.controller = controller
        self.videoLayer = controller.displayLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(videoLayer)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        videoLayer.frame = bounds
    }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        pointerStart = normalizedPoint(event)
        lastPointerPoint = pointerStart
        if controller.supportsContinuousTouch, let point = pointerStart {
            sendPointer("touchDown", point: point)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard pointerStart != nil, let point = normalizedPoint(event) else { return }
        lastPointerPoint = point
        if controller.supportsContinuousTouch,
           Date().timeIntervalSince(lastPointerSentAt) >= 1.0 / 120.0 {
            sendPointer("touchMove", point: point)
        }
    }
    private func sendPointer(_ kind: String, point: CGPoint) {
        lastPointerSentAt = Date()
        controller.input(kind: kind, coordinates: ["x": point.x, "y": point.y])
    }
    override func mouseUp(with event: NSEvent) {
        if controller.supportsContinuousTouch {
            if pointerStart != nil, let point = normalizedPoint(event) ?? lastPointerPoint {
                sendPointer("touchUp", point: point)
            }
            pointerStart = nil
            lastPointerPoint = nil
            return
        }
        guard let start = pointerStart, let end = normalizedPoint(event) else { pointerStart = nil; return }
        pointerStart = nil
        if hypot(start.x - end.x, start.y - end.y) < 0.01 {
            controller.input(kind: "tap", coordinates: ["x": end.x, "y": end.y])
        } else {
            controller.input(kind: "swipe", coordinates: ["x": start.x, "y": start.y, "endX": end.x, "endY": end.y])
        }
    }
    override func scrollWheel(with event: NSEvent) {
        guard Date().timeIntervalSince(lastScrollAt) >= 0.3 else { return }
        lastScrollAt = Date()
        let endY = event.scrollingDeltaY < 0 ? 0.3 : 0.7
        controller.input(kind: "swipe", coordinates: ["x": 0.5, "y": 0.5, "endX": 0.5, "endY": endY])
    }
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 3 { controller.input(kind: "back") }
        else if event.buttonNumber == 4 { controller.input(kind: "forward") }
        else { super.otherMouseUp(with: event) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller.input(kind: "back") }
        else { super.keyDown(with: event) }
    }
    private func normalizedPoint(_ event: NSEvent) -> CGPoint? {
        let point = convert(event.locationInWindow, from: nil)
        let content = AVMakeRect(aspectRatio: controller.videoSize, insideRect: bounds)
        guard content.contains(point), content.width > 0, content.height > 0 else { return nil }
        return CGPoint(x: (point.x - content.minX) / content.width, y: (content.maxY - point.y) / content.height)
    }
}

struct PhoneVideoSurface: NSViewRepresentable {
    let controller: PhoneVideoStreamController
    func makeNSView(context: Context) -> NSView { ScreenLayerView(controller: controller) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class PhoneScreenState: ObservableObject {
    @Published var search = ""
    @Published var selectedApplication: String?
    @Published var previewScale = 1.0
}

struct PhoneScreenView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var controller: PhoneVideoStreamController
    @StateObject private var state = PhoneScreenState()

    private var applications: [PhoneApplication] {
        guard let phoneID = preferencesStore.preferences.selectedPhoneID else { return [] }
        return (preferencesStore.connections.applications[phoneID] ?? []).filter {
            state.search.isEmpty || $0.name.localizedCaseInsensitiveContains(state.search)
        }
    }
    private var selectedApplication: PhoneApplication? {
        applications.first { $0.id == state.selectedApplication }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 20) {
                WorkspaceHeading(title: "Phone screen", subtitle: "Your apps, with room for everything else.")
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    WorkspaceSegments(options: [(60, "60 fps"), (120, "120 fps")], selection: preferencesStore.featurePreferences.screenFramesPerSecond)
                    Button {
                        if let phone = preferencesStore.preferences.selectedPhone {
                            if let application = selectedApplication, let serial = preferencesStore.connections.usb.verifiedSerial(phoneID: phone.id) {
                                preferencesStore.connections.advancedMirroring.open(application: application, phoneID: phone.id,
                                    serial: serial, framesPerSecond: phone.preferences.screenFramesPerSecond)
                            } else {
                                controller.request(phoneID: phone.id, framesPerSecond: phone.preferences.screenFramesPerSecond, application: selectedApplication)
                            }
                        }
                    } label: { Label(shareButtonTitle, systemImage: "play.rectangle.fill") }
                        .buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(!isConnected)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Apps").font(.headline)
                    TextField("Search phone apps", text: $state.search).textFieldStyle(WorkspaceTextFieldStyle())
                    Button("Entire phone screen") { state.selectedApplication = nil }
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(applications) { application in
                                Button { state.selectedApplication = application.id } label: {
                                    HStack(spacing: 12) {
                                        if let icon = application.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                                        else { Image(systemName: "app").frame(width: 28, height: 28) }
                                        Text(application.name).lineLimit(2)
                                        Spacer()
                                        if state.selectedApplication == application.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                                    }.padding(12)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    AdvancedMirroringControls(controller: preferencesStore.connections.advancedMirroring)
                    Text(sharingGuidance)
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(minWidth: 220, idealWidth: 280, maxWidth: 380)
                Spacer(minLength: 0)
                VStack(spacing: 14) {
                    if controller.isDetached {
                        ContentUnavailableView("Sharing in another window", systemImage: "macwindow.on.rectangle")
                    } else {
                        HStack {
                            Text("Preview size").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $state.previewScale, in: 0.5...1).frame(maxWidth: 180)
                                .accessibilityLabel("Stream preview scale")
                            Button("Fit") { state.previewScale = 1 }
                        }
                        PhoneStreamMockup(controller: controller, previewScale: state.previewScale)
                    }
                    HStack {
                        Button("Stop sharing") { controller.stop() }
                        Button { ScreenPopout.shared.show(controller: controller) } label: { Label("Pop out", systemImage: "arrow.up.left.and.arrow.down.right") }
                    }
                    Text(controller.message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer(minLength: 0)
            }
        }.buttonStyle(WorkspaceButtonStyle())
    }
    private var sharingGuidance: String {
        if let phoneID = preferencesStore.preferences.selectedPhoneID,
           preferencesStore.connections.usb.verifiedSerial(phoneID: phoneID) != nil {
            return "Select an app and choose Share app over ADB to open it here. USB debugging must stay enabled during this session."
        }
        return "Without ADB, Android asks you to choose the app on your phone for each new sharing session. Open a missing app first so Android can offer it among recent apps."
    }

    private var shareButtonTitle: String {
        guard selectedApplication != nil else { return "Share phone screen" }
        if let phoneID = preferencesStore.preferences.selectedPhoneID,
           preferencesStore.connections.usb.verifiedSerial(phoneID: phoneID) != nil {
            return "Share app over ADB"
        }
        return "Choose app on phone…"
    }

    private var isConnected: Bool {
        guard let phoneID = preferencesStore.preferences.selectedPhoneID else { return false }
        return preferencesStore.sessions.state(for: phoneID) == .connected
    }
}

struct PhoneStreamMockup: View {
    @ObservedObject var controller: PhoneVideoStreamController
    var previewScale = 1.0

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(1, geometry.size.width - 12)
            let availableHeight = max(1, geometry.size.height - 64)
            let fittedWidth = min(availableWidth, availableHeight * aspectRatio)
            let width = fittedWidth * previewScale
            VStack(spacing: 12) {
                Group {
                    if controller.isStreaming {
                        PhoneVideoSurface(controller: controller)
                    } else {
                        Color.black.overlay {
                            Image(systemName: "iphone").font(.system(size: 48, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
                .frame(width: width, height: width / aspectRatio)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .padding(5)
                .background(Color(rgb: 0x303336), in: RoundedRectangle(cornerRadius: 27))
                navigationControls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var navigationControls: some View {
        HStack(spacing: 16) {
            navigationButton("Back", symbol: "chevron.left", command: "back")
            navigationButton("Home", symbol: "circle", command: "home")
            navigationButton("Recent apps", symbol: "square", command: "recents")
        }
        .foregroundStyle(.primary)
    }

    private func navigationButton(_ title: String, symbol: String, command: String) -> some View {
        Button { controller.input(kind: command) } label: {
            Image(systemName: symbol).frame(width: 36, height: 36).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).help(title)
    }

    private var aspectRatio: CGFloat {
        if controller.videoSize.width > 1 && controller.videoSize.height > 1 {
            return controller.videoSize.width / controller.videoSize.height
        }
        return 0.48
    }
}

@MainActor
final class ScreenPopout: NSObject, NSWindowDelegate {
    static let shared = ScreenPopout()
    private var window: NSWindow?
    private weak var controller: PhoneVideoStreamController?
    func show(controller: PhoneVideoStreamController) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        self.controller = controller
        controller.isDetached = true
        let ratio = streamAspectRatio
        let height = min(720, (NSScreen.main?.visibleFrame.height ?? 800) - 80)
        let initialContentSize = NSSize(width: (height - 48) * ratio + 8, height: height)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: initialContentSize.width, height: initialContentSize.height), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Phone screen"
        window.contentView = NSHostingView(rootView: CompactStreamPopout(controller: controller))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
    private var streamAspectRatio: CGFloat {
        guard let controller, controller.videoSize.height > 1 else { return 0.48 }
        return controller.videoSize.width / controller.videoSize.height
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let titleBarHeight = sender.frame.height - sender.contentLayoutRect.height
        let contentHeight = max(280, frameSize.height - titleBarHeight)
        return NSSize(width: (contentHeight - 48) * streamAspectRatio + 8,
                      height: contentHeight + titleBarHeight)
    }
    func windowWillClose(_ notification: Notification) {
        controller?.isDetached = false
        window = nil
    }
}

private struct CompactStreamPopout: View {
    @ObservedObject var controller: PhoneVideoStreamController
    var body: some View {
        VStack(spacing: 4) {
            PhoneVideoSurface(controller: controller)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 24) {
                navigationButton("Back", symbol: "chevron.left", command: "back")
                navigationButton("Home", symbol: "circle", command: "home")
                navigationButton("Recent apps", symbol: "square", command: "recents")
            }.frame(height: 36)
        }.padding(4)
    }
    private func navigationButton(_ title: String, symbol: String, command: String) -> some View {
        Button { controller.input(kind: command) } label: {
            Image(systemName: symbol).frame(width: 32, height: 32)
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}
