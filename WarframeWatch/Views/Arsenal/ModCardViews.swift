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

    var isArcane: Bool {
        metadata?.isArcane == true
    }

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
        if metadata.isArcane || (metadata.baseDrain == 0 && effectiveMaxRank == 0) {
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
        return isArcane ? "赋能" : "升级 Mod"
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

private enum ModFrameTier: String {
    case bronze = "Bronze"
    case silver = "Silver"
    case gold = "Gold"
    case legendary = "Legendary"
    case galvanized = "Galvanized"
    case amalgam = "Amalgam"
    case omega = "Omega"

    init(card: ModCardPresentation) {
        if card.isRiven {
            self = .omega
            return
        }
        if let explicit = card.metadata?.frameTier, let matched = ModFrameTier(rawValue: explicit) {
            self = matched
            return
        }
        switch card.metadata?.rarity.uppercased() {
        case "LEGENDARY": self = .legendary
        case "RARE": self = .gold
        case "UNCOMMON": self = .silver
        default: self = .bronze
        }
    }

    var hasHorizontalOverhang: Bool {
        self == .galvanized || self == .amalgam || self == .omega
    }

    var topFrameImageName: String { "\(rawValue)FrameTop.png" }
    var bottomFrameImageName: String { "\(rawValue)FrameBottom.png" }

    var backgroundImageName: String {
        switch self {
        case .omega: return "LegendaryBackground.png"
        default: return "\(rawValue)Background.png"
        }
    }

    var sideLightImageName: String { "\(rawValue)SideLight.png" }

    var cornerLightsImageName: String {
        switch self {
        case .galvanized, .amalgam: return "SilverCornerLights.png"
        default: return "\(rawValue)CornerLights.png"
        }
    }

    var topRightBackerImageName: String {
        switch self {
        case .omega: return "RivenTopRightBacker.png"
        case .galvanized, .amalgam: return "SilverTopRightBacker.png"
        default: return "\(rawValue)TopRightBacker.png"
        }
    }

    var lowerTabImageName: String {
        switch self {
        case .omega: return "RivenLowerTab.png"
        case .galvanized, .amalgam: return "SilverLowerTab.png"
        default: return "\(rawValue)LowerTab.png"
        }
    }

    var textColor: Color {
        switch self {
        case .bronze: return Color(hex: "F3E2D8")
        case .silver, .legendary, .galvanized, .amalgam: return .white
        case .gold: return Color(hex: "FAE7BE")
        case .omega: return Color(hex: "D4BAFF")
        }
    }

    var accentColor: Color {
        switch self {
        case .bronze: return Color(hex: "CA9A87")
        case .silver: return Color(hex: "C8D6E2")
        case .gold: return Color(hex: "F5D18A")
        case .legendary: return Color(hex: "E6EEF5")
        case .galvanized: return Color(hex: "9FD3F5")
        case .amalgam: return Color(hex: "BBD4EB")
        case .omega: return Color(hex: "C89EFF")
        }
    }

    var backdropColor: Color {
        switch self {
        case .bronze: return Color(hex: "201510")
        case .silver: return Color(hex: "141D26")
        case .gold: return Color(hex: "231C10")
        case .legendary: return Color(hex: "1A2128")
        case .galvanized: return Color(hex: "131F2C")
        case .amalgam: return Color(hex: "16222E")
        case .omega: return Color(hex: "1C1329")
        }
    }
}

#if canImport(UIKit)
@MainActor
private enum ModAssetImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        return c
    }()

    static func image(at url: URL?) -> UIImage? {
        guard let url else { return nil }
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) {
            return hit
        }
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    static func frameImage(named fileName: String) -> UIImage? {
        image(at: NativeDamageCatalog.shared.localModFrame(named: fileName))
    }

    static func polarityImage(named polarity: String) -> UIImage? {
        image(at: NativeDamageCatalog.shared.localPolarityIcon(named: polarity))
    }
}
#endif

/// Renders raw Mod / Arcane illustration art. High-resolution `mod-art/` illustrations
/// render uncropped cleanly; any legacy portrait `mod-icons/` fallback strips baked-in text.
struct ModArtworkView: View {
    let rawName: String
    let isRiven: Bool
    var contentMode: ContentMode = .fill

    var body: some View {
        Color.clear
            .overlay(artworkLayer)
            .clipped()
    }

    @ViewBuilder
    private var artworkLayer: some View {
        let urls = resolvedURLs
#if canImport(UIKit)
        if let local = urls.local, let loaded = loadDisplayImage(url: local) {
            Image(uiImage: loaded)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let remote = urls.remote {
            AsyncImage(url: remote) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: contentMode)
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
            if let omegaArt = NativeDamageCatalog.shared.localModArt(named: "OmegaMod.webp") {
                return (omegaArt, nil)
            }
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
    private func loadDisplayImage(url: URL) -> UIImage? {
        if url.path.contains("/mod-art/") {
            return ModAssetImageCache.image(at: url)
        }
        return Self.loadCroppedArtwork(path: url.path)
    }

    static func loadCroppedArtwork(path: String) -> UIImage? {
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard height > width * 1.12, let cgImage = image.cgImage else {
            return image
        }
        let cw = CGFloat(cgImage.width)
        let ch = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: cw * 0.06,
            y: ch * 0.11,
            width: cw * 0.88,
            height: ch * 0.19
        ).integral
        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
#endif
}

@MainActor
@ViewBuilder
private func deFrameImage(_ fileName: String, contentMode: ContentMode = .fit) -> some View {
#if canImport(UIKit)
    if let img = ModAssetImageCache.frameImage(named: fileName) {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: contentMode)
    }
#endif
}

@MainActor
@ViewBuilder
private func dePolarityView(_ polarity: String, tint: Color, size: CGFloat) -> some View {
#if canImport(UIKit)
    if let img = ModAssetImageCache.polarityImage(named: polarity) {
        Image(uiImage: img)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(tint)
            .frame(width: size, height: size)
    } else {
        fallbackPolarityText(polarity, tint: tint, size: size)
    }
#else
    fallbackPolarityText(polarity, tint: tint, size: size)
#endif
}

@ViewBuilder
private func fallbackPolarityText(_ polarity: String, tint: Color, size: CGFloat) -> some View {
    switch polarity {
    case "Madurai":
        Text("V").font(.system(size: size * 0.9, weight: .black)).foregroundColor(tint)
    case "Vazarin":
        Text("D").font(.system(size: size * 0.9, weight: .black)).foregroundColor(tint)
    case "Naramon":
        Text("—").font(.system(size: size * 0.9, weight: .black)).foregroundColor(tint)
    case "Zenurik":
        Text("═").font(.system(size: size * 0.9, weight: .black)).foregroundColor(tint)
    case "Unairu":
        Text("R").font(.system(size: size * 0.9, weight: .black)).foregroundColor(tint)
    case "Penjaga":
        Text("Y").font(.system(size: size * 0.9, weight: .black)).foregroundColor(tint)
    case "Umbra":
        Text("U").font(.system(size: size * 0.9, weight: .black)).foregroundColor(tint)
    default:
        EmptyView()
    }
}

@MainActor
@ViewBuilder
private func deRankBar(current: Int, maxRank: Int, dotSize: CGFloat, spacing: CGFloat, lineWidth: CGFloat) -> some View {
    let count = min(maxRank, 10)
    ZStack {
        if maxRank > 0 && current >= maxRank {
            deFrameImage("RankCompleteLine.png", contentMode: .fill)
                .frame(width: lineWidth, height: max(3, dotSize * 0.55))
                .opacity(0.95)
        }
        if count > 0 {
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    deFrameImage(
                        index < current ? "RankSlotActive.png" : "RankSlotEmpty.png",
                        contentMode: .fit
                    )
                    .frame(width: dotSize, height: dotSize)
                }
            }
        }
    }
}

/// Compact in-game horizontal Mod / Arcane tile for 2-column grids.
struct HorizontalModCardView: View {
    let card: ModCardPresentation

    var body: some View {
        if card.isArcane {
            arcaneTile
        } else {
            modTile
        }
    }

    private var modTile: some View {
        let tier = ModFrameTier(card: card)
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let hInset: CGFloat = tier.hasHorizontalOverhang ? 4 : 1.5
            let innerW = max(40, w - hInset * 2)
            let vInset: CGFloat = tier == .galvanized ? 6 : 3
            let drainTint = card.isPositiveCapacity ? Color(hex: "77E494") : tier.textColor

            ZStack {
                // 1. Inner high-res illustration clipped cleanly inside frame boundaries
                ZStack {
                    tier.backdropColor
                    ModArtworkView(rawName: card.rawName, isRiven: card.isRiven, contentMode: .fill)
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(0.24), location: 0.0),
                            .init(color: Color.black.opacity(0.42), location: 0.48),
                            .init(color: Color.black.opacity(0.84), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    HStack {
                        deFrameImage(tier.sideLightImageName, contentMode: .fill)
                            .frame(width: 6)
                            .opacity(0.75)
                        Spacer()
                        deFrameImage(tier.sideLightImageName, contentMode: .fill)
                            .frame(width: 6)
                            .scaleEffect(x: -1, y: 1)
                            .opacity(0.75)
                    }
                }
                .frame(width: innerW, height: max(36, h - vInset * 2))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // 2. DE genuine metallic Top & Bottom sprite frames
                VStack(spacing: 0) {
                    deFrameImage(tier.topFrameImageName, contentMode: .fit)
                        .frame(width: tier.hasHorizontalOverhang ? w : innerW)
                    Spacer(minLength: 0)
                    deFrameImage(tier.bottomFrameImageName, contentMode: .fit)
                        .frame(width: tier.hasHorizontalOverhang ? w : innerW)
                }
                .frame(width: w, height: h)
                .allowsHitTesting(false)

                // 3. Optional Set Mod top emblem (Hunter, Augur, Gladiator, Umbra, etc.)
                if let modSet = card.metadata?.modSet, !modSet.isEmpty {
                    VStack {
                        deFrameImage("\(modSet)Header.png", contentMode: .fit)
                            .frame(width: innerW * 0.44)
                            .offset(y: -1)
                        Spacer()
                    }
                    .frame(width: w, height: h)
                    .allowsHitTesting(false)
                }

                // 4. Optional Aura/Stance/Exilus pill + Top-Right DE drain backer with polarity PNG
                VStack {
                    HStack(alignment: .top, spacing: 4) {
                        if let slotTag = card.slotTag, !slotTag.isEmpty, slotTag != "赋能" {
                            Text(slotTag)
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(tier.textColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.black.opacity(0.72))
                                .clipShape(Capsule())
                        }
                        Spacer(minLength: 2)
                        if let drain = card.effectiveDrain {
                            ZStack {
                                deFrameImage(tier.topRightBackerImageName, contentMode: .fill)
                                HStack(spacing: 2) {
                                    Text(card.isPositiveCapacity ? "+\(drain)" : "\(drain)")
                                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                        .foregroundColor(drainTint)
                                    dePolarityView(card.metadata?.polarity ?? "", tint: drainTint, size: 10.5)
                                }
                                .padding(.horizontal, 4)
                            }
                            .frame(width: 36, height: 21)
                        }
                    }
                    .padding(.horizontal, hInset + 4)
                    .padding(.top, vInset + 5)
                    Spacer()
                }
                .frame(width: w, height: h)

                // 5. Official Chinese title + DE diamond rank bar
                VStack(spacing: 0) {
                    Spacer(minLength: 14)
                    Text(card.displayName)
                        .font(.system(size: card.isRiven ? 11.5 : 13, weight: .semibold))
                        .foregroundColor(tier.textColor)
                        .shadow(color: Color.black.opacity(0.95), radius: 2, y: 1)
                        .lineLimit(card.isRiven ? 2 : 1)
                        .minimumScaleFactor(0.72)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, hInset + 8)
                        .padding(.bottom, 5)

                    if card.effectiveMaxRank > 0 {
                        deRankBar(
                            current: card.effectiveRank,
                            maxRank: card.effectiveMaxRank,
                            dotSize: card.effectiveMaxRank > 6 ? 7 : 8,
                            spacing: card.effectiveMaxRank > 6 ? 1.5 : 2.5,
                            lineWidth: innerW * 0.84
                        )
                        .padding(.bottom, vInset + 2)
                    } else {
                        Spacer().frame(height: vInset + 9)
                    }
                }
                .frame(width: w, height: h)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 82)
    }

    private var arcaneTile: some View {
        let tier = ModFrameTier(card: card)
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tier.accentColor.opacity(0.28), Color(hex: "080D14")],
                            center: .center,
                            startRadius: 2,
                            endRadius: 26
                        )
                    )
                ModArtworkView(rawName: card.rawName, isRiven: false, contentMode: .fit)
                    .padding(5)
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(tier.accentColor.opacity(0.75), lineWidth: 1.4)
            )
            .shadow(color: tier.accentColor.opacity(0.22), radius: 5)

            VStack(alignment: .leading, spacing: 5) {
                Text(card.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tier.textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 6) {
                    Text("赋能")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(tier.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(tier.accentColor.opacity(0.14))
                        .clipShape(Capsule())

                    if card.effectiveMaxRank > 0 {
                        deRankBar(
                            current: card.effectiveRank,
                            maxRank: card.effectiveMaxRank,
                            dotSize: 8,
                            spacing: 2,
                            lineWidth: 56
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .background(
            LinearGradient(
                colors: [tier.backdropColor.opacity(0.92), Color(hex: "090E15")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tier.accentColor.opacity(0.42), lineWidth: 1)
        )
    }
}

/// Full in-game vertical Mod / Arcane sheet presented when tapping a horizontal card.
struct VerticalModCardModal: View {
    let card: ModCardPresentation
    var onReplace: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let tier = ModFrameTier(card: card)
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        if card.isArcane {
                            verticalArcaneCard(tier: tier)
                                .frame(width: 276)
                                .padding(.top, 10)
                        } else {
                            verticalModCard(tier: tier)
                                .frame(width: 280, height: 428)
                                .padding(.top, 10)
                        }

                        if card.effectiveMaxRank > 0 {
                            Text("等级 \(card.effectiveRank) / \(card.effectiveMaxRank)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(WFTheme.textSecondary)
                        }

                        if onReplace != nil || onRemove != nil {
                            HStack(spacing: 12) {
                                if let onReplace {
                                    Button {
                                        dismiss()
                                        onReplace()
                                    } label: {
                                        Label("更换", systemImage: "arrow.triangle.2.circlepath")
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
                            .frame(width: 280)
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

    private func verticalModCard(tier: ModFrameTier) -> some View {
        let cardWidth: CGFloat = 280
        let hInset: CGFloat = tier.hasHorizontalOverhang ? 12 : 4
        let innerW = cardWidth - hInset * 2
        let drainTint = card.isPositiveCapacity ? Color(hex: "77E494") : tier.textColor

        return ZStack {
            // 1. Background texture + upper crisp Mod art + dark lower text panel
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    ModArtworkView(rawName: card.rawName, isRiven: card.isRiven, contentMode: .fill)
                        .frame(width: innerW, height: 196)
                    LinearGradient(
                        colors: [.clear, tier.backdropColor.opacity(0.95)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: 56)
                }
                .clipped()

                ZStack {
                    deFrameImage(tier.backgroundImageName, contentMode: .fill)
                        .opacity(0.55)
                    LinearGradient(
                        colors: [tier.backdropColor.opacity(0.88), Color(hex: "090D14").opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: innerW)
                .frame(maxHeight: .infinity)
                .clipped()
            }
            .frame(width: innerW, height: 404)
            .background(tier.backdropColor)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // 2. Side lights + corner lights
            HStack {
                deFrameImage(tier.sideLightImageName, contentMode: .fill)
                    .frame(width: 12, height: 360)
                Spacer()
                deFrameImage(tier.sideLightImageName, contentMode: .fill)
                    .frame(width: 12, height: 360)
                    .scaleEffect(x: -1, y: 1)
            }
            .frame(width: innerW)
            .allowsHitTesting(false)

            // 3. Top & bottom DE metallic frame PNGs
            VStack(spacing: 0) {
                deFrameImage(tier.topFrameImageName, contentMode: .fit)
                    .frame(width: tier.hasHorizontalOverhang ? cardWidth : innerW)
                Spacer()
                deFrameImage(tier.bottomFrameImageName, contentMode: .fit)
                    .frame(width: tier.hasHorizontalOverhang ? cardWidth : innerW)
            }
            .frame(width: cardWidth, height: 428)
            .allowsHitTesting(false)

            // 4. Optional Set emblem
            if let modSet = card.metadata?.modSet, !modSet.isEmpty {
                VStack {
                    deFrameImage("\(modSet)Header.png", contentMode: .fit)
                        .frame(width: 112)
                        .offset(y: -2)
                    Spacer()
                }
                .frame(width: cardWidth, height: 428)
                .allowsHitTesting(false)
            }

            // 5. Top-right DE drain + polarity backer
            VStack {
                HStack {
                    if let slotTag = card.slotTag, !slotTag.isEmpty, slotTag != "赋能" {
                        Text(slotTag)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(tier.textColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(Color.black.opacity(0.68))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if let drain = card.effectiveDrain {
                        ZStack {
                            deFrameImage(tier.topRightBackerImageName, contentMode: .fill)
                            HStack(spacing: 3) {
                                Text(card.isPositiveCapacity ? "+\(drain)" : "\(drain)")
                                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                    .foregroundColor(drainTint)
                                dePolarityView(card.metadata?.polarity ?? "", tint: drainTint, size: 13)
                            }
                            .padding(.horizontal, 6)
                        }
                        .frame(width: 52, height: 29)
                    }
                }
                .padding(.horizontal, hInset + 10)
                .padding(.top, 26)
                Spacer()
            }
            .frame(width: cardWidth, height: 428)

            // 6. Chinese title, rank-exact effect description, compat tab & rank dots
            VStack(spacing: 8) {
                Spacer().frame(height: 186)

                Text(card.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(tier.textColor)
                    .shadow(color: Color.black.opacity(0.95), radius: 2, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)

                VStack(spacing: 5) {
                    ForEach(Array(card.effectLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.94))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 4)

                ZStack {
                    deFrameImage(tier.lowerTabImageName, contentMode: .fit)
                        .frame(width: innerW * 0.78)
                    Text(card.compatLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tier.textColor)
                }
                .padding(.bottom, 4)

                if card.effectiveMaxRank > 0 {
                    deRankBar(
                        current: card.effectiveRank,
                        maxRank: card.effectiveMaxRank,
                        dotSize: card.effectiveMaxRank > 6 ? 10 : 12,
                        spacing: card.effectiveMaxRank > 6 ? 2.5 : 4,
                        lineWidth: innerW * 0.84
                    )
                    .padding(.bottom, 20)
                } else {
                    Spacer().frame(height: 22)
                }
            }
            .frame(width: innerW, height: 428)
        }
        .shadow(color: tier.accentColor.opacity(0.25), radius: 18, y: 8)
    }

    private func verticalArcaneCard(tier: ModFrameTier) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tier.accentColor.opacity(0.35), Color(hex: "090E16")],
                            center: .center,
                            startRadius: 8,
                            endRadius: 64
                        )
                    )
                ModArtworkView(rawName: card.rawName, isRiven: false, contentMode: .fit)
                    .padding(12)
            }
            .frame(width: 118, height: 118)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(tier.accentColor.opacity(0.85), lineWidth: 2)
            )
            .shadow(color: tier.accentColor.opacity(0.28), radius: 12)
            .padding(.top, 10)

            Text(card.displayName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(tier.textColor)
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                ForEach(Array(card.effectLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.94))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10)

            Text(card.compatLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tier.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(tier.accentColor.opacity(0.14))
                .clipShape(Capsule())

            if card.effectiveMaxRank > 0 {
                deRankBar(
                    current: card.effectiveRank,
                    maxRank: card.effectiveMaxRank,
                    dotSize: 12,
                    spacing: 4,
                    lineWidth: 160
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [tier.backdropColor, Color(hex: "080C12"), tier.backdropColor.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tier.accentColor.opacity(0.75), lineWidth: 1.5)
        )
        .shadow(color: tier.accentColor.opacity(0.22), radius: 16, y: 8)
    }
}
