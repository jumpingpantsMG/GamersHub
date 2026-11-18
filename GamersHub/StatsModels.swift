import SwiftUI

/// A random ID that lives on this device. It's how "once per device per day" works,
/// without accounts. It isn't tied to a person.
enum DeviceID {
    static let current: UUID = {
        let key = "deviceID.v1"
        if let s = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: s) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }()
}

enum EventKind: String {
    case impression   // a Sponsored card was on screen
    case view         // the detail page was opened
    case visit        // Visit was tapped
}

struct RecordEventParams: Encodable {
    let p_listing: UUID
    let p_kind: String
    let p_device: UUID
}

struct StatsParams: Encodable {
    let p_listing: UUID
    let p_days: Int
}

// MARK: Stats returned by the server (property names match the JSON keys)

struct DayStat: Decodable, Identifiable {
    let day: String
    let impressions: Int
    let views: Int
    let visits: Int
    var id: String { day }
    var date: Date { StatsDates.parse(day) }
}

struct ReviewDayStat: Decodable, Identifiable {
    let day: String
    let count: Int
    let avg: Double?
    var id: String { day }
    var date: Date { StatsDates.parse(day) }
}

struct SponsorshipStat: Decodable, Identifiable {
    let startsAt: String
    let endsAt: String
    let days: Int
    let active: Bool
    let impressions: Int
    let views: Int
    let visits: Int
    var id: String { startsAt + endsAt }

    /// Of the people who saw the card, how many tapped Visit. Nil if nobody saw it yet.
    var visitRate: Double? { impressions > 0 ? Double(visits) / Double(impressions) : nil }
}

struct StatTotals: Decodable {
    let impressions: Int
    let views: Int
    let visits: Int
}

struct ListingStats: Decodable {
    let daily: [DayStat]
    let reviews: [ReviewDayStat]
    let sponsorships: [SponsorshipStat]
    let totals: StatTotals
}

enum StatsDates {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = TimeZone(identifier: "UTC")   // days are UTC days, so don't shift them into local time
        return f
    }()
    static func parse(_ s: String) -> Date { formatter.date(from: s) ?? .distantPast }
    static func string(_ d: Date) -> String { formatter.string(from: d) }
    static func addingDays(_ n: Int, to d: Date) -> Date { d.addingTimeInterval(Double(n) * 86_400) }
    static func pretty(_ s: String) -> String { short.string(from: parse(s)) }
}

// MARK: "Seen" detection for cards

extension View {
    /// Runs once a card is mostly on screen. On older systems it falls back to onAppear.
    @ViewBuilder
    func onSeen(_ perform: @escaping () -> Void) -> some View {
        if #available(iOS 18, macOS 15, *) {
            self.onScrollVisibilityChange(threshold: 0.6) { visible in
                if visible { perform() }
            }
        } else {
            self.onAppear(perform: perform)
        }
    }
}
