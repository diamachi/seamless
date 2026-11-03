import AppKit
import SwiftUI

@MainActor
final class AppNotices: ObservableObject {
    @Published private(set) var message: String?
    private var expiration: Task<Void, Never>?

    func show(_ message: String) {
        guard !message.isEmpty else { return }
        expiration?.cancel()
        self.message = message
        expiration = Task {
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            self.message = nil
        }
    }

    func dismiss() {
        expiration?.cancel()
        message = nil
    }
}

@MainActor
private final class ActivityPopupState: ObservableObject {
    @Published var isExpanded = true
}

// Window-level placement keeps transfers accessible while changing pages.
struct ActivityPopup: View {
    @ObservedObject var bulk: BulkTransfers
    @ObservedObject var legacy: FileTransfers
    @ObservedObject var folders: FolderDownloads
    @ObservedObject var notices: AppNotices
    @StateObject private var state = ActivityPopupState()
    @Environment(\.colorScheme) private var colorScheme

    private var transferCount: Int {
        bulk.activities.count + bulk.offers.count + legacy.activities.count + legacy.offers.count
    }

    var body: some View {
        if transferCount > 0 || folders.isListing || notices.message != nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(transferCount > 0 ? "File transfers (\(transferCount))" : "Seamless", systemImage: "arrow.up.arrow.down")
                        .font(.headline)
                    Spacer()
                    if transferCount > 0 || folders.isListing {
                        Button {
                            state.isExpanded.toggle()
                        } label: {
                            Image(systemName: state.isExpanded ? "chevron.down" : "chevron.up")
                        }.accessibilityLabel(state.isExpanded ? "Collapse transfers" : "Expand transfers")
                    }
                    if notices.message != nil {
                        Button { notices.dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Dismiss notice")
                    }
                }
                if let message = notices.message {
                    Text(message).font(.callout).textSelection(.enabled)
                }
                if state.isExpanded && (transferCount > 0 || folders.isListing) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(bulk.offers) { offer in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(offer.name).fontWeight(.medium).lineLimit(2)
                                    Text(ByteCountFormatter.string(fromByteCount: offer.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        IncomingFileDragHandle(offer: offer, transfers: bulk).frame(width: 28, height: 28)
                                        Spacer()
                                        Button("Decline") { bulk.reject(id: offer.id, phoneID: offer.phoneID) }
                                        Button("Save to Downloads") { bulk.accept(offer) }
                                            .buttonStyle(WorkspaceButtonStyle(prominent: true))
                                    }
                                }
                            }
                            ForEach(bulk.activities) { activity in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(activity.name).lineLimit(1)
                                        Spacer()
                                        Button("Cancel") { bulk.reject(id: activity.id, phoneID: activity.phoneID) }
                                    }
                                    ProgressView(value: Double(activity.completed), total: Double(max(1, activity.size)))
                                    Text(activity.status + " · " + ByteCountFormatter.string(fromByteCount: activity.completed, countStyle: .file))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            ForEach(legacy.offers) { offer in
                                Text(offer.name).lineLimit(2)
                                HStack {
                                    Button("Accept and save…") { legacy.accept(offer) }
                                    Button("Decline") { legacy.reject(offer) }
                                }
                            }
                            ForEach(legacy.activities) { activity in
                                Text(activity.name).lineLimit(1)
                                ProgressView(value: Double(activity.completedBytes), total: Double(max(1, activity.totalBytes)))
                                Text(activity.status).font(.caption)
                                Button("Cancel") { legacy.cancelTransfer(activity) }
                            }
                            if folders.isListing {
                                Text(folders.message).font(.caption)
                                Button("Cancel queued downloads") { folders.cancel() }
                            }
                        }.padding(.trailing, 4)
                    }.frame(height: min(260, CGFloat(max(1, transferCount)) * 110))
                }
            }
            .padding(18)
            .frame(maxWidth: 460)
            .background(InterfacePalette(scheme: colorScheme).surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(InterfacePalette(scheme: colorScheme).border))
            .shadow(color: .black.opacity(0.15), radius: 18, y: 6)
            .buttonStyle(WorkspaceButtonStyle())
            .padding(20)
        }
    }
}
