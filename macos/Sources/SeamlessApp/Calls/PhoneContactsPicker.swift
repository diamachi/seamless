import SwiftUI
import SeamlessCore

struct CallingContact: Identifiable {
    let id: String
    let name: String
    let number: String
}

@MainActor
final class PhoneContactsStore: ObservableObject {
    @Published private(set) var contacts: [CallingContact] = []
    @Published private(set) var message = "Load contacts from your phone."
    @Published private(set) var isLoading = false
    private var phoneID: String?
    var sourcePhoneID: String? { phoneID }
    private var token: String?
    private var nextPage = 0
    private var deadline: Task<Void, Never>?
    var send: ((String, ControlPacket) -> Void)?

    func load(phoneID: String) {
        clear(phoneID: nil)
        self.phoneID = phoneID
        let requestToken = UUID().uuidString
        token = requestToken
        isLoading = true
        message = "Approve Contacts access in Seamless on your phone."
        send?(phoneID, ControlPacket(type: "contactsRequest", payload: .object(["token": .string(requestToken)])))
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(90)) } catch { return }
            guard let self, self.token == requestToken, self.isLoading else { return }
            self.isLoading = false
            self.message = "Contacts request timed out. Check the phone and try again."
            self.token = nil
        }
    }

    func receive(_ packet: ControlPacket, phoneID: String) {
        guard self.phoneID == phoneID, isLoading, packet.payload["token"].string == token else { return }
        if packet.type == "contactsError" {
            message = packet.payload["message"].string ?? "Contacts are unavailable."
            isLoading = false
            token = nil
            deadline?.cancel()
            return
        }
        guard nextPage < 50, packet.payload["index"].number == Double(nextPage),
              case .array(let entries) = packet.payload["contacts"], entries.count <= 100,
              contacts.count + entries.count <= 5000 else { return }
        var pageContacts: [CallingContact] = []
        for entry in entries {
            guard let id = entry["id"].string, id.count <= 80,
                  let name = entry["name"].string, name.utf16.count <= 200,
                  let number = entry["number"].string, number.utf16.count <= 80,
                  let dialNumber = PhoneCallState.dialNumber(number) else { continue }
            pageContacts.append(CallingContact(id: "\(nextPage)-\(id)", name: name, number: dialNumber))
        }
        contacts.append(contentsOf: pageContacts)
        nextPage += 1
        if packet.payload["last"].boolean == true {
            isLoading = false
            message = "\(contacts.count) phone numbers · kept only during this connection"
            deadline?.cancel()
            token = nil
        }
    }

    func clear(phoneID: String?) {
        if let phoneID, self.phoneID != phoneID { return }
        deadline?.cancel()
        contacts = []
        self.phoneID = nil
        token = nil
        nextPage = 0
        isLoading = false
        message = "Load contacts from your phone."
    }
}

@MainActor
private final class ContactSearch: ObservableObject {
    @Published var text = ""
}

struct PhoneContactsPicker: View {
    @ObservedObject var contacts: PhoneContactsStore
    let phoneID: String
    let choose: (CallingContact) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var search = ContactSearch()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Phone contacts").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            TextField("Search name or number", text: $search.text).textFieldStyle(WorkspaceTextFieldStyle())
            HStack {
                Text(contacts.message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(contacts.isLoading ? "Loading…" : "Refresh") { contacts.load(phoneID: phoneID) }
                    .disabled(contacts.isLoading)
            }
            if contacts.isLoading { ProgressView() }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredContacts) { contact in
                        Button {
                            choose(contact)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle").font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(contact.name.isEmpty ? "Contact" : contact.name).font(.headline)
                                    Text(contact.number).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(WorkspaceButtonStyle())
                    }
                }
            }
            Text("Selecting a contact fills the dial field. Press Call to place the call.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 520, height: 560)
            .background(InterfacePalette(scheme: colorScheme).canvas)
            .task(id: phoneID) {
                if contacts.sourcePhoneID != phoneID || contacts.contacts.isEmpty { contacts.load(phoneID: phoneID) }
            }
    }

    private var filteredContacts: [CallingContact] {
        guard contacts.sourcePhoneID == phoneID else { return [] }
        if search.text.isEmpty { return contacts.contacts }
        return contacts.contacts.filter {
            $0.name.localizedCaseInsensitiveContains(search.text) || $0.number.contains(search.text)
        }
    }
}
