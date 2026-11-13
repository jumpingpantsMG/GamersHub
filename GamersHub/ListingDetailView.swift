import SwiftUI

struct ListingDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(HiddenStore.self) private var hidden
    @Environment(\.dismiss) private var dismiss
    let listingID: UUID
    let store: ListingsStore
    let onVisit: (Listing) -> Void

    @State private var reviews: [Review] = []
    @State private var myID: UUID?
    @State private var loadingReviews = false
    @State private var writing = false
    @State private var reportingListing = false
    @State private var reportingReview: Review?
    @State private var error: String?

    /// Read from the store so the rating updates right after you review.
    private var listing: Listing? { store.listings.first { $0.id == listingID } }
    private var myReview: Review? { reviews.first { $0.userId == myID } }
    private var visibleReviews: [Review] { reviews.filter { !hidden.isBlocked($0.userId) } }

    var body: some View {
        Group {
            if let listing {
                content(listing)
            } else {
                Text("This listing is no longer available.").foregroundStyle(.secondary)
            }
        }
        .background(ThemedBackground())
        #if os(iOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #else
        .navigationTitle("Details")
        #endif
        .task { await loadReviews() }
    }

    @ViewBuilder
    private func content(_ listing: Listing) -> some View {
        GeometryReader { geo in
            // Wide windows (Mac, iPad landscape) get two columns instead of one narrow strip.
            let wide = geo.size.width >= 900

            ScrollView {
                VStack(spacing: 0) {
                    hero(listing)

                    Group {
                        if wide {
                            HStack(alignment: .top, spacing: 20) {
                                VStack(spacing: 16) {
                                    infoPanel(listing)
                                    ratingPanel(listing)
                                    descriptionPanel(listing)
                                }
                                .frame(width: 440)

                                VStack(spacing: 16) {
                                    reviewsSection(listing)
                                    safetyButtons
                                }
                                .padding(.top, 60)   // clears the part of the hero the left column overlaps
                                .frame(maxWidth: .infinity)
                            }
                        } else {
                            VStack(spacing: 16) {
                                infoPanel(listing)
                                ratingPanel(listing)
                                descriptionPanel(listing)
                                reviewsSection(listing)
                                safetyButtons
                            }
                            .frame(maxWidth: 640)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, -50)   // panel overlaps the bottom of the hero
                    .padding(.bottom, 24)
                    .frame(maxWidth: 1200)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(isPresented: $writing) {
            WriteReviewSheet(listing: listing, store: store, existing: myReview) {
                Task { await loadReviews() }
            }
        }
        .sheet(isPresented: $reportingListing) {
            ReportSheet(listing: listing, store: store)
        }
        .sheet(item: $reportingReview) { r in
            ReportSheet(listing: listing, review: r, store: store)
        }
    }

    // MARK: Pieces

    /// Cover image (or generated art) that stretches when you pull down.
    private func hero(_ listing: Listing) -> some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            ListingArt(category: listing.category, imageURL: listing.imageURL)
                .frame(width: geo.size.width, height: geo.size.height + max(0, minY))
                .offset(y: -max(0, minY))
        }
        .frame(height: 300)
        #if os(iOS)
        .ignoresSafeArea(edges: .top)
        #endif
    }

    private func infoPanel(_ listing: Listing) -> some View {
        let highlighted = listing.isSponsored || store.isFeatured(listing)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ListingThumb(listing: listing, size: 68)
                VStack(alignment: .leading, spacing: 7) {
                    Text(listing.title).font(theme.title(.title2))
                    HStack(spacing: 6) {
                        Chip(text: listing.category)
                        AgeBadge(rating: listing.ageRating)
                        if listing.isSponsored {
                            Label(theme.heading("Sponsored"), systemImage: "megaphone.fill")
                                .font(.caption.bold()).foregroundStyle(theme.accent2)
                                .themeGlow(theme.accent2, radius: 5)
                        } else if store.isFeatured(listing) {
                            Label(theme.heading("Featured"), systemImage: "flame.fill")
                                .font(.caption.bold()).foregroundStyle(.yellow)
                                .themeGlow(.yellow, radius: 5)
                        }
                    }
                    if let rank = listing.rank { RankBadge(rank: rank) }
                }
                Spacer(minLength: 0)
            }

            Button { onVisit(listing) } label: {
                Label(theme.heading("Visit site"), systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlowButtonStyle(large: true))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(featured: highlighted)
    }

    private func ratingPanel(_ listing: Listing) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(spacing: 4) {
                Text(listing.reviewCount == 0 ? "–" : String(format: "%.1f", listing.ratingValue))
                    .font(.system(size: 46, weight: .heavy, design: theme.design))
                    .themeGlow(theme.accent2, radius: 8)
                StarsView(rating: listing.ratingValue, size: 13)
                Text("\(listing.reviewCount) review\(listing.reviewCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(listing.clicks) visit\(listing.clicks == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            RatingHistogram(reviews: reviews)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func descriptionPanel(_ listing: Listing) -> some View {
        Text(listing.description)
            .font(.body)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }

    /// Report, hide, and block. Hiding and blocking stay on this device.
    @ViewBuilder
    private var safetyButtons: some View {
        if let listing {
            VStack(spacing: 12) {
                Button { reportingListing = true } label: {
                    Label("Report this listing", systemImage: "flag")
                }
                .foregroundStyle(.red)

                Button {
                    hidden.hide(listing)
                    dismiss()
                } label: {
                    Label("Hide this listing", systemImage: "eye.slash")
                }

                if listing.ownerId != nil && listing.ownerId != myID {
                    Button {
                        hidden.blockAdvertiser(of: listing)
                        dismiss()
                    } label: {
                        Label("Block this advertiser", systemImage: "person.crop.circle.badge.xmark")
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func reviewsSection(_ listing: Listing) -> some View {
        HStack {
            Text(theme.heading("Reviews"))
                .font(theme.title(.title3))
                .tracking(theme.tracking)
            Spacer()
            if myID != nil && listing.ownerId == myID {
                Text("Your listing").font(.footnote).foregroundStyle(.secondary)
            } else {
                Button(myReview == nil ? "Write a review" : "Edit your review") { writing = true }
                    .buttonStyle(GlowButtonStyle())
            }
        }

        if loadingReviews && reviews.isEmpty {
            ProgressView()
        } else if visibleReviews.isEmpty {
            Text("No reviews yet. Be the first.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 10) {
                ForEach(visibleReviews) { r in
                    ReviewRow(review: r, isMine: r.userId == myID,
                              onReport: { reportingReview = r },
                              onBlock: {
                                  hidden.blockUser(r.userId, label: "Reviewer on \"\(listing.title)\"")
                              },
                              onDelete: { Task { await delete(r) } })
                }
            }
        }

        if let error {
            Text(error).font(.footnote).foregroundStyle(.red)
        }
    }

    private func loadReviews() async {
        loadingReviews = true
        defer { loadingReviews = false }
        myID = await store.currentUserID()
        do {
            reviews = try await store.reviews(for: listingID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ review: Review) async {
        do {
            try await store.deleteReview(review)
            await loadReviews()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ReviewRow: View {
    let review: Review
    let isMine: Bool
    let onReport: () -> Void
    let onBlock: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StarsView(rating: Double(review.stars), size: 13)
                if isMine { Chip(text: "You") }
                Spacer()
                Text(review.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
                Menu {
                    if isMine {
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    } else {
                        Button("Hide reviews from this person", systemImage: "eye.slash", action: onBlock)
                        Button("Report", systemImage: "flag", role: .destructive, action: onReport)
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.secondary).padding(4)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if let comment = review.comment, !comment.isEmpty {
                Text(comment).font(.subheadline)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 16)
    }
}
