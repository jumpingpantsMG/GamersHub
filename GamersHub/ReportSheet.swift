import SwiftUI

/// Reports a listing, or a specific review on it when `review` is set.
struct ReportSheet: View {
    let listing: Listing
    var review: Review? = nil
    let store: ListingsStore
    @Environment(\.dismiss) private var dismiss

    private var reasons: [String] {
        review == nil
            ? ["Inappropriate or adult content", "Wrong age rating", "Scam or malicious site",
               "Spam or misleading", "Other"]
            : ["Offensive or abusive", "Spam or fake review", "Other"]
    }

    @State private var reason = ""
    @State private var note = ""
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section { Text("Thanks. We'll review this.") }
                } else {
                    Section(review == nil ? "Reporting \"\(listing.title)\"" : "Reporting a review") {
                        Picker("Reason", selection: $reason) {
                            ForEach(reasons, id: \.self) { Text($0).tag($0) }
                        }
                        TextField("Details (optional)", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(.red) }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Report")
            .onAppear { if reason.isEmpty { reason = reasons[0] } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { Task { await send() } }
                            .disabled(sending || reason.isEmpty)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 300)
        #endif
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            try await store.report(listing: listing, review: review, reason: reason, note: note)
            sent = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
