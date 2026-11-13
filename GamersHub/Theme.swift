import SwiftUI
#if os(iOS)
import UIKit
import AudioToolbox
#elseif os(macOS)
import AppKit
#endif

// MARK: Colors

struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    /// Accepts "#RRGGBB", "RRGGBB" or "#RGB". Anything invalid becomes white.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&v) else {
            self.init(r: 1, g: 1, b: 1)
            return
        }
        self.init(r: Double((v >> 16) & 0xFF) / 255,
                  g: Double((v >> 8) & 0xFF) / 255,
                  b: Double(v & 0xFF) / 255)
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Used to turn a ColorPicker choice back into a hex string.
    var rgb: RGB {
        #if os(macOS)
        let c = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.white
        return RGB(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGB(r: Double(r), g: Double(g), b: Double(b))
        #endif
    }
}

// MARK: Theme settings (what you edit, save, and share)

enum BackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case mesh = "Animated mesh"
    case gradient = "Gradient"
    case solid = "Solid"
    var id: String { rawValue }
}

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case monospaced = "Monospaced"
    case rounded = "Rounded"
    case standard = "Standard"
    case serif = "Serif"
    var id: String { rawValue }

    var design: Font.Design {
        switch self {
        case .monospaced: return .monospaced
        case .rounded:    return .rounded
        case .standard:   return .default
        case .serif:      return .serif
        }
    }
}

enum WeightChoice: String, Codable, CaseIterable, Identifiable {
    case regular = "Regular"
    case semibold = "Semibold"
    case bold = "Bold"
    case heavy = "Heavy"
    case black = "Black"
    var id: String { rawValue }

    var weight: Font.Weight {
        switch self {
        case .regular:  return .regular
        case .semibold: return .semibold
        case .bold:     return .bold
        case .heavy:    return .heavy
        case .black:    return .black
        }
    }
}

struct ThemeSpec: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var background: String        // hex
    var accent: String            // hex
    var accent2: String           // hex
    var cornerRadius: Double      // 6...34
    var glassTint: Double         // 0...0.6   how strongly glass is tinted with the accent
    var glow: Double              // 0...1.5   0 = no glow at all
    var motion: Double            // 0...1.5   background drift speed, 0 = still
    var vividness: Double         // 0.1...1   how bright the background colors get
    var backgroundStyle: BackgroundStyle
    var font: FontChoice
    var weight: WeightChoice
    var uppercase: Bool           // UPPERCASE headings

    enum CodingKeys: String, CodingKey {
        case id, name, background, accent, accent2, cornerRadius, glassTint, glow
        case motion, vividness, backgroundStyle, font, weight, uppercase
    }
}

extension ThemeSpec {
    /// Missing or out-of-range values (older saves, hand-edited codes) fall back to safe ones.
    init(from decoder: Decoder) throws {
        let d = ThemeSpec.neon
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "custom"
        name = String((try c.decodeIfPresent(String.self, forKey: .name) ?? "Custom").prefix(40))
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? d.background
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? d.accent
        accent2 = try c.decodeIfPresent(String.self, forKey: .accent2) ?? d.accent2
        cornerRadius = clamp(try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius, 6, 34)
        glassTint = clamp(try c.decodeIfPresent(Double.self, forKey: .glassTint) ?? d.glassTint, 0, 0.6)
        glow = clamp(try c.decodeIfPresent(Double.self, forKey: .glow) ?? d.glow, 0, 1.5)
        motion = clamp(try c.decodeIfPresent(Double.self, forKey: .motion) ?? d.motion, 0, 1.5)
        vividness = clamp(try c.decodeIfPresent(Double.self, forKey: .vividness) ?? d.vividness, 0.1, 1)
        backgroundStyle = try c.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? d.backgroundStyle
        font = try c.decodeIfPresent(FontChoice.self, forKey: .font) ?? d.font
        weight = try c.decodeIfPresent(WeightChoice.self, forKey: .weight) ?? d.weight
        uppercase = try c.decodeIfPresent(Bool.self, forKey: .uppercase) ?? d.uppercase
    }

    var encoded: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func decode(_ s: String) -> ThemeSpec? {
        try? JSONDecoder().decode(ThemeSpec.self, from: Data(s.utf8))
    }

    static func encodeList(_ list: [ThemeSpec]) -> String {
        (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    static func decodeList(_ s: String) -> [ThemeSpec]? {
        try? JSONDecoder().decode([ThemeSpec].self, from: Data(s.utf8))
    }

    /// A short text you can send to someone. They paste it into "Import" and get your theme.
    var shareCode: String { "GH1:" + Data(encoded.utf8).base64EncodedString() }

    init?(shareCode: String) {
        let t = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("GH1:"),
              let data = Data(base64Encoded: String(t.dropFirst(4))),
              let json = String(data: data, encoding: .utf8),
              let spec = ThemeSpec.decode(json) else { return nil }
        self = spec
    }
}

// MARK: Presets

extension ThemeSpec {
    static let neon = ThemeSpec(
        id: "neon", name: "Neon Cyberpunk",
        background: "#07050F", accent: "#A855F7", accent2: "#22D3EE",
        cornerRadius: 22, glassTint: 0.16, glow: 1.0, motion: 0.45, vividness: 0.65,
        backgroundStyle: .mesh, font: .monospaced, weight: .heavy, uppercase: true)

    static let modern = ThemeSpec(
        id: "modern", name: "Clean Modern",
        background: "#0B0E16", accent: "#8B5CF6", accent2: "#06B6D4",
        cornerRadius: 20, glassTint: 0, glow: 0, motion: 0.2, vividness: 0.25,
        backgroundStyle: .mesh, font: .rounded, weight: .bold, uppercase: false)

    static let synthwave = ThemeSpec(
        id: "synthwave", name: "Synthwave",
        background: "#120216", accent: "#FF2E93", accent2: "#FFB000",
        cornerRadius: 24, glassTint: 0.2, glow: 1.1, motion: 0.5, vividness: 0.6,
        backgroundStyle: .mesh, font: .monospaced, weight: .heavy, uppercase: true)

    static let toxic = ThemeSpec(
        id: "toxic", name: "Toxic Green",
        background: "#020A05", accent: "#00FF6A", accent2: "#B6FF00",
        cornerRadius: 10, glassTint: 0.12, glow: 1.2, motion: 0.3, vividness: 0.5,
        backgroundStyle: .mesh, font: .monospaced, weight: .bold, uppercase: true)

    static let crimson = ThemeSpec(
        id: "crimson", name: "Crimson Esports",
        background: "#0C0606", accent: "#EF4444", accent2: "#F97316",
        cornerRadius: 14, glassTint: 0.18, glow: 0.8, motion: 0.35, vividness: 0.6,
        backgroundStyle: .mesh, font: .standard, weight: .black, uppercase: true)

    static let ocean = ThemeSpec(
        id: "ocean", name: "Deep Ocean",
        background: "#04101C", accent: "#3B82F6", accent2: "#BAE6FD",
        cornerRadius: 26, glassTint: 0.1, glow: 0.3, motion: 0.25, vividness: 0.5,
        backgroundStyle: .mesh, font: .rounded, weight: .semibold, uppercase: false)

    static let stealth = ThemeSpec(
        id: "stealth", name: "Stealth",
        background: "#000000", accent: "#8B8BF5", accent2: "#6EE7B7",
        cornerRadius: 16, glassTint: 0, glow: 0, motion: 0, vividness: 0.3,
        backgroundStyle: .solid, font: .standard, weight: .semibold, uppercase: false)

    static let presets: [ThemeSpec] = [neon, modern, synthwave, toxic, crimson, ocean, stealth]
}

// MARK: Resolved theme (what the views actually read)

struct Theme: Equatable, Identifiable {
    let id: String
    let name: String
    let background: Color
    let card: Color
    let accent: Color
    let accent2: Color
    let glowIntensity: Double
    let radius: CGFloat
    let design: Font.Design
    let weight: Font.Weight
    let meshColors: [Color]    // 9 colors for the 3x3 background
    let glassTint: Color?
    let drift: Double
    let backgroundStyle: BackgroundStyle
    let uppercase: Bool

    var glow: Bool { glowIntensity > 0.05 }
    var tracking: CGFloat { uppercase ? 1.5 : 0 }

    func title(_ style: Font.TextStyle) -> Font {
        .system(style, design: design).weight(weight)
    }

    func heading(_ text: String) -> String { uppercase ? text.uppercased() : text }

    /// Gradient on glow themes, flat color otherwise.
    var accentFill: AnyShapeStyle {
        glow
            ? AnyShapeStyle(LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(accent)
    }

    /// Thin highlight around glass: accent gradient on glow themes, a soft rim otherwise.
    func edge(strong: Bool) -> AnyShapeStyle {
        if glow {
            let o = strong ? 1.0 : 0.45
            return AnyShapeStyle(LinearGradient(colors: [accent.opacity(o), accent2.opacity(o)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(LinearGradient(colors: [.white.opacity(strong ? 0.4 : 0.22), .white.opacity(0.04)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    static let neon = ThemeSpec.neon.resolved
}

extension ThemeSpec {
    var resolved: Theme {
        let bg = RGB(hex: background)
        let a = RGB(hex: accent)
        let c = RGB(hex: accent2)
        let v = vividness
        func mix(_ x: RGB, _ y: RGB, _ t: Double) -> Color { x.mixed(with: y, t).color }

        // 3x3 mesh built from just your three colors.
        let mesh: [Color] = [
            bg.color,        mix(bg, a, v * 0.35), bg.color,
            mix(bg, a, v * 0.55), mix(bg, a, v),   mix(bg, c, v * 0.4),
            bg.color,        mix(bg, a, v * 0.25), mix(bg, c, v * 0.7),
        ]

        return Theme(
            id: id, name: name,
            background: bg.color,
            card: mix(bg, a, 0.12),
            accent: a.color, accent2: c.color,
            glowIntensity: glow,
            radius: CGFloat(cornerRadius),
            design: font.design, weight: weight.weight,
            meshColors: mesh,
            glassTint: glassTint > 0.01 ? a.color.opacity(glassTint) : nil,
            drift: motion,
            backgroundStyle: backgroundStyle,
            uppercase: uppercase
        )
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.neon
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: Theme storage (current theme + saved themes, kept on this device)

@MainActor
@Observable
final class ThemeManager {
    var spec: ThemeSpec
    var saved: [ThemeSpec]

    private let specKey = "themeSpec.v1"
    private let savedKey = "savedThemes.v1"

    init() {
        let d = UserDefaults.standard
        spec = d.string(forKey: specKey).flatMap(ThemeSpec.decode) ?? .neon
        saved = d.string(forKey: savedKey).flatMap(ThemeSpec.decodeList) ?? []
    }

    func persist() {
        let d = UserDefaults.standard
        d.set(spec.encoded, forKey: specKey)
        d.set(ThemeSpec.encodeList(saved), forKey: savedKey)
    }

    func apply(_ s: ThemeSpec) {
        spec = s
        persist()
    }

    func saveCurrent(as name: String) {
        var copy = spec
        copy.id = UUID().uuidString
        copy.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !copy.name.isEmpty else { return }
        saved.append(copy)
        persist()
    }

    func delete(_ s: ThemeSpec) {
        saved.removeAll { $0.id == s.id }
        persist()
    }
}

// MARK: Liquid Glass (real glass on OS 26 + Xcode 26, frosted material otherwise)

enum GlassSupport {
    static var available: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) { return true }
        #endif
        return false
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, macOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    #if os(iOS)
    if interactive { glass = glass.interactive() }
    #endif
    return glass
}
#endif

extension View {
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.frostedSurface(shape, tint: tint)
        }
        #else
        self.frostedSurface(shape, tint: tint)
        #endif
    }

    func frostedSurface<S: Shape>(_ shape: S, tint: Color?) -> some View {
        self
            .background { shape.fill(.ultraThinMaterial) }
            .background { shape.fill(tint ?? Color.black.opacity(0.28)) }
    }
}

/// Lets nearby glass shapes blend and morph on OS 26. A plain pass-through before that.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

// MARK: Background

struct MeshBackdrop: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var still: Bool { reduceMotion || theme.drift <= 0 }

    var body: some View {
        if #available(iOS 18, macOS 15, *) {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: still)) { ctx in
                MeshGradient(
                    width: 3, height: 3,
                    points: Self.points(at: still ? 0 : ctx.date.timeIntervalSinceReferenceDate * theme.drift),
                    colors: theme.meshColors
                )
            }
        } else {
            ZStack {
                RadialGradient(colors: [theme.accent.opacity(theme.glow ? 0.28 : 0.12), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 420)
                RadialGradient(colors: [theme.accent2.opacity(theme.glow ? 0.16 : 0.08), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 380)
            }
        }
    }

    /// Corners stay put; the edge and center points drift so colors slowly swirl.
    private static func points(at t: Double) -> [SIMD2<Float>] {
        let a = Float(sin(t * 0.9)) * 0.09
        let b = Float(cos(t * 0.7)) * 0.09
        return [
            [0, 0],           [0.5 + a, 0],      [1, 0],
            [0, 0.5 + b],     [0.5 + b, 0.5 - a], [1, 0.5 - b],
            [0, 1],           [0.5 - a, 1],      [1, 1],
        ]
    }
}

struct ThemedBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.background
            switch theme.backgroundStyle {
            case .mesh:
                MeshBackdrop()
            case .gradient:
                LinearGradient(colors: [theme.background, theme.meshColors[4], theme.meshColors[8]],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            case .solid:
                Color.clear
            }
            if theme.backgroundStyle != .solid {
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: Card surface (glass, edge, glow, pulsing glow when highlighted)

struct CardSurface: ViewModifier {
    @Environment(\.theme) private var theme
    var featured = false
    var radius: CGFloat? = nil
    @State private var pulse = false

    private var shadowColor: Color {
        theme.glow
            ? theme.accent.opacity((featured ? 0.5 : 0.15) * min(1, theme.glowIntensity))
            : .black.opacity(0.28)
    }

    private var shadowRadius: CGFloat {
        guard theme.glow else { return 10 }
        return (featured ? (pulse ? 20 : 8) : 5) * CGFloat(theme.glowIntensity)
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? theme.radius, style: .continuous)
        content
            .glassSurface(shape, tint: featured ? theme.accent.opacity(0.3) : theme.glassTint)
            .overlay(shape.strokeBorder(theme.edge(strong: featured), lineWidth: featured ? 1.5 : 1))
            .shadow(color: shadowColor, radius: shadowRadius, y: theme.glow ? 0 : 6)
            .animation(featured && theme.glow
                       ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
                       : .default,
                       value: pulse)
            .onAppear { if featured { pulse = true } }
    }
}

extension View {
    func cardSurface(featured: Bool = false, radius: CGFloat? = nil) -> some View {
        modifier(CardSurface(featured: featured, radius: radius))
    }
}

// MARK: Glow

struct ThemeGlow: ViewModifier {
    @Environment(\.theme) private var theme
    let color: Color
    var radius: CGFloat = 6

    func body(content: Content) -> some View {
        content.shadow(color: theme.glow ? color.opacity(0.7 * min(1, theme.glowIntensity)) : .clear,
                       radius: radius * CGFloat(theme.glowIntensity))
    }
}

extension View {
    func themeGlow(_ color: Color, radius: CGFloat = 6) -> some View {
        modifier(ThemeGlow(color: color, radius: radius))
    }
}

// MARK: Navigation zoom (iOS 18+): cards expand into the detail page

extension View {
    @ViewBuilder
    func zoomSource(_ id: UUID, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        if #available(iOS 18, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func zoomDestination(_ id: UUID, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        if #available(iOS 18, *) {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: Button styles

struct GlowButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(theme.title(large ? .body : .subheadline))
            .padding(.horizontal, large ? 22 : 16)
            .padding(.vertical, large ? 13 : 8)
            .foregroundStyle(.white)

        Group {
            if GlassSupport.available {
                label.glassSurface(Capsule(), tint: theme.accent.opacity(0.85), interactive: true)
            } else {
                label.background(Capsule().fill(theme.accentFill))
            }
        }
        .shadow(color: theme.glow ? theme.accent.opacity(0.6 * min(1, theme.glowIntensity)) : .black.opacity(0.2),
                radius: theme.glow ? 8 * CGFloat(theme.glowIntensity) : 8)
        .scaleEffect(configuration.isPressed ? 0.93 : 1)
        .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Reports its pressed state to a binding so a whole card can shrink while one part is pressed.
struct PressReporter: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, now in pressed = now }
    }
}

// MARK: Sound (system sounds, no files needed)

enum Sound {
    static var enabled: Bool {
        (UserDefaults.standard.object(forKey: "soundOn") as? Bool) ?? true
    }

    static func tap() {
        guard enabled else { return }
        #if os(iOS)
        AudioServicesPlaySystemSound(1104)
        #elseif os(macOS)
        NSSound(named: NSSound.Name("Pop"))?.play()
        #endif
    }
}
