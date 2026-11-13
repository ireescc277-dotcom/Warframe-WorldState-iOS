import SwiftUI
import DamageKit
#if canImport(UIKit)
import UIKit
#endif

/// Unified presentation model for Weapon, Warframe, Companion, Archwing, Riven, and Arcane cards.
struct ModCardPresentation: Identifiable, Hashable {
    let id: String
    let rawName: String
    let displayName: String
    let slotTag: String?
    let rank: Int?
    let maxRank: Int?
    let isRiven: Bool
    let rivenLines: [String]
    let metadata: ModCardMetadata?

    var effectiveMaxRank: Int {
        maxRank ?? metadata?.maxRank ?? 0
    }

    var effectiveRank: Int {
        let cap = effectiveMaxRank
        guard let rank else { return cap }
        return min(max(0, rank), cap)
    }

    var effectiveDrain: Int? {
        if isRiven { return 18 }
        guard let metadata else { return nil }
        if metadata.isArcane || metadata.baseDrain == 0 && effectiveMaxRank == 0 {
            return nil
        }
        return abs(metadata.baseDrain) + effectiveRank
    }

    var isPositiveCapacity: Bool {
        guard let metadata else { return false }
        let compat = metadata.compat.lowercased()
        return metadata.baseDrain < 0 || compat.contains("光环") || compat.contains("架势")
    }

    var effectLines: [String] {
        if isRiven {
            return rivenLines.isEmpty ? ["自定义紫卡词条"] : rivenLines
        }
        if let metadata, !metadata.ranks.isEmpty {
            let idx = min(max(0, effectiveRank), metadata.ranks.count - 1)
            let raw = metadata.ranks[idx]
            let lines = raw
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty { return lines }
        }
        return ["暂无中文效果描述"]
    }

    var compatLabel: String {
        if isRiven { return "裂罅 Mod" }
        if let compat = metadata?.compat, !compat.isEmpty { return compat }
        return "升级 Mod"
    }

    @MainActor
    static func make(
        rawName: String,
        slotTag: String? = nil,
        rank: Int? = nil,
        maxRank: Int? = nil,
        isRiven: Bool = false,
        rivenLines: [String] = [],
        id: String? = nil
    ) -> ModCardPresentation {
        let catalog = NativeDamageCatalog.shared
        let meta = isRiven ? nil : catalog.modCard(for: rawName)
        let localized = isRiven ? rawName : catalog.localizedUpgradeName(rawName)
        return ModCardPresentation(
            id: id ?? "\(rawName)-\(slotTag ?? "")-\(rank ?? -1)",
            rawName: rawName,
            displayName: localized,
            slotTag: slotTag,
            rank: rank,
            maxRank: maxRank,
            isRiven: isRiven,
            rivenLines: rivenLines,
            metadata: meta
        )
    }
}

private enum ModRarityStyle {
    case common, uncommon, rare, legendary, riven

    init(card: ModCardPresentation) {
        if card.isRiven {
            self = .riven
            return
        }
        switch card.metadata?.rarity.uppercased() {
        case "LEGENDARY": self = .legendary
        case "RARE": self = .rare
        case "UNCOMMON": self = .uncommon
        case "PECULIAR": self = .riven
        default: self = .common
        }
    }

    var accent: Color {
        switch self {
        case .common: return Color(hex: "B87D55")
        case .uncommon: return Color(hex: "9FB4C7")
        case .rare: return WFTheme.gold
        case .legendary: return Color(hex: "D9E4EE")
        case .riven: return WFTheme.purple
        }
    }

    var backdrop: Color {
        switch self {
        case .common: return Color(hex: "221813")
        case .uncommon: return Color(hex: "16212B")
        case .rare: return Color(hex: "241E12")
        case .legendary: return Color(hex: "1D232A")
        case .riven: return Color(hex: "1F172B")
        }
    }

    var label: String {
        switch self {
        case .common: return "普通"
        case .uncommon: return "罕见"
        case .rare: return "稀有"
        case .legendary: return "传说"
        case .riven: return "裂罅"
        }
    }
}

/// Renders raw Mod / Arcane illustration art. Portrait full-card images bundled in `mod-icons/`
/// are cropped cleanly to their central illustration region so baked-in English card text never shows.
struct ModArtworkView: View {
    let rawName: String
    let isRiven: Bool

    var body: some View {
        let urls = resolvedURLs
#if canImport(UIKit)
        if let local = urls.local, let loaded = Self.loadCroppedArtwork(path: local.path) {
            Image(uiImage: loaded)
                .resizable()
                .scaledToFill()
        } else if let remote = urls.remote {
            AsyncImage(url: remote) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
#else
        fallbackArtwork
#endif
    }

    private var resolvedURLs: (local: URL?, remote: URL?) {
        if isRiven {
            return (
                NativeDamageCatalog.shared.localModIcon(named: "riven.webp"),
                URL(string: "https://warframe-damage.com/data/mods/riven.webp")
            )
        }
        return NativeDamageCatalog.shared.modIconURLs(forName: rawName)
    }

    private var fallbackArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1C2733"), Color(hex: "101720")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: isRiven ? "sparkles" : "rectangle.stack.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(WFTheme.textMuted.opacity(0.45))
        }
    }

#if canImport(UIKit)
    private static func loadCroppedArtwork(path: String) -> UIImage? {
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        // Bundled `mod-icons/` are ~175x256 portrait cards containing top drain text and
        // bottom English stat blocks. Cropping the upper window extracts clean artwork.
        guard height > width * 1.12, let cgImage = image.cgImage else {
            return image
        }
        let cw = CGFloat(cgImage.width)
        let ch = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: cw * 0.06,
            y: ch * 0.11,
            width: cw * 0.88,
            height: ch * 0.47
        ).integral
        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
#endif
}

/// Compact in-game horizontal Mod card tile for 2-column grids.
struct HorizontalModCardView: View {
    let card: ModCardPresentation

    var body: some View {
        let style = ModRarityStyle(card: card)
        ZStack {
            ModArtworkView(rawName: card.rawName, isRiven: card.isRiven)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: style.backdrop.opacity(0.40), location: 0.0),
                    .init(color: Color(hex: "0A0E16").opacity(0.84), location: 0.58),
                    .init(color: Color(hex: "070A10").opacity(0.95), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if let slotTag = card.slotTag, !slotTag.isEmpty {
                        Text(slotTag)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(style.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 4)
                    if let drain = card.effectiveDrain {
                        HStack(spacing: 2) {
                            Text(card.isPositiveCapacity ? "+\(drain)" : "\(drain)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                            polarityGlyph(card.metadata?.polarity ?? "")
                        }
                        .foregroundColor(card.isPositiveCapacity ? WFTheme.cyan : style.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.black.opacity(0.60))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else if card.metadata?.isArcane == true {
                        Text("赋能")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(style.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                    }
                }

                Spacer(minLength: 4)

                Text(card.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(WFTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, alignment: .center)

                if card.effectiveMaxRank > 0 {
                    rankPips(current: card.effectiveRank, max: card.effectiveMaxRank, accent: style.accent)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                } else {
                    Spacer().frame(height: 5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 66)
        .background(style.backdrop)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(style.accent.opacity(0.65), lineWidth: 1.2)
        )
    }

    @ViewBuilder
    private func rankPips(current: Int, max: Int, accent: Color) -> some View {
        let count = min(max, 10)
        HStack(spacing: count > 6 ? 2.5 : 3.5) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index < current ? Color(hex: "7FE6FF") : Color.white.opacity(0.20))
                    .frame(width: count > 6 ? 3.5 : 4.5, height: count > 6 ? 3.5 : 4.5)
                    .overlay(
                        Circle()
                            .stroke(index < current ? accent.opacity(0.4) : Color.clear, lineWidth: 0.5)
                    )
            }
        }
    }
}

/// Full in-game vertical Mod card sheet presented when tapping a horizontal card.
struct VerticalModCardModal: View {
    let card: ModCardPresentation
    var onReplace: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let style = ModRarityStyle(card: card)
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        verticalCard(style: style)
                            .frame(maxWidth: 300)
                            .padding(.top, 8)

                        if onReplace != nil || onRemove != nil {
                            HStack(spacing: 12) {
                                if let onReplace {
                                    Button {
                                        dismiss()
                                        onReplace()
                                    } label: {
                                        Label("更换 Mod", systemImage: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(Color(hex: "1A1408"))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(WFTheme.gold)
                                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                                if let onRemove {
                                    Button(role: .destructive) {
                                        dismiss()
                                        onRemove()
                                    } label: {
                                        Label("卸下", systemImage: "trash")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(WFTheme.red)
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 12)
                                            .background(WFTheme.panelElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: 300)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(WFTheme.gold)
                }
            }
        }
    }

    private func verticalCard(style: ModRarityStyle) -> some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Text(style.label)
                        .font(.system(size: 10.5, weight: .semibold))
                    if let slotTag = card.slotTag, !slotTag.isEmpty {
                        Text("· \(slotTag)")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }
                .foregroundColor(style.accent)
                Spacer()
                if let drain = card.effectiveDrain {
                    HStack(spacing: 3) {
                        Text(card.isPositiveCapacity ? "+\(drain)" : "\(drain)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        polarityGlyph(card.metadata?.polarity ?? "")
                    }
                    .foregroundColor(card.isPositiveCapacity ? WFTheme.cyan : style.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ModArtworkView(rawName: card.rawName, isRiven: card.isRiven)
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(style.accent.opacity(0.45), lineWidth: 1)
                )
                .padding(.horizontal, 12)

            VStack(spacing: 10) {
                Text(card.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(style.accent)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)

                VStack(spacing: 5) {
                    ForEach(Array(card.effectLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(WFTheme.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

                Text(card.compatLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(WFTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())

                if card.effectiveMaxRank > 0 {
                    HStack(spacing: 5) {
                        ForEach(0..<min(card.effectiveMaxRank, 10), id: \.self) { index in
                            Circle()
                                .fill(index < card.effectiveRank ? Color(hex: "7FE6FF") : Color.white.opacity(0.22))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top, 2)
                    Text("等级 \(card.effectiveRank) / \(card.effectiveMaxRank)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WFTheme.textMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                colors: [style.backdrop, Color(hex: "0C111A"), style.backdrop.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style.accent.opacity(0.85), lineWidth: 2)
        )
        .shadow(color: style.accent.opacity(0.20), radius: 16, y: 8)
    }
}

@ViewBuilder
private func polarityGlyph(_ polarity: String) -> some View {
    switch polarity {
    case "Madurai":
        Text("V").font(.system(size: 10, weight: .black))
    case "Vazarin":
        Text("D").font(.system(size: 10, weight: .black))
    case "Naramon":
        Text("—").font(.system(size: 10, weight: .black))
    case "Zenurik":
        Text("═").font(.system(size: 10, weight: .black))
    case "Unairu":
        Text("R").font(.system(size: 10, weight: .black))
    case "Penjaga":
        Text("Y").font(.system(size: 10, weight: .black))
    case "Umbra":
        Text("U").font(.system(size: 10, weight: .black))
    default:
        EmptyView()
    }
}
