import Foundation

struct Listing: Identifiable, Codable, Hashable {
    let id: UUID
    let ownerId: UUID?
    let title: String
    let description: String
    let url: String
    let imageURL: String?
    let category: String
    let ageRating: Int
    let sponsoredUntil: Date?      // paid placement; set by the server after a verified purchase
    let createdAt: Date
    let avgRating: Double?
    let ratingCount: Int?
    let clickCount: Int?
    var isVerified: Bool? = nil    // set by the server once the advertiser proves they own the site

    var verified: Bool { isVerified ?? false }

    /// Paid placement. Shown as "Sponsored".
    var isSponsored: Bool { (sponsoredUntil ?? .distantPast) > Date() }
    var ratingValue: Double { avgRating ?? 0 }
    var reviewCount: Int { ratingCount ?? 0 }
    var clicks: Int { clickCount ?? 0 }

    /// Weighted so one 5-star review doesn't beat fifty 4.8-star reviews.
    var rankScore: Double {
        (ratingValue * Double(reviewCount) + 3.0 * 3.0) / Double(reviewCount + 3)
    }

    /// 0...1. Mostly rating quality, partly visits. Visits are log-scaled against the
    /// most-visited listing so one huge site doesn't flatten everyone else.
    func featuredScore(maxClicks: Int) -> Double {
        let rating = rankScore / 5.0
        let visits = log(1 + Double(clicks)) / log(1 + Double(max(maxClicks, 1)))
        return 0.6 * rating + 0.4 * visits
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, url, category
        case ownerId = "owner_id"
        case imageURL = "image_url"
        case ageRating = "age_rating"
        case sponsoredUntil = "sponsored_until"
        case createdAt = "created_at"
        case avgRating = "avg_rating"
        case ratingCount = "rating_count"
        case clickCount = "click_count"
        case isVerified = "is_verified"
    }
}

/// What an advertiser sends. owner_id is filled in by the database (auth.uid()).
struct NewListing: Encodable {
    let title: String
    let description: String
    let url: String
    let imageURL: String?
    let category: String
    let ageRating: Int

    enum CodingKeys: String, CodingKey {
        case title, description, url, category
        case imageURL = "image_url"
        case ageRating = "age_rating"
    }
}

/// What an advertiser sends when editing. The image is always sent, as null when cleared,
/// so removing the image actually removes it.
struct ListingEdit: Encodable {
    let title: String
    let description: String
    let url: String
    let imageURL: String?
    let category: String
    let ageRating: Int

    enum CodingKeys: String, CodingKey {
        case title, description, url, category
        case imageURL = "image_url"
        case ageRating = "age_rating"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(url, forKey: .url)
        try c.encode(imageURL, forKey: .imageURL)
        try c.encode(category, forKey: .category)
        try c.encode(ageRating, forKey: .ageRating)
    }
}

struct Review: Identifiable, Codable, Hashable {
    let id: UUID
    let listingId: UUID
    let userId: UUID
    let stars: Int
    let comment: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, stars, comment
        case listingId = "listing_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

/// user_id is filled in by the database (auth.uid()).
struct NewReview: Encodable {
    let listingId: UUID
    let stars: Int
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case stars, comment
        case listingId = "listing_id"
    }

    // Encode comment as an explicit null so editing a review can clear its text.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(listingId, forKey: .listingId)
        try c.encode(stars, forKey: .stars)
        try c.encode(comment, forKey: .comment)
    }
}

struct NewReport: Encodable {
    let listingId: UUID
    let reviewId: UUID?
    let reason: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case reason, note
        case listingId = "listing_id"
        case reviewId = "review_id"
    }
}

enum AgeRating: Int, CaseIterable, Identifiable {
    case everyone = 4, kids = 9, teen = 12, mature = 17
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .everyone: return "4+ (Everyone)"
        case .kids:     return "9+"
        case .teen:     return "12+"
        case .mature:   return "17+ (Mature)"
        }
    }
}

enum ListingCategory {
    static let all = ["Action", "Puzzle", "Strategy", "Racing", "Sports",
                      "Multiplayer", "Casual", "Other"]
}
