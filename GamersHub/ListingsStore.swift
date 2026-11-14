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
        } catch is CancellationError {
            // refresh gesture ended early, not an error
        } catch let e as URLError where e.code == .cancelled {
            // same thing from the network layer
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fire-and-forget click count. Never blocks opening the site.
    func recordClick(_ listing: Listing) {
        Task {
            _ = try? await supabase
                .rpc("increment_click", params: ["listing": listing.id.uuidString])
                .execute()
        }
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

    /// Deletes the account on the server (listings and reviews go with it), then signs out here.
    func deleteAccount() async throws {
        let token = try await supabase.auth.session.accessToken
        try await supabase.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(headers: ["Authorization": "Bearer \(token)"])
        )
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
            .select()
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
