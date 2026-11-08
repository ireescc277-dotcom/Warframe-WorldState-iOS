import SwiftUI

/// Layout and type tokens for the whole app.
///
/// The previous screens mixed nine font sizes (9–20pt), gave every element its
/// own bordered chip, and put three or four text lines in every row. Nothing
/// was louder than anything else, so a list of 26 fissures read as a wall.
///
/// The rules here are deliberately few:
///  - Four text sizes, one of which is reserved for numbers.
///  - Borders are gone. Separation comes from one hairline and from space.
///  - Colour marks exactly one thing per row: its category, via a 3pt bar.
public enum WFUI {
    // Surfaces. Two levels only: the page, and the block sitting on it.
    public static let surface = Color(hex: "0F1720")
    public static let raised = Color(hex: "17222E")
    public static let hairline = Color.white.opacity(0.06)

    // Spacing scale.
    public static let s1: CGFloat = 4
    public static let s2: CGFloat = 8
    public static let s3: CGFloat = 12
    public static let s4: CGFloat = 20
    public static let s5: CGFloat = 32

    public static let radius: CGFloat = 14

    public static func eraColor(_ modifier: String?) -> Color {
        switch modifier {
        case "VoidT1": return Color(hex: "9AA8B6")
        case "VoidT2": return WFTheme.cyan
        case "VoidT3": return WFTheme.green
        case "VoidT4": return WFTheme.gold
        case "VoidT5": return WFTheme.red
        case "VoidT6": return WFTheme.purple
        default: return WFTheme.cyan
        }
    }
}

// MARK: - Type scale

public extension Font {
    /// Numbers that own a screen. Only the "next up" block uses this.
    static let wfHero = Font.system(size: 46, weight: .semibold, design: .rounded).monospacedDigit()
    /// Numbers that sit at the end of a row.
    static let wfNum = Font.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()
    static let wfNumSmall = Font.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit()
    /// Row headline.
    static let wfTitle = Font.system(size: 16, weight: .semibold)
    /// Row second line, and any sentence.
    static let wfBody = Font.system(size: 13, weight: .regular)
    /// Section headers, units, chips.
    static let wfLabel = Font.system(size: 11, weight: .medium)
}

// MARK: - Building blocks

public struct WFHairline: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(WFUI.hairline)
            .frame(height: 0.5)
    }
}

public struct WFSurface<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }
}

public struct WFSectionHeader: View {
    private let title: String
    private let trailing: String?

    public init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            Spacer(minLength: WFUI.s2)
            if let trailing = trailing {
                Text(trailing)
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
        }
        .padding(.horizontal, WFUI.s1)
        .padding(.bottom, WFUI.s2)
    }
}

/// One event, one row: a colour bar, a headline, a context line, a number.
/// Anything that does not fit in those four slots belongs on the detail screen.
public struct WFEventRow<Trailing: View>: View {
    private let accent: Color
    private let title: String
    private let subtitle: String
    private let isLast: Bool
    private let trailing: Trailing

    public init(
        accent: Color,
        title: String,
        subtitle: String,
        isLast: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.accent = accent
        self.title = title
        self.subtitle = subtitle
        self.isLast = isLast
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WFUI.s3) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(accent)
                    .frame(width: 3, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.wfTitle)
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(.wfBody)
                        .foregroundColor(WFTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: WFUI.s2)

                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if !isLast {
                WFHairline()
                    .padding(.leading, 30)
            }
        }
    }
}

/// The right-hand number of a row. Minutes below an hour, `h:mm` below a day,
/// days above it. Three shapes, so the eye can compare rows without reading.
public struct WFTimeLeft: View {
    public let date: Date?
    public var isHero: Bool = false

    @EnvironmentObject private var vm: WorldStateViewModel

    public init(_ date: Date?, isHero: Bool = false) {
        self.date = date
        self.isHero = isHero
    }

    public var body: some View {
        let parts = split()
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(parts.value)
                .font(isHero ? .wfHero : (parts.unit.isEmpty ? .wfNumSmall : .wfNum))
                .foregroundColor(parts.color)
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(.wfLabel)
                    .foregroundColor(parts.color.opacity(0.75))
            }
        }
        .fixedSize()
    }

    private func split() -> (value: String, unit: String, color: Color) {
        guard let target = date else {
            return ("—", "", WFTheme.textMuted)
        }
        let seconds = Int(target.timeIntervalSince(vm.currentTime))
        if seconds <= 0 {
            return ("已结束", "", WFTheme.textMuted)
        }
        if seconds < 3600 {
            return ("\(max(seconds / 60, 1))", "分", WFTheme.gold)
        }
        if seconds < 86400 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return (String(format: "%d:%02d", h, m), "", seconds < 7200 ? WFTheme.gold : WFTheme.textPrimary)
        }
        return ("\(seconds / 86400)", "天", WFTheme.textSecondary)
    }
}

/// A filter chip that also carries its own count. Replaces both the KPI grid
/// and the segmented control, which were saying the same thing twice.
public struct WFChip: View {
    private let label: String
    private let count: Int
    private let tint: Color
    private let isOn: Bool
    private let action: () -> Void

    public init(label: String, count: Int, tint: Color, isOn: Bool, action: @escaping () -> Void) {
        self.label = label
        self.count = count
        self.tint = tint
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(isOn ? tint : WFTheme.textMuted)
            }
            .foregroundColor(isOn ? tint : WFTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isOn ? tint.opacity(0.14) : WFUI.surface)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
