import SwiftUI
import Charts

/// Visits per day, reviews over time, and how each sponsorship performed.
struct StatsView: View {
    let listing: Listing
    let store: ListingsStore
    var ownerView = true
    @Environment(\.dismiss) private var dismiss

    @State private var days = 30
    @State private var stats: ListingStats?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Range", selection: $days) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                    .pickerStyle(.segmented)

                    if let stats {
                        content(stats)
                    } else if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }

                    if let error {
                        Text(error).foregroundStyle(.red)
                    }

                    Text(ownerView ? "Each device counts once per day for each of impressions, page views and visits." : "Public numbers: each device counts once per day.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(ownerView ? "Stats" : "Public stats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task(id: days) { await load() }
            .refreshable { await Task { await load() }.value }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
    }

    @ViewBuilder
    private func content(_ s: ListingStats) -> some View {
        let visits = s.daily.reduce(0) { $0 + $1.visits }
        let views = s.daily.reduce(0) { $0 + $1.views }
        let newReviews = s.reviews.reduce(0) { $0 + $1.count }

        HStack(spacing: 10) {
            tile("Visits", "\(visits)", "last \(days) days")
            tile("Page views", "\(views)", "last \(days) days")
            tile("New reviews", "\(newReviews)", "last \(days) days")
        }

        section("Visits per day") {
            if visits == 0 {
                empty("No visits in this range yet.")
            } else {
                Chart(s.daily) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("Visits", d.visits))
                        .foregroundStyle(.tint)
                }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: 180)
            }
        }

        section("Reviews over time") {
            if s.reviews.allSatisfy({ $0.avg == nil }) {
                empty("No reviews yet.")
            } else {
                Chart(s.reviews) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("New reviews", d.count))
                        .foregroundStyle(.tint.opacity(0.7))
                }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .frame(height: 120)

                Text("Average rating over time").font(.footnote).foregroundStyle(.secondary)
                Chart(s.reviews.filter { $0.avg != nil }) { d in
                    LineMark(x: .value("Day", d.date, unit: .day), y: .value("Average", d.avg ?? 0))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(.yellow)
                }
                .chartYScale(domain: 1...5)
                .frame(height: 120)
            }
        }

        if ownerView {
        section("Sponsorship performance") {
            if s.sponsorships.isEmpty {
                empty("You haven't sponsored this listing yet. After you do, you'll see how many people saw it and how many tapped Visit.")
            } else {
                ForEach(s.sponsorships) { sp in
                    sponsorshipRow(sp)
                }
            }
            if s.totals.impressions > 0 && !s.daily.allSatisfy({ $0.impressions == 0 }) {
                Text("People who saw your Sponsored card, per day").font(.footnote).foregroundStyle(.secondary)
                Chart(s.daily) { d in
                    AreaMark(x: .value("Day", d.date, unit: .day), y: .value("Seen", d.impressions))
                        .foregroundStyle(.tint.opacity(0.4))
                    LineMark(x: .value("Day", d.date, unit: .day), y: .value("Seen", d.impressions))
                        .foregroundStyle(.tint)
                }
                .frame(height: 120)
            }
        }
        }
    }

    private func sponsorshipRow(_ sp: SponsorshipStat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(StatsDates.pretty(sp.startsAt)) to \(StatsDates.pretty(sp.endsAt))", systemImage: "megaphone.fill")
                    .font(.subheadline.weight(.semibold))
                if sp.active { Text("Active").font(.caption2.bold()).foregroundStyle(.green) }
                Spacer()
                Text("\(sp.days) days").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                tile("Seen", "\(sp.impressions)", nil)
                tile("Page views", "\(sp.views)", nil)
                tile("Visits", "\(sp.visits)", nil)
                tile("Visit rate", sp.visitRate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "–", nil)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Pieces

    private func tile(_ title: String, _ value: String, _ footnote: String?) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let footnote { Text(footnote).font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            body()
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            stats = try await store.stats(for: listing, days: days, owner: ownerView)
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
