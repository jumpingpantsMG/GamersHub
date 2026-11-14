import SwiftUI

// MARK: Category look

struct CategoryStyle {
    let symbol: String
    let color: Color

    static func of(_ category: String) -> CategoryStyle {
        switch category {
        case "Action":      return CategoryStyle(symbol: "bolt.fill", color: .red)
        case "Puzzle":      return CategoryStyle(symbol: "puzzlepiece.fill", color: .purple)
        case "Strategy":    return CategoryStyle(symbol: "crown.fill", color: .orange)
        case "Racing":      return CategoryStyle(symbol: "flag.checkered", color: .blue)
        case "Sports":      return CategoryStyle(symbol: "sportscourt.fill", color: .green)
        case "Multiplayer": return CategoryStyle(symbol: "person.3.fill", color: .teal)
        case "Casual":      return CategoryStyle(symbol: "leaf.fill", color: .mint)
        default:            return CategoryStyle(symbol: "gamecontroller.fill", color: .gray)
        }
    }
}

struct CategoryIcon: View {
    @Environment(\.theme) private var theme
    let category: String
    var size: CGFloat = 48

    var body: some View {
        let style = CategoryStyle.of(category)
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        shape
            .fill(LinearGradient(colors: [style.color.opacity(0.95), style.color.opacity(0.5)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .themeGlow(style.color, radius: 8)
    }
}

/// Big abstract cover art for a listing, built from its category color and symbol.
struct ListingArt: View {
    @Environment(\.theme) private var theme
    let category: String
    var imageURL: String? = nil

    var body: some View {
        let style = CategoryStyle.of(category)
        ZStack {
            LinearGradient(colors: [style.color.opacity(0.95), style.color.opacity(0.35), theme.background],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(theme.accent2.opacity(theme.glow ? 0.4 : 0.2))
                .frame(width: 240, height: 240)
                .blur(radius: 50)
                .offset(x: 120, y: -70)
            Image(systemName: style.symbol)
                .font(.system(size: 180, weight: .black))
                .foregroundStyle(.white.opacity(0.14))
                .rotationEffect(.degrees(-14))
                .offset(x: 95, y: 25)
        }
        .overlay { coverImage }
        .clipped()
    }

    /// The advertiser's image, if any. The generated art shows while it loads or if it fails.
    @ViewBuilder
    private var coverImage: some View {
        if let s = imageURL, let url = URL(string: s) {
            ZStack {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.35))) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    }
                }
                LinearGradient(colors: [theme.accent.opacity(theme.glow ? 0.28 : 0.1), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

/// Small square image for list cards: the listing's image, or its category icon.
struct ListingThumb: View {
    let listing: Listing
    var size: CGFloat = 54

    var body: some View {
        if let s = listing.imageURL, let url = URL(string: s) {
            let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.3))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    CategoryIcon(category: listing.category, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
        } else {
            CategoryIcon(category: listing.category, size: size)
        }
    }
}

// MARK: Ratings

struct StarsView: View {
    let rating: Double
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: symbol(for: i))
                    .font(.system(size: size))
                    .foregroundStyle(.yellow)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(String(format: "%.1f", rating)) out of 5 stars")
    }

    private func symbol(for i: Int) -> String {
        let v = rating - Double(i - 1)
        if v >= 0.75 { return "star.fill" }
        if v >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct RatingSummary: View {
    let listing: Listing
    var size: CGFloat = 12

    var body: some View {
        if listing.reviewCount == 0 {
            Text("No ratings yet").font(.caption).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                StarsView(rating: listing.ratingValue, size: size)
                Text(String(format: "%.1f", listing.ratingValue)).font(.caption.bold())
                Text("(\(listing.reviewCount))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct StarPicker: View {
    @Binding var stars: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= stars ? "star.fill" : "star")
                    .font(.title)
                    .foregroundStyle(.yellow)
                    .scaleEffect(i <= stars ? 1.1 : 1)
                    .animation(.spring(duration: 0.25), value: stars)
                    .onTapGesture { stars = i }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue("\(stars) of 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: stars = min(5, stars + 1)
            case .decrement: stars = max(1, stars - 1)
            @unknown default: break
            }
        }
    }
}

/// 5-to-1 star bars, built from the loaded reviews.
struct RatingHistogram: View {
    @Environment(\.theme) private var theme
    let reviews: [Review]

    var body: some View {
        let total = max(reviews.count, 1)
        VStack(spacing: 5) {
            ForEach((1...5).reversed(), id: \.self) { star in
                let n = reviews.filter { $0.stars == star }.count
                HStack(spacing: 6) {
                    Text("\(star)").font(.caption.monospacedDigit()).frame(width: 10)
                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1))
                            Capsule().fill(theme.accentFill)
                                .frame(width: g.size.width * CGFloat(n) / CGFloat(total))
                        }
                    }
                    .frame(height: 6)
                    Text("\(n)").font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
        .animation(.spring(duration: 0.5), value: reviews.count)
    }
}

// MARK: Rank tiers

enum Rank {
    case bronze, silver, gold, diamond

    var title: String {
        switch self {
        case .bronze:  return "BRONZE"
        case .silver:  return "SILVER"
        case .gold:    return "GOLD"
        case .diamond: return "DIAMOND"
        }
    }

    var symbol: String {
        switch self {
        case .bronze, .silver: return "shield.fill"
        case .gold:            return "trophy.fill"
        case .diamond:         return "diamond.fill"
        }
    }

    var color: Color {
        switch self {
        case .bronze:  return Color(hex: 0xCD7F32)
        case .silver:  return Color(hex: 0xC0C7D1)
        case .gold:    return Color(hex: 0xFFC83D)
        case .diamond: return Color(hex: 0x67E8F9)
        }
    }
}

extension Listing {
    /// Needs both a high average and enough reviews to count.
    var rank: Rank? {
        let r = ratingValue, n = reviewCount
        if r >= 4.8 && n >= 10 { return .diamond }
        if r >= 4.5 && n >= 5  { return .gold }
        if r >= 4.0 && n >= 3  { return .silver }
        if r >= 3.0 && n >= 1  { return .bronze }
        return nil
    }
}

struct RankBadge: View {
    let rank: Rank

    var body: some View {
        Label(rank.title, systemImage: rank.symbol)
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(rank.color.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(rank.color.opacity(0.7), lineWidth: 1))
            .foregroundStyle(rank.color)
            .themeGlow(rank.color, radius: 5)
    }
}

// MARK: Badges

struct AgeBadge: View {
    let rating: Int
    var body: some View {
        Text("\(rating)+")
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((rating >= 17 ? Color.red : Color.secondary).opacity(0.3), in: Capsule())
    }
}

struct VerifiedBadge: View {
    var body: some View {
        Label("Verified", systemImage: "checkmark.seal.fill")
            .font(.caption2.bold())
            .foregroundStyle(.green)
            .help("The advertiser proved they own this site")
    }
}

struct Chip: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((theme.glow ? theme.accent2 : Color.white).opacity(0.14), in: Capsule())
            .foregroundStyle(theme.glow ? theme.accent2 : Color.white.opacity(0.8))
    }
}

// MARK: Loading placeholder

struct SkeletonCard: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14).frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 150, height: 14)
                    RoundedRectangle(cornerRadius: 4).frame(width: 100, height: 10)
                }
            }
            RoundedRectangle(cornerRadius: 4).frame(height: 10)
            RoundedRectangle(cornerRadius: 4).frame(width: 220, height: 10)
        }
        .foregroundStyle(.white.opacity(pulse ? 0.08 : 0.2))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
