import SwiftUI

enum FeedSort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case topRated = "Top rated"
    var id: String { rawValue }
}

/// Sponsored = paid placement. Featured = earned from ratings and visits.
enum HeroKind {
    case sponsored, featured

    var label: String { self == .sponsored ? "Sponsored" : "Featured" }
    var symbol: String { self == .sponsored ? "megaphone.fill" : "flame.fill" }
}

struct BrowseView: View {
    @AppStorage("soundOn") private var soundOn = true

    @State private var themes = ThemeManager()
    @State private var hidden = HiddenStore()
    @State private var store = ListingsStore()
    @State private var search = ""
    @State private var category: String?
    @State private var sort: FeedSort = .newest
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

    /// Everything else. A listing only ever appears in one section.
    private var regular: [Listing] {
        let skip = Set(sponsored.map(\.id) + featuredRow.map(\.id))
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
            .refreshable { await store.load() }
            .task { await store.load() }
            .toolbar {
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
                        Button("Hidden and blocked...", systemImage: "eye.slash") { showHidden = true }
                    } label: {
                        Label("Style", systemImage: "paintpalette")
                    }
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
    let listing: Listing
    let onReport: () -> Void

    var body: some View {
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

    private var labelColor: Color { kind == .sponsored ? theme.accent2 : .yellow }

    private var edgeStyle: AnyShapeStyle {
        kind == .sponsored
            ? theme.edge(strong: true)
            : AnyShapeStyle(LinearGradient(colors: [.yellow.opacity(0.9), .orange.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var glowColor: Color { kind == .sponsored ? theme.accent : .orange }

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
