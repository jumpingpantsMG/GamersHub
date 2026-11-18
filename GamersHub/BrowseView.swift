import SwiftUI
import Supabase

enum FeedSort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case topRated = "Top rated"
    var id: String { rawValue }
}

/// Sponsored = paid placement. Featured = earned from ratings and visits.
enum HeroKind {
    case sponsored, featured, trending, new

    var label: String {
        switch self {
        case .sponsored: "Sponsored"
        case .featured: "Featured"
        case .trending: "Trending"
        case .new: "New"
        }
    }
    var symbol: String {
        switch self {
        case .sponsored: "megaphone.fill"
        case .featured: "flame.fill"
        case .trending: "chart.line.uptrend.xyaxis"
        case .new: "sparkles"
        }
    }
}

struct BrowseView: View {
    @AppStorage("soundOn") private var soundOn = true

    @State private var themes = ThemeManager()
    @State private var hidden = HiddenStore()
    @State private var saved = SavedStore()
    @State private var savedOnly = false
    @State private var showProfile = false
    @State private var showNewPassword = false
    @State private var router = DeepLinkRouter.shared
    @State private var store = ListingsStore()
    @State private var search = ""
    @State private var category: String?
    @State private var sort: FeedSort = .newest
    @State private var filters = FeedFilters()
    @State private var selected: Listing?
    @State private var reporting: Listing?
    @State private var pendingAdult: Listing?
    @State private var showSubmit = false
    @State private var showStudio = false
    @State private var showHidden = false
    @State private var tapTick = 0
    @Namespace private var zoomNS
    @Environment(\.openURL) private var openURL

    private var theme: Theme { themes.spec.resolved }

    private var filtered: [Listing] {
        let base = store.listings.filter { l in
            !hidden.isHidden(l)
            && filters.matches(l)
            && (!savedOnly || saved.isSaved(l))
            && (category == nil || l.category == category)
            && (search.isEmpty
                || l.title.localizedCaseInsensitiveContains(search)
                || l.description.localizedCaseInsensitiveContains(search))
        }
        switch sort {
        case .newest:   return base   // the store already returns newest first
        case .topRated: return base.sorted { $0.rankScore > $1.rankScore }
        }
    }

    /// Paid. Big spotlight cards.
    private var sponsored: [Listing] { filtered.filter(\.isSponsored) }

    /// Earned. Kept in score order. Never includes sponsored listings.
    private var featuredRow: [Listing] {
        store.featuredIDs.compactMap { id in filtered.first { $0.id == id } }
    }

    /// Busy lately. Skips anything already shown above.
    private var trendingRow: [Listing] {
        guard !savedOnly else { return [] }
        let skip = Set(sponsored.map(\.id) + featuredRow.map(\.id))
        let rows = store.trendingIDs.compactMap { id in filtered.first { $0.id == id } }
            .filter { !skip.contains($0.id) }
        return Array(rows.prefix(8))
    }

    /// Added in the last 7 days. Only shown when the main list keeps at least 3 sites, so it never empties it.
    private var newRow: [Listing] {
        guard !savedOnly, search.isEmpty else { return [] }
        let skip = Set((sponsored + featuredRow + trendingRow).map(\.id))
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let candidates = Array(filtered.filter { $0.createdAt > cutoff && !skip.contains($0.id) }.prefix(8))
        let remaining = filtered.count - skip.count - candidates.count
        return remaining >= 3 ? candidates : []
    }

    /// Everything else. A listing only ever appears in one section.
    private var regular: [Listing] {
        let skip = Set((sponsored + featuredRow + trendingRow + newRow).map(\.id))
        return filtered.filter { !skip.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    Section {
                        if !sponsored.isEmpty {
                            sectionHeader("Sponsored", systemImage: "megaphone.fill", tint: theme.accent2,
                                          subtitle: "Paid placement")
                            heroCarousel(sponsored, kind: .sponsored)
                        }

                        if !featuredRow.isEmpty {
                            sectionHeader("Featured", systemImage: "flame.fill", tint: .orange,
                                          subtitle: "Top rated and most visited")
                            heroCarousel(featuredRow, kind: .featured)
                        }

                        if !trendingRow.isEmpty {
                            sectionHeader("Trending", systemImage: "chart.line.uptrend.xyaxis", tint: .pink,
                                          subtitle: "Most visited this week")
                            heroCarousel(trendingRow, kind: .trending)
                        }

                        if !newRow.isEmpty {
                            sectionHeader("New this week", systemImage: "sparkles", tint: .green,
                                          subtitle: "Just added")
                            heroCarousel(newRow, kind: .new)
                        }

                        sectionHeader(sort == .topRated ? "Top rated" : "All sites",
                                      systemImage: sort == .topRated ? "trophy.fill" : "gamecontroller.fill",
                                      tint: theme.accent2, subtitle: nil)

                        // One column on a phone, 2-4 on iPad and Mac depending on window width.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 560),
                                                     spacing: 16, alignment: .top)],
                                  spacing: 16) {
                            ForEach(regular) { l in
                                ListingCard(listing: l,
                                            onOpen: { open(detail: l) },
                                            onVisit: { visit(l) },
                                            onReport: { reporting = l })
                                    .zoomSource(l.id, in: zoomNS)
                                    .scrollTransition(.animated) { content, phase in
                                        content
                                            .opacity(phase.isIdentity ? 1 : 0.4)
                                            .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                    }
                            }
                        }
                        .padding(.horizontal)

                        statusViews
                    } header: {
                        categoryBar
                    }
                }
                .frame(maxWidth: 1400)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .background(ThemedBackground())
            .navigationTitle("GamersHub")
            .searchable(text: $search, prompt: "Search games and sites")
            .refreshable { await Task { await store.load() }.value }  // own task, so the pull gesture can't cancel the request
            .task {
                await store.load()
                await openDeepLink()
            }
            .onChange(of: router.listingID) { Task { await openDeepLink() } }
            .onChange(of: router.showNewPassword) {
                guard router.showNewPassword else { return }
                router.showNewPassword = false
                showSubmit = false
                showNewPassword = true
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Picker("Pricing", selection: $filters.pricing) {
                            Text("Any price").tag(String?.none)
                            ForEach(Taxonomy.pricing) { Text($0.label).tag(String?.some($0.id)) }
                        }
                        Menu("Platform") {
                            ForEach(Taxonomy.platforms) { o in
                                Toggle(o.label, isOn: filterFlag(\.platforms, o.id))
                            }
                        }
                        Menu("Features") {
                            ForEach(Taxonomy.tags) { o in
                                Toggle(o.label, isOn: filterFlag(\.tags, o.id))
                            }
                        }
                        if filters.isActive {
                            Divider()
                            Button("Clear filters", role: .destructive) { filters = FeedFilters() }
                        }
                    } label: {
                        Label("Filter", systemImage: filters.isActive
                              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(FeedSort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Picker("Theme", selection: presetBinding) {
                            ForEach(ThemeSpec.presets) { Text($0.name).tag($0.id) }
                        }
                        Button("Customize...", systemImage: "slider.horizontal.3") { showStudio = true }
                        Toggle("Sounds", isOn: $soundOn)
                        Divider()
                        Button("Reviewer profile...", systemImage: "bolt.shield") { showProfile = true }
                        Button("Hidden and blocked...", systemImage: "eye.slash") { showHidden = true }
                    } label: {
                        Label("Style", systemImage: "paintpalette")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button { surprise() } label: { Label("Surprise me", systemImage: "dice") }
                        .help("Open a random site")
                }
                ToolbarItem(placement: .automatic) {
                    Button { savedOnly.toggle() } label: {
                        Label("Saved", systemImage: savedOnly ? "heart.fill" : "heart")
                    }
                    .help(savedOnly ? "Show everything" : "Show only saved sites")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { tapTick += 1; showSubmit = true } label: {
                        Label("Advertise", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(item: $selected) { l in
                ListingDetailView(listingID: l.id, store: store, onVisit: visit)
                    .zoomDestination(l.id, in: zoomNS)
            }
        }
        .sheet(isPresented: $showSubmit) {
            AuthGate { AdvertiserHome(store: store) }
        }
        .sheet(isPresented: $showStudio) {
            ThemeStudioView(themes: themes)
        }
        .task {
            // A password-reset link signs the person in and fires this event.
            for await (event, _) in supabase.auth.authStateChanges where event == .passwordRecovery {
                showSubmit = false
                showNewPassword = true
            }
        }
        .sheet(isPresented: $showNewPassword) {
            NewPasswordSheet()
        }
        .sheet(isPresented: $showProfile) {
            ReviewerProfileView(store: store)
        }
        .sheet(isPresented: $showHidden) {
            HiddenItemsView(hidden: hidden)
        }
        .sheet(item: $reporting) { l in
            ReportSheet(listing: l, store: store)
        }
        .alert("Mature content",
               isPresented: Binding(get: { pendingAdult != nil },
                                    set: { if !$0 { pendingAdult = nil } }),
               presenting: pendingAdult) { l in
            Button("Cancel", role: .cancel) {}
            Button("I'm 17 or older") { openSite(l) }
        } message: { _ in
            Text("This site is rated 17+. It opens in your browser.")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tapTick)
        .environment(\.theme, theme)
        .environment(hidden)
        .environment(saved)
        .preferredColorScheme(.dark)
        .tint(theme.accent)
        .animation(.easeInOut(duration: 0.3), value: themes.spec)
    }

    // MARK: Pieces

    /// Shows which preset is active in the Style menu, or nothing if you've customized it.
    private var presetBinding: Binding<String> {
        Binding(
            get: { ThemeSpec.presets.first { $0 == themes.spec }?.id ?? "custom" },
            set: { id in
                if let p = ThemeSpec.presets.first(where: { $0.id == id }) { themes.apply(p) }
            }
        )
    }

    private func filterFlag(_ path: WritableKeyPath<FeedFilters, Set<String>>, _ id: String) -> Binding<Bool> {
        Binding(get: { filters[keyPath: path].contains(id) },
                set: { on in
                    if on { filters[keyPath: path].insert(id) } else { filters[keyPath: path].remove(id) }
                })
    }

    private func heroCarousel(_ items: [Listing], kind: HeroKind) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items) { l in
                    HeroCard(listing: l, kind: kind,
                             onOpen: { open(detail: l) },
                             onVisit: { visit(l) },
                             onReport: { reporting = l })
                        .containerRelativeFrame(.horizontal) { length, _ in
                            kind == .sponsored ? min(length * 0.88, 440) : min(length * 0.72, 360)
                        }
                        .zoomSource(l.id, in: zoomNS)
                        .onSeen {
                            if kind == .sponsored { store.recordEvent(l, .impression) }
                        }
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.92)
                                .opacity(phase.isIdentity ? 1 : 0.7)
                                .rotation3DEffect(.degrees(phase.value * -10), axis: (x: 0, y: 1, z: 0))
                        }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 14)   // room for the glow
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var statusViews: some View {
        if store.isLoading && store.listings.isEmpty {
            ForEach(0..<4, id: \.self) { _ in
                SkeletonCard().padding(.horizontal)
            }
        } else if let err = store.errorMessage {
            Text(err).foregroundStyle(.red).padding()
        } else if filtered.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 44))
                    .foregroundStyle(theme.accent2)
                    .themeGlow(theme.accent2, radius: 10)
                Text("Nothing here yet").font(theme.title(.headline))
                Text("Try another search or category.").font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(40)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String, tint: Color,
                               subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .themeGlow(tint, radius: 6)
                Text(theme.heading(title))
                    .font(theme.title(.title3))
                    .tracking(theme.tracking)
            }
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    /// Pinned to the top while you scroll. Glass pills that blend together on OS 26.
    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 10) {
                HStack(spacing: 8) {
                    chip("All", symbol: "square.grid.2x2.fill", selected: category == nil) {
                        category = nil
                    }
                    ForEach(ListingCategory.all, id: \.self) { c in
                        chip(c, symbol: CategoryStyle.of(c).symbol, selected: category == c) {
                            category = (category == c) ? nil : c
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .background(
            LinearGradient(colors: [theme.background.opacity(0.85), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func chip(_ title: String, symbol: String, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button {
            tap()
            withAnimation(.spring(duration: 0.3)) { action() }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13).padding(.vertical, 8)
                .foregroundStyle(.white)
                .glassSurface(Capsule(), tint: selected ? theme.accent.opacity(0.85) : nil, interactive: true)
                .background {
                    if !GlassSupport.available && selected {
                        Capsule().fill(theme.accentFill)
                    }
                }
                .themeGlow(theme.accent, radius: selected ? 8 : 0)
                .scaleEffect(selected ? 1.05 : 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func tap() {
        tapTick += 1
        Sound.tap()
    }

    private func surprise() {
        guard let l = filtered.randomElement() else { return }
        open(detail: l)
    }

    private func openDeepLink() async {
        guard let id = router.listingID else { return }
        router.listingID = nil
        if let l = await store.listing(id: id) { selected = l }
    }

    private func open(detail l: Listing) {
        tap()
        selected = l
    }

    private func visit(_ l: Listing) {
        tap()
        if l.ageRating >= 17 { pendingAdult = l } else { openSite(l) }
    }

    private func openSite(_ l: Listing) {
        guard let url = URL(string: l.url), url.scheme == "https" else { return }
        store.recordClick(l)
        openURL(url)   // default browser
    }
}

// MARK: Shared "..." menu for cards

/// Report, hide, and block. Hiding and blocking stay on this device.
struct ListingMenu: View {
    @Environment(HiddenStore.self) private var hidden
    @Environment(SavedStore.self) private var saved
    let listing: Listing
    let onReport: () -> Void

    var body: some View {
        Button(saved.isSaved(listing) ? "Remove from saved" : "Save",
               systemImage: saved.isSaved(listing) ? "heart.slash" : "heart") { saved.toggle(listing) }
        Button("Hide this listing", systemImage: "eye.slash") { hidden.hide(listing) }
        if listing.ownerId != nil {
            Button("Block this advertiser", systemImage: "person.crop.circle.badge.xmark") {
                hidden.blockAdvertiser(of: listing)
            }
        }
        Button("Report", systemImage: "flag", role: .destructive, action: onReport)
    }
}

// MARK: Spotlight card (Sponsored and Featured)

struct HeroCard: View {
    @Environment(\.theme) private var theme
    let listing: Listing
    let kind: HeroKind
    let onOpen: () -> Void
    let onVisit: () -> Void
    let onReport: () -> Void
    @State private var pressed = false
    @State private var pulse = false

    private var labelColor: Color {
        switch kind {
        case .sponsored: theme.accent2
        case .featured: .yellow
        case .trending: .pink
        case .new: .green
        }
    }

    private var edgeStyle: AnyShapeStyle {
        kind == .sponsored
            ? theme.edge(strong: true)
            : AnyShapeStyle(LinearGradient(colors: [labelColor.opacity(0.9), glowColor.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var glowColor: Color {
        switch kind {
        case .sponsored: theme.accent
        case .featured: .orange
        case .trending: .pink
        case .new: .green
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius + 6, style: .continuous)
        let k = CGFloat(theme.glowIntensity)

        Button(action: onOpen) {
            ZStack(alignment: .bottomLeading) {
                ListingArt(category: listing.category, imageURL: listing.imageURL)
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Label(theme.heading(kind.label), systemImage: kind.symbol)
                        .font(.caption2.bold())
                        .foregroundStyle(labelColor)
                        .themeGlow(labelColor, radius: 5)
                    Text(listing.title)
                        .font(theme.title(.title2))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                    RatingSummary(listing: listing)
                    if let rank = listing.rank { RankBadge(rank: rank) }
                }
                .padding(16)
                .padding(.trailing, 90)   // keeps text clear of the Visit button
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressReporter(pressed: $pressed))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                AgeBadge(rating: listing.ageRating)
                Menu {
                    ListingMenu(listing: listing, onReport: onReport)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.white)
                        .padding(6)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(12)
        }
        .overlay(alignment: .bottomTrailing) {
            Button("Visit", action: onVisit)
                .buttonStyle(GlowButtonStyle())
                .padding(14)
        }
        .frame(height: kind == .sponsored ? 250 : 210)
        .clipShape(shape)
        .overlay(shape.strokeBorder(edgeStyle, lineWidth: 1.5))
        .shadow(color: theme.glow ? glowColor.opacity(0.5 * min(1, theme.glowIntensity)) : .black.opacity(0.3),
                radius: theme.glow ? (pulse ? 22 : 10) * k : 12,
                y: theme.glow ? 0 : 6)
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.spring(duration: 0.25), value: pressed)
        .animation(theme.glow ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true) : .default,
                   value: pulse)
        .onAppear { pulse = true }
    }
}

// MARK: Regular listing card

struct ListingCard: View {
    @Environment(\.theme) private var theme
    let listing: Listing
    let onOpen: () -> Void
    let onVisit: () -> Void
    let onReport: () -> Void
    @State private var pressed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                // Tappable info area. Visit and the menu sit outside it so they keep their own taps.
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            ListingThumb(listing: listing, size: 54)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(listing.title)
                                    .font(theme.title(.headline))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                RatingSummary(listing: listing)
                                if listing.verified { VerifiedBadge() }
                                if let rank = listing.rank { RankBadge(rank: rank) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.trailing, 64)
                        Text(listing.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressReporter(pressed: $pressed))

                HStack {
                    Chip(text: listing.category)
                    if let p = listing.pricing, let name = Taxonomy.label(p, in: Taxonomy.pricing) {
                        Chip(text: name)
                    }
                    Spacer()
                    Button("Visit", action: onVisit)
                        .buttonStyle(GlowButtonStyle())
                }
            }

            HStack(spacing: 6) {
                AgeBadge(rating: listing.ageRating)
                Menu {
                    ListingMenu(listing: listing, onReport: onReport)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(14)
        .cardSurface()
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.spring(duration: 0.25), value: pressed)
    }
}
