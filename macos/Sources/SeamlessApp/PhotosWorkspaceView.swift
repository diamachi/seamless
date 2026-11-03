import AppKit
import SwiftUI

@MainActor
private final class PhotosWorkspaceState: ObservableObject {
    @Published var selected: Set<String> = []
    @Published var cellSize = 180.0
    @Published var filter = "All"
}

struct PhotosWorkspaceView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var browser: PhoneStorageBrowser
    @ObservedObject var bulk: BulkTransfers
    @StateObject private var state = PhotosWorkspaceState()
    @Environment(\.colorScheme) private var colorScheme

    private var media: [PhoneStorageEntry] {
        browser.entries.filter {
            if state.filter == "Photos" { return $0.mime.hasPrefix("image/") }
            if state.filter == "Videos" { return $0.mime.hasPrefix("video/") }
            return $0.mime.hasPrefix("image/") || $0.mime.hasPrefix("video/")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                WorkspaceHeading(title: "Photos", subtitle: "Your phone’s library, on a bigger canvas.")
                Spacer()
                if !state.selected.isEmpty {
                    Button("Save \(state.selected.count) to Downloads", action: saveSelection)
                        .buttonStyle(WorkspaceButtonStyle(prominent: true))
                }
                Button("Refresh") { state.selected = []; browser.refresh() }
            }
            HStack(spacing: 20) {
                WorkspaceSegments(options: ["All", "Photos", "Videos"].map { ($0, $0) }, selection: $state.filter)
                Spacer()
                Image(systemName: "square.grid.3x3")
                Slider(value: $state.cellSize, in: 110...300).frame(width: 140).accessibilityLabel("Thumbnail size")
                Button(state.selected.count == media.count && !media.isEmpty ? "Deselect all" : "Select loaded") {
                    if state.selected.count == media.count { state.selected = [] }
                    else { state.selected = Set(media.map(\.id)) }
                }
            }
            Text(browser.message).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: state.cellSize), spacing: 16)], spacing: 16) {
                    ForEach(media) { entry in
                        Button {
                            if state.selected.contains(entry.id) { state.selected.remove(entry.id) }
                            else { state.selected.insert(entry.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                ZStack(alignment: .topTrailing) {
                                    // GeometryReader constrains fill-mode images to the grid's assigned width.
                                    GeometryReader { geometry in
                                        Group {
                                            if let image = browser.thumbnails[entry.id] {
                                                Image(nsImage: image).resizable().scaledToFill()
                                            } else {
                                                Rectangle().fill(InterfacePalette(scheme: colorScheme).raisedSurface)
                                                    .overlay {
                                                        Image(systemName: entry.mime.hasPrefix("video/") ? "play.rectangle" : "photo").font(.title)
                                                    }
                                            }
                                        }
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                        .clipped()
                                    }.frame(height: state.cellSize * 0.75)
                                    Image(systemName: state.selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(state.selected.contains(entry.id) ? .yellow : .white).font(.title3).padding(10)
                                }.clipShape(RoundedRectangle(cornerRadius: 14))
                                Label(entry.name, systemImage: entry.mime.hasPrefix("video/") ? "video" : "photo")
                                    .font(.caption).lineLimit(1)
                            }.padding(6)
                                .background(InterfacePalette(scheme: colorScheme).surface, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).task(id: entry.id) { browser.thumbnail(entry) }
                    }
                }
                if browser.nextOffset >= 0 { Button("Load more") { browser.more() }.padding() }
                if media.isEmpty && !browser.isLoading {
                    Text("Enable All files access in the Android companion, or choose media there, then refresh.")
                        .foregroundStyle(.secondary).padding(30)
                }
            }
        }
        .buttonStyle(WorkspaceButtonStyle())
        .task(id: preferencesStore.preferences.selectedPhoneID) {
            if let phoneID = preferencesStore.preferences.selectedPhoneID { browser.load(phoneID: phoneID, media: true) }
        }
    }

    private func saveSelection() {
        guard let phoneID = preferencesStore.preferences.selectedPhoneID else { return }
        guard let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        bulk.enqueueBrowserDownloads(phoneID: phoneID, entries: browser.entries.filter { state.selected.contains($0.id) }, directory: directory)
        state.selected = []
    }
}
