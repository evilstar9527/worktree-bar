import SwiftUI

/// Shared visual language for the colorful, fresh card UI. Pure presentation —
/// no business logic or data dependencies. Consumed by every view so the
/// palette, spacing, corner radius, and hover behavior stay consistent across
/// the popover and the standalone windows.

// MARK: - Palette

/// Fresh, soft, saturated palette. Each color is a fixed semantic so the whole
/// app reads as one coherent scheme. Values are sRGB 0...1.
enum AppPalette {
    static let blue   = Color(red: 0.31, green: 0.56, blue: 0.97) // #4F8EF7
    static let violet = Color(red: 0.55, green: 0.36, blue: 0.96) // #8B5CF6
    static let amber  = Color(red: 0.96, green: 0.62, blue: 0.04) // #F59E0B
    static let mint   = Color(red: 0.20, green: 0.83, blue: 0.60) // #34D399
    static let coral  = Color(red: 0.98, green: 0.44, blue: 0.52) // #FB7185
    static let cyan   = Color(red: 0.13, green: 0.83, blue: 0.93) // #22D3EE
    static let indigo = Color(red: 0.39, green: 0.40, blue: 0.95) // #6366F1

    /// Cycled per launcher index (launchers are user-editable, so index%count
    /// gives every button a stable color with a natural fallback).
    static let launcherPalette: [Color] = [blue, violet, amber, mint, coral, cyan]

    static func launcherColor(_ index: Int) -> Color {
        launcherPalette[((index % launcherPalette.count) + launcherPalette.count) % launcherPalette.count]
    }

    /// Page background gradient — a barely-there blue-gray wash so cards float.
    static let canvasTop    = Color(red: 0.97, green: 0.98, blue: 0.99) // #F7F9FD
    static let canvasBottom = Color(red: 0.93, green: 0.95, blue: 0.98) // #EEF2FA

    static var canvas: LinearGradient {
        LinearGradient(
            colors: [canvasTop, canvasBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension Color {
    /// Soft tinted fill for cards (visible, not washed out).
    var softFill: Color { opacity(0.14) }
    /// Tinted hairline stroke for cards.
    var softStroke: Color { opacity(0.38) }
}

// MARK: - Metrics

enum CardMetrics {
    static let cardCornerRadius: CGFloat = 10
    static let badgeCornerRadius: CGFloat = 5
    static let rowVSpacing: CGFloat = 7
    static let sectionGutter: CGFloat = 12
    static let cardPaddingH: CGFloat = 12
    static let cardPaddingV: CGFloat = 9
    /// Tighter values for the narrow `.menu` presentation (380pt wide).
    static let compactGutter: CGFloat = 9
    static let compactPaddingH: CGFloat = 9
    static let hairline: CGFloat = 1
}

// MARK: - Card background

/// Rounded card surface with a real, visible color: a light base plus a tinted
/// wash, a tinted hairline border, and a soft shadow. `isAccented` swaps to a
/// blue gradient + bold stroke for the "current" worktree. Hover deepens fill,
/// border, and shadow a notch.
struct CardBackground: ViewModifier {
    var tint: Color = AppPalette.blue
    var isAccented: Bool = false
    var isHovered: Bool = false

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                // Base surface (white in light mode, control bg in dark).
                RoundedRectangle(cornerRadius: CardMetrics.cardCornerRadius, style: .continuous)
                    .fill(baseFill)
                // Color: accent gradient for current, tinted wash otherwise.
                RoundedRectangle(cornerRadius: CardMetrics.cardCornerRadius, style: .continuous)
                    .fill(washStyle)
                // Border.
                RoundedRectangle(cornerRadius: CardMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: isAccented ? 2 : CardMetrics.hairline)
            }
            .shadow(
                color: shadowColor,
                radius: isHovered ? 6 : 3,
                y: isHovered ? 2 : 1
            )
        }
    }

    private var isDark: Bool { scheme == .dark }

    private var baseFill: Color {
        isDark ? Color(nsColor: .controlBackgroundColor) : .white
    }

    /// The colored layer painted over the base.
    private var washStyle: AnyShapeStyle {
        if isAccented {
            let top = AppPalette.blue.opacity(isDark ? 0.30 : 0.20)
            let bottom = AppPalette.blue.opacity(isDark ? 0.16 : 0.08)
            return AnyShapeStyle(
                LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            )
        }
        let wash = tint.opacity((isDark ? 0.20 : 0.12) + (isHovered ? 0.05 : 0))
        return AnyShapeStyle(wash)
    }

    private var strokeColor: Color {
        if isAccented { return AppPalette.blue.opacity(isDark ? 0.9 : 0.8) }
        return tint.opacity(isDark ? 0.45 : 0.38)
    }

    private var shadowColor: Color {
        if isAccented { return AppPalette.blue.opacity(isHovered ? 0.28 : 0.18) }
        return .black.opacity(isHovered ? 0.10 : 0.05)
    }
}

extension View {
    func cardBackground(tint: Color = AppPalette.blue, isAccented: Bool = false, isHovered: Bool = false) -> some View {
        modifier(CardBackground(tint: tint, isAccented: isAccented, isHovered: isHovered))
    }

    /// Dashed-border placeholder card for empty / not-a-repo states.
    func dashedCard() -> some View {
        background {
            RoundedRectangle(cornerRadius: CardMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    AppPalette.indigo.opacity(0.32),
                    style: StrokeStyle(lineWidth: CardMetrics.hairline, dash: [4])
                )
        }
    }
}

// MARK: - Hover-aware row

/// Wraps a row so each instance owns its own `isHovered` state. Using this
/// instead of a shared `@State` in the parent avoids every row lighting up at
/// once — SwiftUI gives each `HoverableRow` its own storage.
struct HoverableRow<Content: View>: View {
    @State private var isHovered = false
    let content: (Bool) -> Content

    var body: some View {
        content(isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Worktree badge

/// Compact status pill shown next to a worktree name. `current` is the loudest
/// (solid blue gradient, white text); the rest are tinted soft pills.
struct WorktreeBadge: View {
    enum Kind {
        case current
        case detached
        case locked
        case prunable

        var text: String {
            switch self {
            case .current: return "CURRENT"
            case .detached: return "detached"
            case .locked: return "locked"
            case .prunable: return "prunable"
            }
        }

        var systemImage: String? {
            switch self {
            case .current: return nil
            case .detached: return "arrow.triangle.branch"
            case .locked: return "lock.fill"
            case .prunable: return "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .current: return AppPalette.blue
            case .detached: return AppPalette.violet
            case .locked: return .secondary
            case .prunable: return AppPalette.amber
            }
        }
    }

    let kind: Kind
    /// In the narrow popover, non-current badges collapse to icon-only.
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let image = kind.systemImage {
                Image(systemName: image)
            }
            if !(compact && kind != .current) {
                Text(kind.text)
            }
        }
        .font(.system(size: 9, weight: .bold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundColor(kind == .current ? .white : kind.tint)
        .background {
            RoundedRectangle(cornerRadius: CardMetrics.badgeCornerRadius, style: .continuous)
                .fill(badgeFill)
        }
    }

    private var badgeFill: AnyShapeStyle {
        if kind == .current {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [AppPalette.blue, AppPalette.indigo],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(kind.tint.opacity(0.16))
    }
}

// MARK: - Launcher icon button

/// Square icon button with a colored pill background. Each launcher gets its own
/// `tint` (cycled by index). Press deepens the pill.
struct LauncherIconButtonStyle: ButtonStyle {
    var tint: Color = AppPalette.blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 28, height: 24)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.30 : 0.15))
            }
            .contentShape(Rectangle())
    }
}

// MARK: - Info / error card

/// Soft tinted callout used for inline errors and warnings. `tint` drives both
/// the icon and the border/fill.
struct InfoCard: View {
    var systemImage: String
    var message: String
    var tint: Color = AppPalette.coral
    var lineLimit: Int? = 2

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(tint)
            Text(message)
                .foregroundColor(.primary)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: CardMetrics.cardCornerRadius, style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: CardMetrics.cardCornerRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: CardMetrics.hairline)
                }
        }
    }
}
