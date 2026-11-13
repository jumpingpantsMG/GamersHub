import SwiftUI
import Observation

struct HiddenEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let label: String
}

/// Things this person chose not to see. Kept on the device only.
@MainActor
@Observable
final class HiddenStore {
    private(set) var listings: [HiddenEntry]
    private(set) var users: [HiddenEntry]      // advertisers and reviewers alike (both are just users)

    private let listingsKey = "hiddenListings.v1"
    private let usersKey = "blockedUsers.v1"

    init() {
        let d = UserDefaults.standard
        listings = Self.load(d.data(forKey: listingsKey))
        users = Self.load(d.data(forKey: usersKey))
    }

    var isEmpty: Bool { listings.isEmpty && users.isEmpty }

    func isHidden(_ l: Listing) -> Bool {
        listings.contains { $0.id == l.id } || (l.ownerId.map { isBlocked($0) } ?? false)
    }

    func isBlocked(_ userID: UUID) -> Bool { users.contains { $0.id == userID } }

    func hide(_ l: Listing) {
        guard !listings.contains(where: { $0.id == l.id }) else { return }
        listings.append(HiddenEntry(id: l.id, label: l.title))
        save()
    }

    func blockAdvertiser(of l: Listing) {
        guard let owner = l.ownerId else { return }
        blockUser(owner, label: "Advertiser of \"\(l.title)\"")
    }

    func blockUser(_ id: UUID, label: String) {
        guard !isBlocked(id) else { return }
        users.append(HiddenEntry(id: id, label: label))
        save()
    }

    func unhide(_ e: HiddenEntry) {
        listings.removeAll { $0.id == e.id }
        save()
    }

    func unblock(_ e: HiddenEntry) {
        users.removeAll { $0.id == e.id }
        save()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(listings), forKey: listingsKey)
        d.set(try? JSONEncoder().encode(users), forKey: usersKey)
    }

    private static func load(_ data: Data?) -> [HiddenEntry] {
        guard let data, let list = try? JSONDecoder().decode([HiddenEntry].self, from: data) else { return [] }
        return list
    }
}

struct HiddenItemsView: View {
    let hidden: HiddenStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if hidden.isEmpty {
                    Text("Nothing hidden or blocked. Use the ... menu on a listing to hide it or block its advertiser.")
                        .foregroundStyle(.secondary)
                }
                if !hidden.listings.isEmpty {
                    Section("Hidden listings") {
                        ForEach(hidden.listings) { e in
                            HStack {
                                Text(e.label)
                                Spacer()
                                Button("Unhide") { hidden.unhide(e) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
                if !hidden.users.isEmpty {
                    Section("Blocked advertisers and reviewers") {
                        ForEach(hidden.users) { e in
                            HStack {
                                Text(e.label)
                                Spacer()
                                Button("Unblock") { hidden.unblock(e) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hidden and blocked")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 400)
        #endif
    }
}
