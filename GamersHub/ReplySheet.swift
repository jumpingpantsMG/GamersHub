//
//  ReplySheet.swift
//  GamersHub
//
//  Created by Jaiden Kumar on 14/11/26.
//


import SwiftUI

/// The advertiser answers a review. One reply per review, up to 300 characters.
struct ReplySheet: View {
    let review: Review
    let listing: Listing
    let store: ListingsStore
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var sending = false
    @State private var error: String?

    init(review: Review, listing: Listing, store: ListingsStore, onDone: @escaping () -> Void) {
        self.review = review
        self.listing = listing
        self.store = store
        self.onDone = onDone
        _text = State(initialValue: review.reply?.body ?? "")
    }

    private var valid: Bool { (1...300).contains(text.trimmingCharacters(in: .whitespacesAndNewlines).count) }

    var body: some View {
        NavigationStack {
            Form {
                Section("They wrote") {
                    StarsView(rating: Double(review.stars), size: 13)
                    if let c = review.comment, !c.isEmpty { Text(c) }
                }
                Section("Your reply (shown publicly)") {
                    TextField("Thanks for playing!", text: $text, axis: .vertical).lineLimit(3...6)
                    Text("\(text.count)/300").font(.caption).foregroundStyle(.secondary)
                }
                if review.reply != nil {
                    Section {
                        Button("Delete reply", role: .destructive) { Task { await remove() } }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Reply")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { Task { await save() } }.disabled(!valid || sending)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    private func save() async {
        sending = true
        defer { sending = false }
        do {
            try await store.saveReply(to: review, on: listing, body: text)
            onDone(); dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func remove() async {
        do {
            try await store.deleteReply(to: review)
            onDone(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}