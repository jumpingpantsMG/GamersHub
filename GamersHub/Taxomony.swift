//
//  Taxomony.swift
//  GamersHub
//
//  Created by Jaiden Kumar on 14/11/26.
//

import SwiftUI

/// The fixed lists advertisers pick from. The ids must match the database constraints in phase4.sql.
struct Option: Identifiable, Hashable {
    let id: String
    let label: String
    let symbol: String
}

enum Taxonomy {
    static let pricing: [Option] = [
        Option(id: "free", label: "Free", symbol: "gift"),
        Option(id: "paid", label: "Paid", symbol: "dollarsign.circle"),
        Option(id: "free_with_purchases", label: "Free + purchases", symbol: "cart"),
    ]

    static let platforms: [Option] = [
        Option(id: "browser", label: "Browser", symbol: "safari"),
        Option(id: "ios", label: "iPhone / iPad", symbol: "iphone"),
        Option(id: "android", label: "Android", symbol: "iphone.gen3"),
        Option(id: "windows", label: "Windows", symbol: "desktopcomputer"),
        Option(id: "mac", label: "Mac", symbol: "laptopcomputer"),
        Option(id: "linux", label: "Linux", symbol: "terminal"),
        Option(id: "console", label: "Console", symbol: "gamecontroller"),
    ]

    static let tags: [Option] = [
        Option(id: "multiplayer", label: "Multiplayer", symbol: "person.2"),
        Option(id: "singleplayer", label: "Single player", symbol: "person"),
        Option(id: "co_op", label: "Co-op", symbol: "person.3"),
        Option(id: "mobile_friendly", label: "Mobile friendly", symbol: "iphone"),
        Option(id: "controller_support", label: "Controller support", symbol: "gamecontroller"),
        Option(id: "no_signup", label: "No sign-up", symbol: "bolt"),
    ]

    static func label(_ id: String, in list: [Option]) -> String? {
        list.first { $0.id == id }?.label
    }
}

/// Feed filters. Pricing is exact, platforms match any selected, tags must all match.
struct FeedFilters: Equatable {
    var pricing: String?
    var platforms: Set<String> = []
    var tags: Set<String> = []

    var isActive: Bool { pricing != nil || !platforms.isEmpty || !tags.isEmpty }

    func matches(_ l: Listing) -> Bool {
        if let pricing, l.pricing != pricing { return false }
        if !platforms.isEmpty && platforms.isDisjoint(with: l.platformList) { return false }
        if !tags.isSubset(of: Set(l.tagList)) { return false }
        return true
    }
}

/// Wide-to-narrow labels for a listing's pricing, platforms and tags, in display order.
func listingBadges(_ l: Listing) -> [String] {
    var out: [String] = []
    if let p = l.pricing, let name = Taxonomy.label(p, in: Taxonomy.pricing) { out.append(name) }
    out += l.platformList.compactMap { Taxonomy.label($0, in: Taxonomy.platforms) }
    out += l.tagList.compactMap { Taxonomy.label($0, in: Taxonomy.tags) }
    return out
}

// MARK: Sponsorship slots

struct SlotDay: Decodable {
    let day: String
    let used: Int
    let cap: Int
    var isFull: Bool { used >= cap }
}

struct SlotReservation: Decodable {
    let reservationId: UUID
    let startsAt: String
    let endsAt: String
}

struct AvailabilityParams: Encodable { let p_start: String; let p_days: Int }
struct ReserveParams: Encodable { let p_listing: UUID; let p_start: String; let p_days: Int }

// MARK: Replies and votes

struct ReviewReply: Codable, Hashable {
    let body: String
    let createdAt: Date?
    enum CodingKeys: String, CodingKey { case body; case createdAt = "created_at" }
}

struct NewReply: Encodable {
    let reviewId: UUID
    let listingId: UUID
    let body: String
    enum CodingKeys: String, CodingKey { case body; case reviewId = "review_id"; case listingId = "listing_id" }
}

struct NewVote: Encodable {
    let reviewId: UUID
    enum CodingKeys: String, CodingKey { case reviewId = "review_id" }
}

struct VoteRow: Decodable {
    let reviewId: UUID
    enum CodingKeys: String, CodingKey { case reviewId = "review_id" }
}
