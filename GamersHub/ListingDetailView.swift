import SwiftUI

struct ListingDetailView: View {
    @Environment(\.theme) private var theme
    @Environment(HiddenStore.self) private var hidden
    @Environment(SavedStore.self) private var saved
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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
    @State private var replying: Review?
    @State private var votes: Set<UUID> = []
    @State private var levels: [UUID: Int] = [:]
    @State private var showStats = false

    /// Read from the store so the rating updates right after you review.
    private var listing: Listing? { store.listings.first { $0.id == listingID } }
    private var myReview: Review? { reviews.first { $0.userId == myID } }
    private var visibleReviews: [Review] {
        reviews.filter { !hidden.isBlocked($0.userId) }.sorted {
            let a = $0.helpfulCount ?? 0, b = $1.helpfulCount ?? 0
            return a != b ? a > b : $0.createdAt > $1.createdAt
        }
    }
    private var isOwner: Bool { myID != nil && listing?.ownerId == myID }

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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let listing {
                    ShareLink(item: ShareConfig.url(for: listing),
                              subject: Text(listing.title),
                              message: Text("Check out \(listing.title) on GamersHub")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button { saved.toggle(listing) } label: {
                        Label(saved.isSaved(listing) ? "Remove from saved" : "Save",
                              systemImage: saved.isSaved(listing) ? "heart.fill" : "heart")
                    }
                }
            }
        }
        .task { await loadReviews() }
        .task { if let listing { store.recordEvent(listing, .view) } }
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
                                    mediaPanel(listing)
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
                                mediaPanel(listing)
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
        .sheet(item: $replying) { r in
            ReplySheet(review: r, listing: listing, store: store) { Task { await loadReviews() } }
        }
        .sheet(isPresented: $showStats) {
            StatsView(listing: listing, store: store, ownerView: isOwner)
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
                        if listing.verified { VerifiedBadge() }
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
                Button { showStats = true } label: {
                    Label("Stats", systemImage: "chart.bar")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent2)
                .padding(.top, 2)
            }
            RatingHistogram(reviews: reviews)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func descriptionPanel(_ listing: Listing) -> some View {
        let badges = listingBadges(listing)
        return VStack(alignment: .leading, spacing: 12) {
            Text(listing.description).font(.body)
            if !badges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(badges, id: \.self) { Chip(text: $0) } }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// Screenshots and trailer link. The trailer opens in the browser, nothing is embedded.
    @ViewBuilder
    private func mediaPanel(_ listing: Listing) -> some View {
        let trailer = listing.trailerURL.flatMap { URL(string: $0) }.flatMap { $0.scheme == "https" ? $0 : nil }
        if !listing.shots.isEmpty || trailer != nil {
            VStack(alignment: .leading, spacing: 12) {
                if !listing.shots.isEmpty {
                    Text(theme.heading("Screenshots")).font(theme.title(.headline))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(listing.shots, id: \.self) { s in
                                AsyncImage(url: URL(string: s)) { phase in
                                    switch phase {
                                    case .success(let image): image.resizable().scaledToFill()
                                    case .failure: Image(systemName: "photo").foregroundStyle(.secondary)
                                    default: ProgressView()
                                    }
                                }
                                .frame(width: 284, height: 160)
                                .background(.black.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
                if let trailer {
                    Button { openURL(trailer) } label: {
                        Label("Watch trailer", systemImage: "play.rectangle.fill")
                    }
                    .buttonStyle(GlowButtonStyle())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
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
                              isOwner: isOwner,
                              level: levels[r.userId],
                              helpful: votes.contains(r.id),
                              onHelpful: { Task { await toggleHelpful(r) } },
                              onReply: { replying = r },
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
            votes = await store.myHelpfulVotes(for: reviews.map(\.id))
            let stats = await store.reviewerStats(for: Array(Set(reviews.map(\.userId))))
            levels = Dictionary(uniqueKeysWithValues: stats.map { ($0.userId, $0.level) })
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Updates the count on screen right away, and puts it back if the server says no.
    private func toggleHelpful(_ review: Review) async {
        guard let i = reviews.firstIndex(where: { $0.id == review.id }) else { return }
        let on = !votes.contains(review.id)
        if on { votes.insert(review.id) } else { votes.remove(review.id) }
        reviews[i].helpfulCount = max(0, (reviews[i].helpfulCount ?? 0) + (on ? 1 : -1))
        do {
            try await store.setHelpful(review, on: on)
        } catch {
            if on { votes.remove(review.id) } else { votes.insert(review.id) }
            reviews[i].helpfulCount = max(0, (reviews[i].helpfulCount ?? 0) + (on ? -1 : 1))
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
    let isOwner: Bool
    let level: Int?
    let helpful: Bool
    let onHelpful: () -> Void
    let onReply: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StarsView(rating: Double(review.stars), size: 13)
                if isMine { Chip(text: "You") }
                if let level { LevelChip(level: level) }
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

            if let reply = review.reply {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Reply from the advertiser", systemImage: "arrowshape.turn.up.left.fill")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text(reply.body).font(.subheadline)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 14) {
                if !isMine {
                    Button(action: onHelpful) {
                        Label(helpful ? "Helpful" : "Mark helpful",
                              systemImage: helpful ? "hand.thumbsup.fill" : "hand.thumbsup")
                    }
                }
                if let n = review.helpfulCount, n > 0 {
                    Text("\(n) found this helpful").foregroundStyle(.secondary)
                }
                Spacer()
                if isOwner {
                    Button(review.reply == nil ? "Reply" : "Edit reply", action: onReply)
                }
            }
            .font(.caption)
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 16)
    }
}
