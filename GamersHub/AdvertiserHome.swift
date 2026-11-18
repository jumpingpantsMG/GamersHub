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
    @State private var verifying: Listing?
    @State private var viewingStats: Listing?
    @State private var showDeleteAccount = false

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
            .refreshable { await Task { await loadMine() }.value }
            .sheet(isPresented: $showNew, onDismiss: { Task { await loadMine() } }) {
                SubmitListingView(store: store)
            }
            .sheet(item: $editing, onDismiss: { Task { await loadMine() } }) { l in
                SubmitListingView(store: store, editing: l)
            }
            .sheet(item: $sponsoring) { l in
                FeatureSheet(listing: l, store: store) {
                    Task {
                        await loadMine()
                        await store.load()
                    }
                }
            }
            .sheet(item: $viewingStats) { l in
                StatsView(listing: l, store: store)
            }
            .sheet(item: $verifying) { l in
                VerifySiteSheet(listing: l, store: store) {
                    Task { await loadMine() }
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
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountSheet(store: store) { dismiss() }
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
                if l.verified { VerifiedBadge() }
                AgeBadge(rating: l.ageRating)
            }
            if l.isSponsored, let until = l.sponsoredUntil {
                Label("Sponsored until \(until.formatted(date: .abbreviated, time: .shortened))",
                      systemImage: "megaphone.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else if l.isScheduled, let from = l.sponsoredFrom, let until = l.sponsoredUntil {
                Label("Sponsored \(from.formatted(date: .abbreviated, time: .omitted)) to \(until.formatted(date: .abbreviated, time: .omitted))",
                      systemImage: "calendar")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button { editing = l } label: { Label("Edit", systemImage: "pencil") }
                Button { viewingStats = l } label: { Label("Stats", systemImage: "chart.bar") }
                Button { sponsoring = l } label: {
                    Label(l.isSponsored || l.isScheduled ? "Extend" : "Sponsor", systemImage: "megaphone")
                }
                if !l.verified {
                    Button { verifying = l } label: { Label("Verify", systemImage: "checkmark.seal") }
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
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
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

}
