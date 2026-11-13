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

    var compactTopFrameImageName: String {
        hasHorizontalOverhang ? "\(rawValue)FrameTopCompact.png" : "\(rawValue)FrameTopTrimmed.png"
    }

    var compactBottomFrameImageName: String {
        hasHorizontalOverhang ? "\(rawValue)FrameBottomCompact.png" : "\(rawValue)FrameBottomTrimmed.png"
    }

    var backgroundImageName: String {
        switch self {
        case .omega: return "LegendaryBackgroundTrimmed.png"
        default: return "\(rawValue)BackgroundTrimmed.png"
        }
    }

    var glassTintColor: Color {
        switch self {
        case .bronze: return Color(hex: "BA7352")
        case .silver: return Color(hex: "73A3CA")
        case .gold: return Color(hex: "D8A84B")
        case .legendary: return Color(hex: "BDD0E2")
        case .galvanized: return Color(hex: "66A6DF")
        case .amalgam: return Color(hex: "8FB4D8")
        case .omega: return Color(hex: "985AE2")
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
            if let omegaBackdrop = NativeDamageCatalog.shared.localModFrame(named: "OmegaInnerBackdrop.png") {
                return (omegaBackdrop, nil)
            }
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
        if url.path.contains("/mod-art/")
            || url.path.contains("/arcane-icons/")
            || url.path.contains("/mod-frames/") {
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
                .clipped()
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

/// Compact in-game horizontal Mod / Arcane tile for 2-column grids (strict 2:1 DE card ratio).
struct HorizontalModCardView: View {
    let card: ModCardPresentation

    var body: some View {
        Group {
            if card.isArcane {
                arcaneTile
            } else {
                modTile
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(2.0, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
    }

    private var modTile: some View {
        let tier = ModFrameTier(card: card)
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let hInset: CGFloat = tier.hasHorizontalOverhang ? 2 : 1
            let innerW = max(40, w - hInset * 2)
            let innerH = max(24, h - 2)
            let frameW = tier.hasHorizontalOverhang ? w : innerW
            let drainTint = card.isPositiveCapacity ? Color(hex: "77E494") : tier.textColor

            ZStack {
                // 1. Inner high-res illustration + DE glass tint + glass glow, shaped by ModGlassMask
                maskedWithModGlass(
                    ZStack {
                        tier.backdropColor
                        ModArtworkView(rawName: card.rawName, isRiven: card.isRiven, contentMode: .fill)
                            .frame(width: innerW, height: innerH)
                            .clipped()

                        // Subtle ambient rarity glass tint ("底色混色")
                        tier.glassTintColor.opacity(card.isRiven ? 0.14 : 0.24)
                            .blendMode(.screen)

                        // Bottom vignette for crisp Chinese title contrast
                        LinearGradient(
                            stops: [
                                .init(color: Color.black.opacity(0.08), location: 0.0),
                                .init(color: Color.black.opacity(0.36), location: 0.52),
                                .init(color: Color.black.opacity(0.84), location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        // DE glass sheen overlay
                        deFrameImage("ModGlassGlowTrimmed.png", contentMode: .fill)
                            .frame(width: innerW, height: innerH)
                            .clipped()
                            .opacity(0.34)
                            .blendMode(.plusLighter)

                        // Vertical edge light rails
                        HStack(spacing: 0) {
                            deFrameImage(tier.sideLightImageName, contentMode: .fill)
                                .frame(width: 6, height: innerH)
                                .clipped()
                                .opacity(0.75)
                            Spacer(minLength: 0)
                            deFrameImage(tier.sideLightImageName, contentMode: .fill)
                                .frame(width: 6, height: innerH)
                                .clipped()
                                .scaleEffect(x: -1, y: 1)
                                .opacity(0.75)
                        }
                    }
                    .frame(width: innerW, height: innerH),
                    width: innerW,
                    height: innerH
                )
                .allowsHitTesting(false)

                // 2. Full-width DE metallic Top & Bottom compact frames (aligned independently in ZStack)
                ZStack(alignment: .top) {
                    Color.clear
                    deFrameImage(tier.compactTopFrameImageName, contentMode: .fit)
                        .frame(width: frameW)
                }
                .frame(width: w, height: h)
                .allowsHitTesting(false)

                ZStack(alignment: .bottom) {
                    Color.clear
                    deFrameImage(tier.compactBottomFrameImageName, contentMode: .fit)
                        .frame(width: frameW)
                }
                .frame(width: w, height: h)
                .allowsHitTesting(false)

                // 3. Optional Set Mod top emblem
                if let modSet = card.metadata?.modSet, !modSet.isEmpty {
                    ZStack(alignment: .top) {
                        Color.clear
                        deFrameImage("\(modSet)Header.png", contentMode: .fit)
                            .frame(width: innerW * 0.44)
                            .offset(y: -1)
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
                            .clipped()
                        }
                    }
                    .padding(.horizontal, hInset + 5)
                    .padding(.top, 6)
                    Spacer()
                }
                .frame(width: w, height: h)
                .allowsHitTesting(false)

                // 5. Official Chinese title + DE diamond rank bar
                VStack(spacing: 0) {
                    Spacer(minLength: 14)
                    Text(card.displayName)
                        .font(.system(size: card.isRiven ? 11 : 12.5, weight: .semibold))
                        .foregroundColor(tier.textColor)
                        .shadow(color: Color.black.opacity(0.95), radius: 2.5, y: 1)
                        .lineLimit(card.isRiven ? 2 : 1)
                        .minimumScaleFactor(0.72)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, hInset + 10)
                        .padding(.bottom, tier == .legendary ? 7 : 5)

                    if card.effectiveMaxRank > 0 {
                        deRankBar(
                            current: card.effectiveRank,
                            maxRank: card.effectiveMaxRank,
                            dotSize: card.effectiveMaxRank > 6 ? 6.5 : 7.5,
                            spacing: card.effectiveMaxRank > 6 ? 1.5 : 2.5,
                            lineWidth: innerW * 0.82
                        )
                        .padding(.bottom, 3)
                    } else {
                        Spacer().frame(height: 10)
                    }
                }
                .frame(width: w, height: h)
                .allowsHitTesting(false)
            }
            .frame(width: w, height: h)
        }
    }

    private var arcaneTile: some View {
        let tier = ModFrameTier(card: card)
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            HStack(spacing: 8) {
                ZStack {
                    RadialGradient(
                        colors: [tier.accentColor.opacity(0.28), Color.clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: h * 0.48
                    )
                    ModArtworkView(rawName: card.rawName, isRiven: false, contentMode: .fit)
                        .frame(width: min(74, w * 0.44), height: max(36, h - 14))
                }
                .frame(width: min(76, w * 0.45), height: max(38, h - 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text(card.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(tier.textColor)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    HStack(spacing: 5) {
                        Text("赋能")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(tier.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(tier.accentColor.opacity(0.16))
                            .clipShape(Capsule())

                        if card.effectiveMaxRank > 0 {
                            deRankBar(
                                current: card.effectiveRank,
                                maxRank: card.effectiveMaxRank,
                                dotSize: 7.5,
                                spacing: 1.5,
                                lineWidth: 50
                            )
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: w, height: h)
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
                    .strokeBorder(tier.accentColor.opacity(0.45), lineWidth: 1)
            )
        }
    }
}

@MainActor
@ViewBuilder
private func maskedWithModGlass<Content: View>(_ content: Content, width: CGFloat, height: CGFloat) -> some View {
#if canImport(UIKit)
    if let maskImg = ModAssetImageCache.frameImage(named: "ModGlassMaskTrimmed.png") {
        content.mask(
            Image(uiImage: maskImg)
                .resizable()
                .frame(width: width, height: height)
        )
    } else {
        content.clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
#else
    content.clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
#endif
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
        let hInset: CGFloat = tier.hasHorizontalOverhang ? 10 : 4
        let innerW = cardWidth - hInset * 2
        let frameW = tier.hasHorizontalOverhang ? cardWidth : innerW
        let drainTint = card.isPositiveCapacity ? Color(hex: "77E494") : tier.textColor

        return ZStack {
            // 1. DE textured carbon-diamond background + upper Mod illustration fading into the weave
            ZStack(alignment: .top) {
                tier.backdropColor
                deFrameImage(tier.backgroundImageName, contentMode: .fill)
                    .frame(width: innerW, height: 404)
                    .clipped()

                ModArtworkView(rawName: card.rawName, isRiven: card.isRiven, contentMode: .fill)
                    .frame(width: innerW, height: 224)
                    .clipped()
                    .overlay(
                        tier.glassTintColor.opacity(card.isRiven ? 0.10 : 0.16)
                            .blendMode(.screen)
                    )
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0.0),
                                .init(color: .white, location: 0.56),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: innerW, height: 404)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // 2. Side lights + corner lights
            HStack {
                deFrameImage(tier.sideLightImageName, contentMode: .fill)
                    .frame(width: 12, height: 356)
                    .clipped()
                Spacer()
                deFrameImage(tier.sideLightImageName, contentMode: .fill)
                    .frame(width: 12, height: 356)
                    .clipped()
                    .scaleEffect(x: -1, y: 1)
            }
            .frame(width: innerW)
            .allowsHitTesting(false)

            ZStack(alignment: .topLeading) {
                Color.clear
                deFrameImage(tier.cornerLightsImageName, contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .opacity(0.65)
            }
            .frame(width: innerW, height: 404)
            .allowsHitTesting(false)

            // 3. Full-width DE Top & Bottom vertical frames (anchored independently in ZStack)
            ZStack(alignment: .top) {
                Color.clear
                deFrameImage(tier.topFrameImageName, contentMode: .fit)
                    .frame(width: frameW)
            }
            .frame(width: cardWidth, height: 428)
            .allowsHitTesting(false)

            ZStack(alignment: .bottom) {
                Color.clear
                deFrameImage(tier.bottomFrameImageName, contentMode: .fit)
                    .frame(width: frameW)
            }
            .frame(width: cardWidth, height: 428)
            .allowsHitTesting(false)

            // 4. Optional Set emblem
            if let modSet = card.metadata?.modSet, !modSet.isEmpty {
                ZStack(alignment: .top) {
                    Color.clear
                    deFrameImage("\(modSet)Header.png", contentMode: .fit)
                        .frame(width: 112)
                        .offset(y: -2)
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
                        .clipped()
                    }
                }
                .padding(.horizontal, hInset + 10)
                .padding(.top, 26)
                Spacer()
            }
            .frame(width: cardWidth, height: 428)

            // 6. Chinese title, rank-exact effect description, compat tab & rank dots
            VStack(spacing: 8) {
                Spacer().frame(height: 192)

                Text(card.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(tier.textColor)
                    .shadow(color: Color.black.opacity(0.95), radius: 2.5, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)

                VStack(spacing: 5) {
                    ForEach(Array(card.effectLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.95))
                            .shadow(color: Color.black.opacity(0.85), radius: 1.5, y: 1)
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
        VStack(spacing: 14) {
            ZStack {
                RadialGradient(
                    colors: [tier.accentColor.opacity(0.32), Color.clear],
                    center: .center,
                    startRadius: 10,
                    endRadius: 84
                )
                ModArtworkView(rawName: card.rawName, isRiven: false, contentMode: .fit)
                    .frame(width: 175, height: 126)
            }
            .frame(width: 196, height: 140)
            .shadow(color: tier.accentColor.opacity(0.28), radius: 12)
            .padding(.top, 8)

            Text(card.displayName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(tier.textColor)
                .multilineTextAlignment(.center)

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
            .padding(.top, 2)
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
