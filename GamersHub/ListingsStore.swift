import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class ListingsStore {
    var listings: [Listing] = []
    var isLoading = false
    var errorMessage: String?

    /// Listings that earned a "Featured" spot (best ratings and most visits), best first.
    /// Paid placements are "Sponsored" instead and never appear here.
    private(set) var featuredIDs: [UUID] = []
    private(set) var trendingIDs: [UUID] = []   // most visited and opened lately, best first

    func isFeatured(_ listing: Listing) -> Bool { featuredIDs.contains(listing.id) }

    // MARK: Listings

    /// Newest first. Featured vs. regular is split in the view.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            listings = try await supabase
                .from("listings")
                .select()
                .eq("is_hidden", value: false)   // admins can read hidden ones, the public feed shouldn't show them
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            featuredIDs = computeFeatured()
            trendingIDs = await fetchTrending()
        } catch is CancellationError {
            // The refresh gesture ended early. Not an error.
        } catch let e as URLError where e.code == .cancelled {
            // Same thing, from the network layer.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private struct TrendParams: Encodable { let p_days: Int; let p_limit: Int }
    private struct TrendRow: Decodable {
        let listingId: UUID
        enum CodingKeys: String, CodingKey { case listingId = "listing_id" }
    }

    private func fetchTrending() async -> [UUID] {
        let rows: [TrendRow] = (try? await supabase
            .rpc("trending_listings", params: TrendParams(p_days: 7, p_limit: 10))
            .execute().value) ?? []
        return rows.map(\.listingId)
    }

    /// One listing by id, for opening a shared link. Adds it to the feed if it wasn't loaded.
    func listing(id: UUID) async -> Listing? {
        if let l = listings.first(where: { $0.id == id }) { return l }
        let found: Listing? = try? await supabase.from("listings").select()
            .eq("id", value: id).eq("is_hidden", value: false).single().execute().value
        if let found { listings.append(found) }
        return found
    }

    private struct StatsIDs: Encodable { let p_ids: [UUID] }

    func reviewerStats(for ids: [UUID]) async -> [ReviewerStats] {
        guard !ids.isEmpty else { return [] }
        return (try? await supabase.rpc("reviewer_stats", params: StatsIDs(p_ids: ids)).execute().value) ?? []
    }

    /// Fire-and-forget click count. Never blocks opening the site.
    func recordClick(_ listing: Listing) {
        recordEvent(listing, .visit)
    }

    /// Impressions and page views are sent once per listing per app session. The server also
    /// keeps one per device per day, so the numbers are unique devices, not raw taps.
    private var sentEvents = Set<String>()

    func recordEvent(_ listing: Listing, _ kind: EventKind) {
        if kind != .visit, !sentEvents.insert("\(listing.id)-\(kind.rawValue)").inserted { return }
        let params = RecordEventParams(p_listing: listing.id, p_kind: kind.rawValue, p_device: DeviceID.current)
        Task {
            _ = try? await supabase.rpc("record_event", params: params).execute()
        }
    }

    /// `owner: true` is the private version (impressions, sponsorship results). Otherwise it's the public one.
    func stats(for listing: Listing, days: Int, owner: Bool) async throws -> ListingStats {
        try await supabase
            .rpc(owner ? "listing_stats" : "public_listing_stats",
                 params: StatsParams(p_listing: listing.id, p_days: days))
            .execute()
            .value
    }

    func submit(_ listing: NewListing) async throws {
        try await supabase.from("listings").insert(listing).execute()
        await load()
    }

    enum StoreError: LocalizedError {
        case notAllowed
        var errorDescription: String? {
            "That didn't go through. The listing may have been removed, or it isn't yours."
        }
    }

    /// Edits one of your own listings. Asks for the changed row back, because a blocked
    /// update otherwise "succeeds" while changing nothing.
    func update(_ id: UUID, with edit: ListingEdit) async throws {
        let rows: [Listing] = try await supabase
            .from("listings")
            .update(edit)
            .eq("id", value: id)
            .select()
            .execute()
            .value
        if rows.isEmpty { throw StoreError.notAllowed }
        await load()
    }

    func delete(_ listing: Listing) async throws {
        let rows: [Listing] = try await supabase
            .from("listings")
            .delete()
            .eq("id", value: listing.id)
            .select()
            .execute()
            .value
        if rows.isEmpty { throw StoreError.notAllowed }
        await load()
    }

    /// The code the advertiser puts on their site. Created on first ask, kept until the URL changes.
    func verifyToken(for listing: Listing) async throws -> String {
        try await supabase
            .rpc("get_verify_token", params: ["p_listing": listing.id.uuidString])
            .execute()
            .value
    }

    struct VerifyResult: Decodable { let verified: Bool?; let error: String? }

    /// Asks the server to look for the code on the site. Returns nil on success, or a message to show.
    func verifySite(_ listing: Listing) async -> String? {
        do {
            let token = try await supabase.auth.session.accessToken
            let result: VerifyResult = try await supabase.functions.invoke(
                "verify-site",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(token)"],
                    body: ["listing_id": listing.id.uuidString]
                )
            )
            if result.verified == true { await load(); return nil }
            return result.error ?? "Couldn't verify yet."
        } catch FunctionsError.httpError(_, let data) {
            return (try? JSONDecoder().decode(VerifyResult.self, from: data))?.error ?? "Couldn't verify. Try again."
        } catch {
            return error.localizedDescription
        }
    }

    struct ServerError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private struct ServerMessage: Decodable { let error: String? }

    /// Deletes the account on the server (listings and reviews go with it), then signs out here.
    /// The server checks the code that was emailed, so a stolen session alone can't delete an account.
    func deleteAccount(code: String) async throws {
        let token = try await supabase.auth.session.accessToken
        do {
            try await supabase.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(token)"],
                    body: ["code": code]
                )
            )
        } catch FunctionsError.httpError(_, let data) {
            let text = (try? JSONDecoder().decode(ServerMessage.self, from: data))?.error
            throw ServerError(message: text ?? "Couldn't delete the account.")
        }
        try? await supabase.auth.signOut(scope: .local)
        await load()
    }

    // MARK: Featured (earned, not bought)

    enum FeaturedRules {
        static let maxCount = 6        // how many listings can be Featured at once
        static let minReviews = 1      // needs at least this many reviews...
        static let minRating = 4.0     // ...averaging at least this, OR...
        static let minClicks = 10      // ...at least this many visits
    }

    private func computeFeatured() -> [UUID] {
        let maxClicks = listings.map(\.clicks).max() ?? 0
        return listings
            .filter { !$0.isSponsored }
            .filter { l in
                (l.reviewCount >= FeaturedRules.minReviews && l.ratingValue >= FeaturedRules.minRating)
                || l.clicks >= FeaturedRules.minClicks
            }
            .sorted { $0.featuredScore(maxClicks: maxClicks) > $1.featuredScore(maxClicks: maxClicks) }
            .prefix(FeaturedRules.maxCount)
            .map(\.id)
    }

    // MARK: Reviews

    /// Viewers have no accounts. To review, they get a silent anonymous session,
    /// which gives each device one identity so it can only leave one review per listing.
    func ensureViewerSession() async throws {
        if (try? await supabase.auth.session) == nil {
            try await supabase.auth.signInAnonymously()
        }
    }

    func currentUserID() async -> UUID? {
        try? await supabase.auth.session.user.id
    }

    func reviews(for listingID: UUID) async throws -> [Review] {
        try await supabase
            .from("reviews")
            .select("*, review_replies(body, created_at)")
            .eq("listing_id", value: listingID)
            .eq("is_hidden", value: false)
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    /// Creates the review, or edits yours if you already left one.
    func saveReview(listingID: UUID, stars: Int, comment: String?) async throws {
        try await ensureViewerSession()
        let trimmed = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        let review = NewReview(listingId: listingID,
                               stars: stars,
                               comment: (trimmed?.isEmpty ?? true) ? nil : trimmed)
        try await supabase
            .from("reviews")
            .upsert(review, onConflict: "listing_id,user_id")
            .execute()
        await load()   // refreshes avg_rating / rating_count
    }

    // MARK: Replies, helpful votes

    func saveReply(to review: Review, on listing: Listing, body: String) async throws {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        try await supabase.from("review_replies")
            .upsert(NewReply(reviewId: review.id, listingId: listing.id, body: text), onConflict: "review_id")
            .execute()
    }

    func deleteReply(to review: Review) async throws {
        try await supabase.from("review_replies").delete().eq("review_id", value: review.id).execute()
    }

    /// Which of these reviews this device's session already marked helpful.
    func myHelpfulVotes(for reviewIDs: [UUID]) async -> Set<UUID> {
        guard !reviewIDs.isEmpty, await currentUserID() != nil else { return [] }
        let rows: [VoteRow] = (try? await supabase.from("review_votes")
            .select("review_id")
            .in("review_id", values: reviewIDs.map(\.uuidString))
            .execute().value) ?? []
        return Set(rows.map(\.reviewId))
    }

    func setHelpful(_ review: Review, on: Bool) async throws {
        try await ensureViewerSession()
        if on {
            try await supabase.from("review_votes").insert(NewVote(reviewId: review.id)).execute()
        } else if let me = await currentUserID() {
            try await supabase.from("review_votes").delete()
                .eq("review_id", value: review.id).eq("user_id", value: me).execute()
        }
    }

    // MARK: Sponsorship slots

    func availability(from start: Date, days: Int = 40) async -> [SlotDay] {
        (try? await supabase
            .rpc("sponsor_availability", params: AvailabilityParams(p_start: StatsDates.string(start), p_days: days))
            .execute().value) ?? []
    }

    /// Holds a slot before the person pays. Throws a readable message if it's sold out.
    func reserveSlot(for listing: Listing, start: Date, days: Int) async throws -> SlotReservation {
        try await supabase
            .rpc("reserve_slot", params: ReserveParams(p_listing: listing.id, p_start: StatsDates.string(start), p_days: days))
            .execute().value
    }

    func deleteReview(_ review: Review) async throws {
        try await supabase.from("reviews").delete().eq("id", value: review.id).execute()
        await load()
    }

    // MARK: Reports

    func report(listing: Listing, review: Review? = nil, reason: String, note: String?) async throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let report = NewReport(listingId: listing.id,
                               reviewId: review?.id,
                               reason: reason,
                               note: (trimmed?.isEmpty ?? true) ? nil : trimmed)
        try await supabase.from("reports").insert(report).execute()
    }
}
