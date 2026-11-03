import AppKit
import SwiftUI
import SeamlessCore

@MainActor
private final class FilesWorkspaceState: ObservableObject {
    @Published var tab = "Storage"
    @Published var selected: Set<String> = []
}

struct FilesWorkspaceView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var bulk: BulkTransfers
    @ObservedObject var browser: PhoneStorageBrowser
    @StateObject private var state = FilesWorkspaceState()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WorkspaceHeading(title: "Files", subtitle: "Your files and memories, within reach.")
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        storage.frame(minWidth: 300, maxWidth: .infinity)
                        transfers.frame(minWidth: 320, maxWidth: 440)
                    }
                    VStack(alignment: .leading, spacing: 20) { storage; transfers }
                }

            }.padding(.bottom, 24)
        }
        .buttonStyle(WorkspaceButtonStyle())
        .onChange(of: browser.entries.map(\.id)) { _, ids in state.selected.formIntersection(Set(ids)) }
        .task(id: phoneID) {
            if let phoneID { browser.load(phoneID: phoneID, media: false) }
        }

    }

    private var phoneID: String? { preferencesStore.preferences.selectedPhoneID }

    private var transfers: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkspaceCard {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "arrow.up.arrow.down.doc").font(.system(size: 30, weight: .light)).foregroundStyle(.tint)
                    Text("Drop files here").font(.headline)
                    Text("Or drop them anywhere in this window to send to your selected phone.").foregroundStyle(.secondary)
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            if let phoneID {
                                if bulk.supportedPhones.contains(phoneID) { bulk.choose(phoneID: phoneID) }
                                else { preferencesStore.connections.files.chooseAndOffer(phoneID: phoneID) }
                            }
                        } label: { Label("Choose files…", systemImage: "plus") }
                        .buttonStyle(WorkspaceButtonStyle(prominent: true))
                        .disabled(phoneID.map { preferencesStore.sessions.state(for: $0) != .connected } ?? true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let phoneID, !bulk.supportedPhones.contains(phoneID) {
                    Text("Older companion: transfers use the previous 20 MiB path. Send and install the latest APK here to enable large transfers and browsing.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !bulk.downloads.filter({ $0.phoneID == phoneID }).isEmpty {
                Text("Received on this Mac").font(.headline)
                ForEach(bulk.downloads.filter { $0.phoneID == phoneID }) { download in
                    WorkspaceCard {
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: download.url.path)).resizable().frame(width: 32, height: 32)
                            Text(download.url.lastPathComponent)
                            Spacer()
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([download.url]) }
                        }
                    }.onDrag { NSItemProvider(contentsOf: download.url) ?? NSItemProvider() }
                }
                Text("Drag a received file into Finder or another app.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button { browser.back() } label: { Image(systemName: "chevron.left") }.disabled(browser.breadcrumbs.count <= 1)
                Text(browser.breadcrumbs.last?.1 ?? "Phone storage").font(.headline).lineLimit(1)
                Spacer()
                if browser.isLoading { ProgressView().controlSize(.small) }
                Button("Select loaded") { state.selected = Set(browser.entries.map(\.id)) }
                if !state.selected.isEmpty {
                    Button("Save \(state.selected.count) to Downloads") {
                        browser.saveToDownloads(browser.entries.filter { state.selected.contains($0.id) }, bulk: bulk)
                        state.selected = []
                    }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                }
                Button("Refresh") { browser.refresh() }
            }
            Text(browser.message).font(.callout).foregroundStyle(.secondary)
            if state.tab == "Storage" {
                LazyVStack(spacing: 10) {
                    ForEach(browser.entries) { entry in entryRow(entry) }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 16) {
                    ForEach(browser.entries.filter { state.tab == "Videos" ? $0.mime.hasPrefix("video/") : $0.mime.hasPrefix("image/") }) { entry in
                        WorkspaceCard {
                            Group {
                                if let image = browser.thumbnails[entry.id] { Image(nsImage: image).resizable().scaledToFit() }
                                else { Image(systemName: state.tab == "Videos" ? "play.rectangle" : "photo").font(.largeTitle).foregroundStyle(.tint) }
                            }.frame(maxWidth: .infinity).frame(height: 120)
                            Text(entry.name).font(.caption).lineLimit(2)
                            Button("Save to Mac") { browser.download(entry) }
                        }.task(id: entry.id) { browser.thumbnail(entry) }
                    }
                }
            }
            if browser.nextOffset >= 0 { Button("Load more") { browser.more() } }
            Text("Enable All files access on the phone for shared storage and its photo library. You can also share selected folders or media. Android private app data stays protected.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func entryRow(_ entry: PhoneStorageEntry) -> some View {
        WorkspaceCard {
            HStack(spacing: 14) {
                Toggle("Select \(entry.name)", isOn: Binding(
                    get: { state.selected.contains(entry.id) },
                    set: { selected in
                        if selected { state.selected.insert(entry.id) }
                        else { state.selected.remove(entry.id) }
                    }
                )).labelsHidden().toggleStyle(.checkbox)
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc").foregroundStyle(.tint).frame(width: 26)
                Text(entry.name).lineLimit(2)
                Spacer()
                if !entry.isDirectory { Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                if entry.isDirectory { Button("Open") { browser.open(entry) } }
                Button(entry.isDirectory ? "Save folder" : "Save to Downloads") { browser.saveToDownloads([entry], bulk: bulk) }
            }
        }
    }
}
