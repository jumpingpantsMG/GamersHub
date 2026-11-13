//
//  WriteReviewSheet.swift
//  GamersHub
//
//  Created by Jaiden Kumar on 10/11/26.
//


import SwiftUI

struct WriteReviewSheet: View {
    let listing: Listing
    let store: ListingsStore
    let existing: Review?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var stars: Int
    @State private var comment: String
    @State private var sending = false
    @State private var error: String?

    init(listing: Listing, store: ListingsStore, existing: Review?, onSaved: @escaping () -> Void) {
        self.listing = listing
        self.store = store
        self.existing = existing
        self.onSaved = onSaved
        _stars = State(initialValue: existing?.stars ?? 0)
        _comment = State(initialValue: existing?.comment ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your rating") {
                    StarPicker(stars: $stars)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
                Section("Comment (optional)") {
                    TextField("What did you think?", text: $comment, axis: .vertical)
                        .lineLimit(3...8)
                    Text("\(comment.count)/300")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("Reviews are public. Be honest and kind. Abusive reviews get removed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "Write a review" : "Edit review")
            .onChange(of: comment) { _, new in
                if new.count > 300 { comment = String(new.prefix(300)) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(stars == 0 || sending)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 380)
        #endif
    }

    private func save() async {
        sending = true
        error = nil
        defer { sending = false }
        do {
            try await store.saveReview(listingID: listing.id, stars: stars, comment: comment)
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
