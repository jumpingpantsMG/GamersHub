import SwiftUI
import Supabase

/// What a signed-in advertiser sees: their listings (edit, sponsor, delete) and their account.
struct AdvertiserHome: View {
    let store: ListingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var mine: [Listing] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showNew = false
    @State private var editing: Listing?
    @State private var sponsoring: Listing?
    @State private var deleting: Listing?
    @State private var showDeleteAccount = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                if mine.isEmpty && !loading {
                    Text("No listings yet. Tap + to add your first site. It's free.")
                        .foregroundStyle(.secondary)
                }

                ForEach(mine) { l in
                    row(l)
                }

                Section("Account") {
                    Button("Sign out") {
                        Task { try? await supabase.auth.signOut() }
                    }
                    Button("Delete account", role: .destructive) { showDeleteAccount = true }
                        .disabled(working)
                }

                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("My listings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showNew = true } label: { Label("New listing", systemImage: "plus") }
                }
            }
            .task { await loadMine() }
            .refreshable { await loadMine() }
            .sheet(isPresented: $showNew, onDismiss: { Task { await loadMine() } }) {
                SubmitListingView(store: store)
            }
            .sheet(item: $editing, onDismiss: { Task { await loadMine() } }) { l in
                SubmitListingView(store: store, editing: l)
            }
            .sheet(item: $sponsoring) { l in
                FeatureSheet(listing: l) {
                    Task {
                        await loadMine()
                        await store.load()
                    }
                }
            }
            .confirmationDialog(
                "Delete this listing?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { l in
                Button("Delete \"\(l.title)\"", role: .destructive) { Task { await delete(l) } }
            } message: { _ in
                Text("Its reviews are removed too. This can't be undone, and any sponsorship time left on it is lost.")
            }
            .alert("Delete your account?", isPresented: $showDeleteAccount) {
                Button("Cancel", role: .cancel) {}
                Button("Delete account", role: .destructive) { Task { await deleteAccount() } }
            } message: {
                Text("This permanently deletes your account, all your listings, and your reviews. Purchases you've already made can't be refunded by deleting your account.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    // MARK: Row

    private func row(_ l: Listing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l.title).font(.headline)
                Spacer()
                AgeBadge(rating: l.ageRating)
            }
            if l.isSponsored, let until = l.sponsoredUntil {
                Label("Sponsored until \(until.formatted(date: .abbreviated, time: .shortened))",
                      systemImage: "megaphone.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button { editing = l } label: { Label("Edit", systemImage: "pencil") }
                Button { sponsoring = l } label: {
                    Label(l.isSponsored ? "Extend" : "Sponsor", systemImage: "megaphone")
                }
                Spacer()
                Button(role: .destructive) { deleting = l } label: { Image(systemName: "trash") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: Actions

    private func loadMine() async {
        loading = true
        defer { loading = false }
        do {
            let uid = try await supabase.auth.session.user.id
            mine = try await supabase
                .from("listings")
                .select()
                .eq("owner_id", value: uid)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ l: Listing) async {
        error = nil
        do {
            try await store.delete(l)
            await loadMine()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await store.deleteAccount()
            dismiss()
        } catch {
            self.error = "Couldn't delete the account: \(error.localizedDescription)"
        }
    }
}
