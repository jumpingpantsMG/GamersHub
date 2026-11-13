//
//  ThemeStudioView.swift
//  GamersHub
//
//  Created by Jaiden Kumar on 12/11/26.
//


import SwiftUI

extension Listing {
    /// Fake listing for the theme preview.
    static var sample: Listing {
        Listing(id: UUID(), ownerId: nil,
                title: "Pixel Raiders",
                description: "A fast 2D arena shooter you can play in your browser. Team up, climb the ranks, unlock skins.",
                url: "https://example.com", imageURL: nil,
                category: "Action", ageRating: 12,
                sponsoredUntil: nil, createdAt: Date(),
                avgRating: 4.6, ratingCount: 12, clickCount: 120)
    }
}

struct ThemeStudioView: View {
    @Bindable var themes: ThemeManager
    @AppStorage("soundOn") private var soundOn = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var saveName = ""
    @State private var importText = ""
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                presetsSection
                colorsSection
                shapeSection
                effectsSection
                textSection
                savedSection
                shareSection
                Section {
                    Toggle("Sounds", isOn: $soundOn)
                    Button("Reset to Neon Cyberpunk", role: .destructive) { themes.apply(.neon) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Theme studio")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: themes.spec) { _, _ in themes.persist() }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 740)
        #endif
    }

    // MARK: Sections

    /// The whole app behind this sheet already updates live, but a sheet covers most of it,
    /// so here is a sample card that always shows the current look.
    private var previewSection: some View {
        Section("Preview") {
            ZStack {
                ThemedBackground()
                VStack(spacing: 12) {
                    ListingCard(listing: .sample, onOpen: {}, onVisit: {}, onReport: {})
                    HStack(spacing: 8) {
                        Chip(text: "Chip")
                        RankBadge(rank: .gold)
                        Spacer()
                        Button("Button") {}.buttonStyle(GlowButtonStyle())
                    }
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .listRowInsets(EdgeInsets())
        }
    }

    private var presetsSection: some View {
        Section("Presets") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(ThemeSpec.presets) { p in
                        let selected = themes.spec == p
                        Button { themes.apply(p) } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(RGB(hex: p.background).color)
                                    .overlay(
                                        Circle()
                                            .fill(LinearGradient(colors: [RGB(hex: p.accent).color, RGB(hex: p.accent2).color],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .padding(9)
                                    )
                                    .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.95 : 0.15),
                                                                   lineWidth: selected ? 3 : 1))
                                    .frame(width: 52, height: 52)
                                Text(p.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 70)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var colorsSection: some View {
        Section("Colors") {
            ColorPicker("Accent", selection: colorBinding(\.accent), supportsOpacity: false)
            ColorPicker("Second accent", selection: colorBinding(\.accent2), supportsOpacity: false)
            ColorPicker("Background", selection: colorBinding(\.background), supportsOpacity: false)
        }
    }

    private var shapeSection: some View {
        Section("Shape and glass") {
            sliderRow("Corner roundness", $themes.spec.cornerRadius, 6...34,
                      display: "\(Int(themes.spec.cornerRadius))")
            sliderRow("Glass tint", $themes.spec.glassTint, 0...0.6,
                      display: "\(Int(themes.spec.glassTint / 0.6 * 100))%")
        }
    }

    private var effectsSection: some View {
        Section("Effects") {
            sliderRow("Glow", $themes.spec.glow, 0...1.5,
                      display: themes.spec.glow < 0.05 ? "Off" : "\(Int(themes.spec.glow / 1.5 * 100))%")
            Picker("Background", selection: $themes.spec.backgroundStyle) {
                ForEach(BackgroundStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            if themes.spec.backgroundStyle == .mesh {
                sliderRow("Background motion", $themes.spec.motion, 0...1.5,
                          display: themes.spec.motion < 0.05 ? "Still" : "\(Int(themes.spec.motion / 1.5 * 100))%")
            }
            if themes.spec.backgroundStyle != .solid {
                sliderRow("Background brightness", $themes.spec.vividness, 0.1...1,
                          display: "\(Int(themes.spec.vividness * 100))%")
            }
        }
    }

    private var textSection: some View {
        Section("Text") {
            Picker("Font style", selection: $themes.spec.font) {
                ForEach(FontChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Heading weight", selection: $themes.spec.weight) {
                ForEach(WeightChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            Toggle("UPPERCASE headings", isOn: $themes.spec.uppercase)
        }
    }

    private var savedSection: some View {
        Section("My themes") {
            HStack {
                TextField("Name this look", text: $saveName)
                Button("Save") {
                    themes.saveCurrent(as: saveName)
                    saveName = ""
                }
                .disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if themes.saved.isEmpty {
                Text("Saved themes appear here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(themes.saved) { s in
                HStack {
                    Button {
                        themes.apply(s)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(LinearGradient(colors: [RGB(hex: s.accent).color, RGB(hex: s.accent2).color],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 22, height: 22)
                            Text(s.name)
                            if themes.spec == s {
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(role: .destructive) { themes.delete(s) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var shareSection: some View {
        Section("Share") {
            ShareLink("Share this theme", item: themes.spec.shareCode)
            TextField("Paste a theme code", text: $importText)
            Button("Import theme code") {
                if let spec = ThemeSpec(shareCode: importText) {
                    themes.apply(spec)
                    importText = ""
                    importMessage = "Imported \"\(spec.name)\"."
                } else {
                    importMessage = "That doesn't look like a theme code."
                }
            }
            .disabled(importText.trimmingCharacters(in: .whitespaces).isEmpty)
            if let importMessage {
                Text(importMessage).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Helpers

    private func colorBinding(_ keyPath: WritableKeyPath<ThemeSpec, String>) -> Binding<Color> {
        Binding(
            get: { RGB(hex: themes.spec[keyPath: keyPath]).color },
            set: { themes.spec[keyPath: keyPath] = $0.rgb.hex }
        )
    }

    private func sliderRow(_ title: String, _ value: Binding<Double>,
                           _ range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}
