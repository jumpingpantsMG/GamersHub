import SwiftUI
import Supabase

// MARK: Numbers from the server -> XP, level, badges

struct ReviewerStats: Decodable {
    let userId: UUID
    let reviews: Int
    let helpful: Int
    let categories: Int

    enum CodingKeys: String, CodingKey {
        case reviews, helpful, categories
        case userId = "user_id"
    }

    static func empty(_ id: UUID) -> ReviewerStats { ReviewerStats(userId: id, reviews: 0, helpful: 0, categories: 0) }

    /// 10 per review, 5 per "helpful" you received, 5 per different category you've reviewed.
    var xp: Int { reviews * 10 + helpful * 5 + categories * 5 }

    static let maxLevel = 20
    static func xpNeeded(forLevel n: Int) -> Int { 25 * (n - 1) * (n - 1) }

    var level: Int { min(Self.maxLevel, Int((Double(xp) / 25).squareRoot()) + 1) }
    var isMaxLevel: Bool { level >= Self.maxLevel }

    /// 0...1 toward the next level.
    var progress: Double {
        if isMaxLevel { return 1 }
        let lo = Self.xpNeeded(forLevel: level), hi = Self.xpNeeded(forLevel: level + 1)
        return Double(xp - lo) / Double(hi - lo)
    }
    var xpToNext: Int { isMaxLevel ? 0 : Self.xpNeeded(forLevel: level + 1) - xp }

    var title: String {
        switch level {
        case ...2: return "Rookie"
        case 3...4: return "Scout"
        case 5...7: return "Veteran"
        case 8...11: return "Elite"
        default: return "Legend"
        }
    }

    struct Badge: Identifiable {
        let id: String
        let name: String
        let detail: String
        let symbol: String
        let earned: Bool
    }

    var badges: [Badge] {
        [
            Badge(id: "first", name: "First blood", detail: "Write your first review", symbol: "flag.checkered", earned: reviews >= 1),
            Badge(id: "critic", name: "Critic", detail: "Write 10 reviews", symbol: "text.bubble.fill", earned: reviews >= 10),
            Badge(id: "explorer", name: "Explorer", detail: "Review 4 different categories", symbol: "map.fill", earned: categories >= 4),
            Badge(id: "helper", name: "Helping hand", detail: "Get 5 helpful votes", symbol: "hand.thumbsup.fill", earned: helpful >= 5),
            Badge(id: "trusted", name: "Trusted voice", detail: "Get 25 helpful votes", symbol: "checkmark.seal.fill", earned: helpful >= 25),
            Badge(id: "veteran", name: "Veteran", detail: "Reach level 5", symbol: "shield.lefthalf.filled", earned: level >= 5),
        ]
    }
}

/// Small "Lv 3" tag shown next to reviewers.
struct LevelChip: View {
    let level: Int
    var body: some View {
        Label("Lv \(level)", systemImage: "bolt.fill")
            .font(.caption2.bold())
            .foregroundStyle(.yellow)
            .help("Reviewer level")
    }
}

// MARK: Profile screen

struct ReviewerProfileView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let store: ListingsStore

    @State private var stats: ReviewerStats?
    @State private var loading = true
    @State private var viewerOnly = true   // no account yet, so progress only lives on this device
    @State private var showAuth = false

    private var s: ReviewerStats { stats ?? .empty(UUID()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    levelRing

                    HStack(spacing: 10) {
                        tile("Reviews", "\(s.reviews)")
                        tile("Helpful votes", "\(s.helpful)")
                        tile("Categories", "\(s.categories)")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(theme.heading("Badges")).font(theme.title(.headline))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                            ForEach(s.badges) { b in badge(b) }
                        }
                    }

                    if viewerOnly {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Save your progress", systemImage: "icloud.and.arrow.up")
                                .font(.headline)
                            Text("Right now your level only lives on this device. Create an account or sign in and everything you've earned moves into it, and follows you to any device.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Sign in or create account") { showAuth = true }
                                .buttonStyle(GlowButtonStyle())
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface(radius: 14)
                    }

                    Text("Earn XP by writing reviews (10 each), getting helpful votes (5 each), and reviewing different categories (5 each). \(viewerOnly ? "Your progress is tied to this device until you sign in." : "Your progress is saved to your account.")")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(ThemedBackground())
            .navigationTitle("Reviewer profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
            .sheet(isPresented: $showAuth, onDismiss: { Task { await load() } }) {
                AuthGate { AccountReadyView() }
            }
            .refreshable { await Task { await load() }.value }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 620)
        #endif
    }

    private var levelRing: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: s.progress)
                    .stroke(theme.accentFill, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .themeGlow(theme.accent, radius: 8)
                    .animation(.spring(duration: 0.8), value: s.progress)
                VStack(spacing: 0) {
                    Text("LEVEL").font(.caption2.bold()).foregroundStyle(.secondary)
                    Text("\(s.level)").font(.system(size: 52, weight: .heavy, design: theme.design))
                }
            }
            .frame(width: 150, height: 150)

            Text(theme.heading(s.title)).font(theme.title(.title2)).tracking(theme.tracking)
            if loading && stats == nil {
                ProgressView()
            } else if s.isMaxLevel {
                Text("\(s.xp) XP. Max level!").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("\(s.xp) XP. \(s.xpToNext) to level \(s.level + 1)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardSurface(radius: 14)
    }

    private func badge(_ b: ReviewerStats.Badge) -> some View {
        HStack(spacing: 10) {
            Image(systemName: b.earned ? b.symbol : "lock.fill")
                .font(.title3)
                .foregroundStyle(b.earned ? theme.accent2 : .secondary)
                .frame(width: 28)
                .themeGlow(b.earned ? theme.accent2 : .clear, radius: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(b.name).font(.subheadline.weight(.semibold))
                Text(b.detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 14)
        .opacity(b.earned ? 1 : 0.55)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let session = try? await supabase.auth.session
        viewerOnly = session?.user.isAnonymous ?? true
        guard let me = await store.currentUserID() else { stats = .empty(UUID()); return }
        stats = await store.reviewerStats(for: [me]).first ?? .empty(me)
    }
}

/// Shown after signing in from the reviewer profile.
private struct AccountReadyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text("You're signed in").font(.title3.bold())
            Text("Your progress is now saved to your account.").foregroundStyle(.secondary)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding(40)
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 260)
        #endif
    }
}
