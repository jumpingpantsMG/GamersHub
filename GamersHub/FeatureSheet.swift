import SwiftUI
import StoreKit
import Supabase

/// Pick a start date and a length. A slot is held before you pay, so you never pay for a sold-out day.
struct FeatureSheet: View {
    let listing: Listing
    let store: ListingsStore
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let purchases = PurchaseManager.shared

    @State private var start = Date()
    @State private var availability: [SlotDay] = []
    @State private var reserving = false
    @State private var succeeded = false
    @State private var note: String?
    @State private var bookedStart: String?

    /// Already sponsored (or booked)? New time is added after the current end.
    private var extending: Bool { (listing.sponsoredUntil ?? .distantPast) > Date() }
    private var effectiveStart: Date { extending ? (listing.sponsoredUntil ?? start) : start }

    /// First sold-out day inside a window of `days`, or nil. When extending, the first day is the
    /// listing's own current slot, so the server decides that one.
    private func fullDay(for days: Int) -> String? {
        let first = StatsDates.string(effectiveStart)
        let wanted = (0..<days).map { StatsDates.string(StatsDates.addingDays($0, to: effectiveStart)) }
            .dropFirst(extending ? 1 : 0)
        return availability.first { wanted.contains($0.day) && $0.isFull && $0.day >= first }?.day
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sponsor \"\(listing.title)\"") {
                    Text("Sponsored listings get the large spotlight cards at the top of the feed, labeled Sponsored. Slots are limited each day. Featured is separate and earned through ratings and visits.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if succeeded {
                    Section {
                        Label(bookedStart.map { "Booked. Your sponsorship starts \($0)." } ?? "Your listing is sponsored.",
                              systemImage: "checkmark.circle.fill")
                    }
                } else {
                    Section("Start") {
                        if extending, let until = listing.sponsoredUntil {
                            Text("New time is added after your current sponsorship, starting \(until.formatted(date: .abbreviated, time: .omitted)).")
                                .font(.subheadline)
                        } else {
                            DatePicker("Start date", selection: $start,
                                       in: Date()...StatsDates.addingDays(60, to: Date()),
                                       displayedComponents: .date)
                                .onChange(of: start) { Task { await loadAvailability() } }
                        }
                    }

                    Section("Choose a length") {
                        if purchases.products.isEmpty { ProgressView() }
                        ForEach(purchases.products) { product in
                            let d = PurchaseManager.days(for: product.id)
                            let full = fullDay(for: d)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(d) day\(d == 1 ? "" : "s")")
                                    if let full {
                                        Text("Sold out \(StatsDates.pretty(full))")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                Button(product.displayPrice) { Task { await buy(product, days: d) } }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(purchases.isWorking || reserving || full != nil)
                            }
                        }
                    }
                }

                if let note { Section { Text(note).foregroundStyle(.red) } }
                if let message = purchases.message { Section { Text(message).foregroundStyle(.red) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Get sponsored")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(succeeded ? "Done" : "Cancel") { dismiss() }
                }
            }
            .task {
                await purchases.loadProducts()
                await loadAvailability()
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func loadAvailability() async {
        availability = await store.availability(from: effectiveStart)
    }

    private func buy(_ product: Product, days: Int) async {
        reserving = true
        note = nil
        defer { reserving = false }
        do {
            let r = try await store.reserveSlot(for: listing, start: effectiveStart, days: days)
            if await purchases.buy(product, reservation: r.reservationId) {
                bookedStart = StatsDates.pretty(r.startsAt)
                succeeded = true
                onDone()
            }
        } catch let e as PostgrestError {
            note = e.message
            await loadAvailability()
        } catch {
            note = error.localizedDescription
        }
    }
}
