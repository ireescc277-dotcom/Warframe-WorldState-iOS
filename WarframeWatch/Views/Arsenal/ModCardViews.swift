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
    case arcane = "Arcane"

    init(card: ModCardPresentation) {
        if card.isRiven {
            self = .omega
            return
        }
        if card.isArcane {
            self = .arcane
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

    var topFrameImageName: String {
        self == .arcane ? "LegendaryFrameTop.png" : "\(rawValue)FrameTop.png"
    }

    var bottomFrameImageName: String {
        self == .arcane ? "LegendaryFrameBottom.png" : "\(rawValue)FrameBottom.png"
    }

    /// Native widths of the full-height frame assets, shared by both
    /// portrait and horizontal overhang cards so side pylons connect seamlessly.
    var frameTopNativeWidth: CGFloat {
        switch self {
        case .galvanized, .amalgam: return 288
        case .omega: return 281
        default: return 256
        }
    }

    var frameBottomNativeWidth: CGFloat {
        switch self {
        case .galvanized, .amalgam: return 288
        case .omega: return 292
        default: return 256
        }
    }

    var sideLightNativeWidth: CGFloat {
        self == .galvanized ? 32 : 16
    }

    var backgroundImageName: String {
        switch self {
        case .omega, .arcane: return "LegendaryBackgroundTrimmed.png"
        default: return "\(rawValue)BackgroundTrimmed.png"
        }
    }

    var glassTintColor: Color {
        switch self {
        case .bronze: return Color(hex: "C47248")
        case .silver: return Color(hex: "4C7FE0")
        case .gold: return Color(hex: "DFA93E")
        case .legendary: return Color(hex: "3896B0")
        case .galvanized: return Color(hex: "4E82DC")
        case .amalgam: return Color(hex: "689AD8")
        case .omega: return Color(hex: "985AE2")
        case .arcane: return Color(hex: "8CC8D6")
        }
    }

    var sideLightImageName: String {
        self == .arcane ? "LegendarySideLight.png" : "\(rawValue)SideLight.png"
    }

    var cornerLightsImageName: String {
        switch self {
        case .galvanized, .amalgam: return "SilverCornerLights.png"
        case .arcane: return "LegendaryCornerLights.png"
        default: return "\(rawValue)CornerLights.png"
        }
    }

    var topRightBackerImageName: String {
        switch self {
        case .omega: return "RivenTopRightBacker.png"
        case .galvanized, .amalgam: return "SilverTopRightBacker.png"
        case .arcane: return "LegendaryTopRightBacker.png"
        default: return "\(rawValue)TopRightBacker.png"
        }
    }

    var lowerTabImageName: String {
        switch self {
        case .omega: return "RivenLowerTab.png"
        case .galvanized, .amalgam: return "SilverLowerTab.png"
        case .arcane: return "LegendaryLowerTab.png"
        default: return "\(rawValue)LowerTab.png"
        }
    }

    var textColor: Color {
        switch self {
        case .bronze: return Color(hex: "F3E2D8")
        case .silver, .legendary, .galvanized, .amalgam, .arcane: return .white
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
        case .arcane: return Color(hex: "B8E8E9")
        }
    }

    var backdropColor: Color {
        switch self {
        case .bronze: return Color(hex: "201510")
        case .silver: return Color(hex: "141D26")
        case .gold: return Color(hex: "231C10")
        case .legendary: return Color(hex: "102026")
        case .galvanized: return Color(hex: "131F2C")
        case .amalgam: return Color(hex: "16222E")
        case .omega: return Color(hex: "120F1A")
        case .arcane: return Color(hex: "0D171C")
        }
    }

    var horizontalTopY: CGFloat {
        switch self {
        case .galvanized: return -19.0
        case .amalgam: return -10.0
        case .omega: return -12.0
        default: return -11.0
        }
    }

    var horizontalBottomTopY: CGFloat {
        switch self {
        case .galvanized: return 16.0
        case .amalgam: return 40.0
        case .omega: return 14.0
        default: return 21.0
        }
    }

    var horizontalGlassOriginY: CGFloat {
        switch self {
        case .omega: return 2.0
        default: return 1.0
        }
    }

    var horizontalGlassHeight: CGFloat {
        switch self {
        case .galvanized: return 126.0
        case .omega: return 124.0
        default: return 128.0
        }
    }

    var horizontalRankY: CGFloat {
        switch self {
        case .galvanized: return 119.5
        case .amalgam: return 118.0
        case .omega: return 118.5
        default: return 118.6
        }
    }

    var horizontalCapacityTrailingX: CGFloat {
        switch self {
        case .galvanized: return 251.5
        case .amalgam: return 252.0
        case .omega: return 249.0
        default: return 249.4
        }
    }

    var horizontalTitleColor: Color {
        switch self {
        case .omega: return Color(hex: "C9A6FF")
        case .gold: return Color(hex: "EFE3C4")
        case .bronze: return Color(hex: "EDE0D8")
        default: return Color(hex: "E4E7EC")
        }
    }

    var horizontalArtOpacity: Double {
        switch self {
        case .omega: return 0.52
        case .legendary: return 0.40
        default: return 0.48
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

    /// Splits a 45×26 capacity plate into its 16px left chevron bevel and its
    /// borderless 22px flat horizontal body so `#15` widens dynamically with the
    /// drain text (`7` vs `14` vs `+14`) without stretching the chevron or
    /// exposing its right border.
    static func capacityBackerParts(named fileName: String) -> (leftCap: UIImage, flatBody: UIImage)? {
        let leftKey = "backer-left:\(fileName)" as NSString
        let bodyKey = "backer-body:\(fileName)" as NSString
        if let leftHit = cache.object(forKey: leftKey),
           let bodyHit = cache.object(forKey: bodyKey) {
            return (leftHit, bodyHit)
        }
        guard let source = frameImage(named: fileName),
              let cgImage = source.cgImage,
              cgImage.width >= 40,
              let leftCG = cgImage.cropping(to: CGRect(x: 0, y: 0, width: 16, height: cgImage.height)),
              let bodyCG = cgImage.cropping(to: CGRect(x: 16, y: 0, width: 22, height: cgImage.height)) else {
            return nil
        }
        let left = UIImage(cgImage: leftCG, scale: 1, orientation: .up)
        let body = UIImage(cgImage: bodyCG, scale: 1, orientation: .up)
        cache.setObject(left, forKey: leftKey)
        cache.setObject(body, forKey: bodyKey)
        return (left, body)
    }

    static func polarityImage(named polarity: String) -> UIImage? {
        image(at: NativeDamageCatalog.shared.localPolarityIcon(named: polarity))
    }

    /// Expands `ModGlassMask.png` by 1px and tightens its 5px Gaussian edge
    /// fade so the glass layer reaches cleanly underneath `#4` / `#5`'s inner
    /// metal rails with no semi-transparent background seam.
    static func seamlessGlassMaskImage() -> UIImage? {
        let key = "seamless-glass-mask" as NSString
        if let hit = cache.object(forKey: key) {
            return hit
        }
        guard let source = frameImage(named: "ModGlassMask.png"),
              let cgImage = source.cgImage else {
            return nil
        }
        let w = cgImage.width
        let h = cgImage.height
        let bytesPerRow = w * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        var src = [UInt8](repeating: 0, count: h * bytesPerRow)
        let drew = src.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return source }

        var dst = [UInt8](repeating: 0, count: h * bytesPerRow)
        for y in 0..<h {
            let y0 = max(0, y - 1)
            let y1 = min(h - 1, y + 1)
            for x in 0..<w {
                let x0 = max(0, x - 1)
                let x1 = min(w - 1, x + 1)
                var maxA: UInt8 = 0
                for ny in y0...y1 {
                    let row = ny * bytesPerRow
                    for nx in x0...x1 {
                        let a = src[row + nx * 4 + 3]
                        if a > maxA { maxA = a }
                    }
                }
                let outA: UInt8
                if maxA <= 20 {
                    outA = 0
                } else if maxA >= 90 {
                    outA = 255
                } else {
                    outA = UInt8((Int(maxA) - 20) * 255 / 70)
                }
                let idx = y * bytesPerRow + x * 4
                dst[idx] = outA
                dst[idx + 1] = outA
                dst[idx + 2] = outA
                dst[idx + 3] = outA
            }
        }

        let outCG: CGImage? = dst.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return nil }
            return ctx.makeImage()
        }
        guard let cg = outCG else { return source }
        let result = UIImage(cgImage: cg, scale: 1, orientation: .up)
        cache.setObject(result, forKey: key)
        return result
    }
}
#endif

/// Renders raw Mod / Arcane illustration art. High-resolution `mod-art/` illustrations
/// render uncropped cleanly; any legacy portrait `mod-icons/` fallback strips baked-in text.
struct ModArtworkView: View {
    let rawName: String
    let isRiven: Bool
    var contentMode: ContentMode = .fill
    var alignment: Alignment = .center
    var imageYOffset: CGFloat = 0

    var body: some View {
        Color.clear
            .overlay(artworkLayer.offset(y: imageYOffset), alignment: alignment)
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
            let isVeiled = rawName.localizedCaseInsensitiveContains("riven mod")
                || rawName.contains("裂罅")
            if isVeiled {
                if let omegaArt = NativeDamageCatalog.shared.localModArt(named: "OmegaMod.webp") {
                    return (omegaArt, nil)
                }
                return (
                    NativeDamageCatalog.shared.localModIcon(named: "riven.webp"),
                    URL(string: "https://warframe-damage.com/data/mods/riven.webp")
                )
            }
            if let unveiledArt = NativeDamageCatalog.shared.localModArt(named: "RifleZoomMod.webp") {
                return (unveiledArt, nil)
            }
            return (
                NativeDamageCatalog.shared.localModIcon(named: "riven.webp"),
                URL(string: "https://warframe-damage.com/data/mod-art/RifleZoomMod.webp")
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
private func deTintedFrameImage(_ fileName: String, tint: Color, contentMode: ContentMode = .fit) -> some View {
#if canImport(UIKit)
    if let img = ModAssetImageCache.frameImage(named: fileName) {
        Image(uiImage: img)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .foregroundColor(tint)
    }
#endif
}

@MainActor
@ViewBuilder
private func deCapacityBackerPlate(_ fileName: String, height: CGFloat, leftCapWidth: CGFloat) -> some View {
#if canImport(UIKit)
    if let parts = ModAssetImageCache.capacityBackerParts(named: fileName) {
        HStack(spacing: 0) {
            Image(uiImage: parts.leftCap)
                .resizable()
                .frame(width: leftCapWidth, height: height)
            Image(uiImage: parts.flatBody)
                .resizable()
                .frame(height: height)
        }
    } else {
        deFrameImage(fileName, contentMode: .fill)
            .frame(height: height)
            .clipped()
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

/// One complete #15 capacity plate. Normalized to the 256×131 card chrome and
/// trailing-anchored inside #01 so its left chevron bevel extends automatically
/// for single-digit (`7`), two-digit (`14`), or positive (`+14`) drains while
/// its right edge tucks cleanly under the right chrome rail.
@MainActor
private struct DETopRightCapacityBacker: View {
    let frameImageName: String
    let capacityText: String
    let polarity: String
    let tint: Color
    let scale: CGFloat

    static let nativeContainerWidth: CGFloat = 96
    private let nativeHeight: CGFloat = 25.7

    var body: some View {
        let plateHeight = nativeHeight * scale
        let leftCapWidth = 15.5 * scale

        HStack(spacing: polarity.isEmpty ? 0 : 3.5 * scale) {
            Text(capacityText)
                .font(.custom("Verdana-Bold", size: 19.0 * scale))
                .foregroundColor(tint)
                .fixedSize()
                .scaleEffect(x: 0.85, y: 1)

            if !polarity.isEmpty {
                dePolarityView(polarity, tint: tint, size: 18.0 * scale)
                    .scaleEffect(x: 0.92, y: 1)
                    .frame(width: 14.0 * scale, height: 15.0 * scale)
            }
        }
        .shadow(color: Color.black.opacity(0.65), radius: 1.0 * scale, y: 0.6 * scale)
        .padding(.leading, leftCapWidth)
        .padding(.trailing, 6.0 * scale)
        .frame(height: plateHeight)
        .background(
            deCapacityBackerPlate(
                frameImageName,
                height: plateHeight,
                leftCapWidth: leftCapWidth
            )
        )
        .frame(width: Self.nativeContainerWidth * scale, height: plateHeight, alignment: .trailing)
    }
}

/// Compact in-game horizontal Mod / Arcane tile for a two-column grid.
///
/// The Mod chrome, glass mask, and glass glow were extracted from a single
/// 256 × 128 DE canvas.  Keeping that coordinate system intact is important:
/// scaling the mask only to an estimated "art window" distorts the lower
/// notches and makes the frame look hand drawn.
struct HorizontalModCardView: View {
    let card: ModCardPresentation

    /// All horizontal Mod cards share the same 256 × 131 outer reference canvas
    /// so ordinary and overhang tiers keep identical glass height and rank alignment.
    private var nativeCanvasHeight: CGFloat {
        card.isArcane ? 128 : 131
    }

    var body: some View {
        Group {
            if card.isArcane {
                arcaneTile
            } else {
                modTile
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(256.0 / nativeCanvasHeight, contentMode: .fit)
        // Do not clip here: compact Galvanized / Amalgam / Omega chrome has
        // intentional wings that extend beyond the 256px glass canvas.
        .contentShape(Rectangle())
    }

    private var modTile: some View {
        let tier = ModFrameTier(card: card)
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Use one uniform scale from the 256px long edge. The ordinary
            // stitched chrome is taller than its 128px glass mask, so deriving
            // Y from the parent height would stretch every source asset.
            let scale = w / 256
            let sx = scale
            let sy = scale
            let isOverhang = tier.hasHorizontalOverhang
            let glassHeight = tier.horizontalGlassHeight * scale
            // #1's opaque 242×116 silhouette (center 127.5, 62.5) is centred
            // within the 256 × 131 ordinary chrome (visible y=1..130, center 65.5).
            let glassOriginX: CGFloat = 0
            // Tuck glass rims cleanly behind chrome top/bottom rails across all tiers.
            let glassOriginY: CGFloat = tier.horizontalGlassOriginY * scale
            let drainTint = card.isPositiveCapacity ? Color(hex: "77E494") : tier.textColor
            let titleWidth = w * (isOverhang ? 0.74 : 0.80)
            // The ordinary 256 × 131 chrome, rather than its centred glass
            // canvas, is the reference coordinate system for the name.
            let titleCenterX: CGFloat = 127.6 * sx
            let titleCenterY: CGFloat = (card.isRiven ? 61.5 : 62.5) * sy
            let capacityTrailingX: CGFloat = tier.horizontalCapacityTrailingX * sx
            let capacityCenterY: CGFloat = 27.1 * sy
            let rankCenterX: CGFloat = isOverhang ? glassOriginX + w * 0.5 : 128 * sx
            let rankCenterY: CGFloat = tier.horizontalRankY * sy
            let rankDotSize: CGFloat = (isOverhang ? 10.5 : 11.8) * scale
            let rankSpacing: CGFloat = (isOverhang ? 1.0 : 0.74) * scale
            let rankLineWidth: CGFloat = isOverhang ? w * 0.74 : 243 * scale

            ZStack(alignment: .topLeading) {
                // Artwork, rarity wash, and the *real* glass layers all use
                // the same full card canvas. The metal chrome goes above it.
                ZStack {
                    Color.black
                    tier.backdropColor.opacity(0.65)

                    ModArtworkView(
                        rawName: card.rawName,
                        isRiven: card.isRiven,
                        contentMode: .fill,
                        alignment: .top,
                        imageYOffset: (card.isRiven ? -2 : -10) * scale
                    )
                    .frame(width: w, height: glassHeight)
                    .clipped()
                    .saturation(card.isRiven ? 0.10 : 0.14)
                    .opacity(tier.horizontalArtOpacity)

                    // Directional corner glass reflections matching in-game shader
                    RadialGradient(
                        stops: [
                            .init(color: tier.glassTintColor.opacity(card.isRiven ? 0.20 : 0.40), location: 0.0),
                            .init(color: tier.glassTintColor.opacity(card.isRiven ? 0.07 : 0.14), location: 0.45),
                            .init(color: .clear, location: 1.0),
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: w * 0.62
                    )
                    .blendMode(.screen)

                    RadialGradient(
                        stops: [
                            .init(color: tier.glassTintColor.opacity(card.isRiven ? 0.16 : 0.34), location: 0.0),
                            .init(color: .clear, location: 1.0),
                        ],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: w * 0.48
                    )
                    .blendMode(.screen)

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color.black.opacity(0.06), location: 0.35),
                            .init(color: Color.black.opacity(0.26), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    deTintedFrameImage("ModGlassGlow.png", tint: tier.glassTintColor, contentMode: .fill)
                        .frame(width: w, height: glassHeight)
                        .opacity(card.isRiven ? 0.42 : 0.72)
                        .blendMode(.screen)

                    deTintedFrameImage("ModGlassHoverGlow.png", tint: Color(hex: "D8E8FF"), contentMode: .fill)
                        .frame(width: w, height: glassHeight)
                        .opacity(0.20)
                        .blendMode(.screen)

                    // Ordinary tiers clip the capacity plate inside the glass mask so
                    // its right edge stops cleanly under the thin vertical chrome rim.
                    if !isOverhang {
                        capacityPlateView(
                            tier: tier,
                            drainTint: drainTint,
                            trailingX: capacityTrailingX - glassOriginX,
                            centerY: capacityCenterY - glassOriginY,
                            scale: scale
                        )
                    }
                }
                .compositingGroup()
                .mask(deGlassMask(width: w, height: glassHeight))
                .frame(width: w, height: glassHeight)
                .position(
                    x: glassOriginX + w * 0.5,
                    y: glassOriginY + glassHeight * 0.5
                )
                .allowsHitTesting(false)

                // All tiers align their full top & bottom frames onto the same 256 × 131 grid.
                ZStack(alignment: .top) {
                    Color.clear
                    deFrameImage(tier.bottomFrameImageName, contentMode: .fit)
                        .frame(width: w * (tier.frameBottomNativeWidth / 256))
                        .offset(y: tier.horizontalBottomTopY * scale)
                }
                .frame(width: w, height: h)
                .allowsHitTesting(false)

                ZStack(alignment: .top) {
                    Color.clear
                    deFrameImage(tier.topFrameImageName, contentMode: .fit)
                        .frame(width: w * (tier.frameTopNativeWidth / 256))
                        .offset(y: tier.horizontalTopY * scale)
                }
                .frame(width: w, height: h)
                .allowsHitTesting(false)

                // Overhang tiers drape the capacity ribbon in front of the right side pillar.
                if isOverhang {
                    capacityPlateView(
                        tier: tier,
                        drainTint: drainTint,
                        trailingX: capacityTrailingX,
                        centerY: capacityCenterY,
                        scale: scale
                    )
                    .allowsHitTesting(false)
                }

                if let modSet = card.metadata?.modSet, !modSet.isEmpty {
                    ZStack(alignment: .top) {
                        Color.clear
                        deFrameImage("\(modSet)Header.png", contentMode: .fit)
                            .frame(width: w * 0.44)
                            .offset(y: -15.0 * scale)
                    }
                    .frame(width: w, height: h)
                    .allowsHitTesting(false)
                }

                // The game chrome already communicates type/rank. Deliberately
                // omit the former application-only slotTag capsule here.
                Text(card.displayName)
                    .font(.system(
                        size: (card.isRiven ? 19.5 : 24.0) * scale,
                        weight: .medium
                    ))
                    .foregroundColor(tier.horizontalTitleColor)
                    .shadow(color: Color.black.opacity(0.88), radius: 2.0 * scale, y: 1.2 * scale)
                    .lineLimit(card.isRiven ? 2 : 1)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
                    .frame(width: titleWidth)
                    .position(
                        x: titleCenterX,
                        y: titleCenterY
                    )
                    .allowsHitTesting(false)

                if card.effectiveMaxRank > 0 {
                    deRankBar(
                        current: card.effectiveRank,
                        maxRank: card.effectiveMaxRank,
                        dotSize: rankDotSize,
                        spacing: rankSpacing,
                        lineWidth: rankLineWidth
                    )
                    .position(
                        x: rankCenterX,
                        y: rankCenterY
                    )
                    .allowsHitTesting(false)
                }
            }
            .frame(width: w, height: h)
        }
        // This belongs to the grid child rather than its inner ZStack, so a
        // special frame's right wing is painted above the next grid cell.
        .zIndex(tier.hasHorizontalOverhang ? 1 : 0)
    }

    @ViewBuilder
    private func capacityPlateView(
        tier: ModFrameTier,
        drainTint: Color,
        trailingX: CGFloat,
        centerY: CGFloat,
        scale: CGFloat
    ) -> some View {
        if let drain = card.effectiveDrain {
            DETopRightCapacityBacker(
                frameImageName: tier.topRightBackerImageName,
                capacityText: card.isPositiveCapacity ? "+\(drain)" : "\(drain)",
                polarity: card.metadata?.polarity ?? "",
                tint: drainTint,
                scale: scale
            )
            .position(
                x: trailingX - DETopRightCapacityBacker.nativeContainerWidth * 0.5 * scale,
                y: centerY
            )
        }
    }

    private var arcaneTile: some View {
        let tier = ModFrameTier(card: card)
        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let backerSide = min(h * 1.04, w * 0.42)

            ZStack {
                LinearGradient(
                    colors: [Color(hex: "16252B"), tier.backdropColor, Color(hex: "071015")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [tier.accentColor.opacity(0.12), .clear, Color.black.opacity(0.24)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: 0) {
                    ZStack {
                        deFrameImage("ArcaneUpgradeBackerMask.png", contentMode: .fit)
                            .frame(width: backerSide, height: backerSide)
                            .opacity(0.94)

                        ModArtworkView(rawName: card.rawName, isRiven: false, contentMode: .fit)
                            .frame(width: backerSide * 1.28, height: backerSide * 0.92)
                            .shadow(color: Color.black.opacity(0.65), radius: 3, y: 1)
                    }
                    .frame(width: w * 0.48, height: h)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.displayName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.85), radius: 1.5, y: 1)
                            .lineLimit(2)
                            .minimumScaleFactor(0.74)

                        Text("赋能")
                            .font(.system(size: 9, weight: .medium))
                            .tracking(1.1)
                            .foregroundColor(tier.accentColor)

                        if card.effectiveMaxRank > 0 {
                            deRankBar(
                                current: card.effectiveRank,
                                maxRank: card.effectiveMaxRank,
                                dotSize: 7.5,
                                spacing: 1.5,
                                lineWidth: w * 0.34
                            )
                        }
                    }
                    .frame(width: w * 0.45, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, max(5, w * 0.025))
            }
            .frame(width: w, height: h)
        }
    }
}

@MainActor
@ViewBuilder
private func deGlassMask(width: CGFloat, height: CGFloat) -> some View {
#if canImport(UIKit)
    if let maskImg = ModAssetImageCache.seamlessGlassMaskImage()
        ?? ModAssetImageCache.frameImage(named: "ModGlassMask.png") {
        Image(uiImage: maskImg)
            .resizable()
            .frame(width: width, height: height)
    } else {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
    }
#else
    RoundedRectangle(cornerRadius: 4, style: .continuous)
#endif
}

@MainActor
@ViewBuilder
private func maskedWithModGlass<Content: View>(_ content: Content, width: CGFloat, height: CGFloat) -> some View {
    content.mask(deGlassMask(width: width, height: height))
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
        // Portrait frame assets share a native 256 × 512 coordinate system.
        // Preserve it instead of stretching the 242 × 342 carbon background
        // into an arbitrary short sheet.
        let cardWidth: CGFloat = 280
        let scale = cardWidth / 256
        let cardHeight = 512 * scale
        let bodyWidth = 242 * scale
        let bodyHeight = 342 * scale
        let bodyTop = 85 * scale
        let sideLightWidth = tier.sideLightNativeWidth * scale
        let drainTint = card.isPositiveCapacity ? Color(hex: "77E494") : tier.textColor

        return ZStack {
            Color.clear
                .frame(width: cardWidth, height: cardHeight)

            // 1. The trimmed body is an exact crop of Background.png at
            //    native x:7, y:85. It must keep its 242:342 aspect ratio.
            ZStack(alignment: .top) {
                tier.backdropColor
                deFrameImage(tier.backgroundImageName, contentMode: .fill)
                    .frame(width: bodyWidth, height: bodyHeight)
                    .clipped()

                ModArtworkView(rawName: card.rawName, isRiven: card.isRiven, contentMode: .fill)
                    .frame(width: bodyWidth, height: 218 * scale)
                    .clipped()
                    .saturation(card.isRiven ? 0.12 : 0.18)
                    .overlay(
                        tier.glassTintColor.opacity(card.isRiven ? 0.14 : 0.20)
                            .blendMode(.screen)
                    )
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0.0),
                                .init(color: .white, location: 0.52),
                                .init(color: .clear, location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: bodyWidth, height: bodyHeight)
            .position(x: cardWidth * 0.5, y: bodyTop + bodyHeight * 0.5)

            // 2. Side lights occupy their native 16 × 256 (32 × 256 for
            //    Galvanized) slot between the portrait top and bottom chrome.
            deFrameImage(tier.sideLightImageName, contentMode: .fit)
                .frame(width: sideLightWidth, height: 256 * scale)
                .position(x: sideLightWidth * 0.5, y: 256 * scale)
                .allowsHitTesting(false)

            deFrameImage(tier.sideLightImageName, contentMode: .fit)
                .frame(width: sideLightWidth, height: 256 * scale)
                .scaleEffect(x: -1, y: 1)
                .position(x: cardWidth - sideLightWidth * 0.5, y: 256 * scale)
            .allowsHitTesting(false)

            // Capacity backing is inside the chrome, so its right edge is
            // occluded by the full portrait frame just as it is on the
            // horizontal card.
            if let drain = card.effectiveDrain {
                DETopRightCapacityBacker(
                    frameImageName: tier.topRightBackerImageName,
                    capacityText: card.isPositiveCapacity ? "+\(drain)" : "\(drain)",
                    polarity: card.metadata?.polarity ?? "",
                    tint: drainTint,
                    scale: scale
                )
                .position(
                    x: cardWidth - (3.25 + DETopRightCapacityBacker.nativeContainerWidth * 0.5) * scale,
                    y: 29 * scale
                )
                .allowsHitTesting(false)
            }

            deFrameImage(tier.cornerLightsImageName, contentMode: .fit)
                .frame(width: 64 * scale, height: 64 * scale)
                .opacity(0.65)
                .position(x: 32 * scale, y: 32 * scale)
                .allowsHitTesting(false)

            // 3. Full portrait frames. Special tiers retain their source
            //    width, so their ornate side wings are never squashed.
            ZStack(alignment: .top) {
                Color.clear
                deFrameImage(tier.topFrameImageName, contentMode: .fit)
                    .frame(width: cardWidth * (tier.frameTopNativeWidth / 256))
            }
            .frame(width: cardWidth, height: cardHeight)
            .allowsHitTesting(false)

            ZStack(alignment: .bottom) {
                Color.clear
                deFrameImage(tier.bottomFrameImageName, contentMode: .fit)
                    .frame(width: cardWidth * (tier.frameBottomNativeWidth / 256))
            }
            .frame(width: cardWidth, height: cardHeight)
            .allowsHitTesting(false)

            if let modSet = card.metadata?.modSet, !modSet.isEmpty {
                ZStack(alignment: .top) {
                    Color.clear
                    deFrameImage("\(modSet)Header.png", contentMode: .fit)
                        .frame(width: 128 * scale)
                        .offset(y: -2 * scale)
                }
                .frame(width: cardWidth, height: cardHeight)
                .allowsHitTesting(false)
            }

            // 4. Text stays within the safe body area while the source chrome
            //    owns the upper/lower visual weight and the rank tray.
            VStack(spacing: 7) {
                Spacer().frame(height: 226 * scale)

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
                .padding(.horizontal, 16 * scale)

                Spacer(minLength: 8 * scale)

                ZStack {
                    deFrameImage(tier.lowerTabImageName, contentMode: .fit)
                        .frame(width: 210 * scale)
                    Text(card.compatLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tier.textColor)
                }
                .padding(.bottom, 5 * scale)

                if card.effectiveMaxRank > 0 {
                    deRankBar(
                        current: card.effectiveRank,
                        maxRank: card.effectiveMaxRank,
                        dotSize: card.effectiveMaxRank > 6 ? 10 : 12,
                        spacing: card.effectiveMaxRank > 6 ? 2.5 : 4,
                        lineWidth: 206 * scale
                    )
                    .padding(.bottom, 30 * scale)
                } else {
                    Spacer().frame(height: 32 * scale)
                }
            }
            .frame(width: bodyWidth, height: cardHeight)
        }
        .frame(width: cardWidth, height: cardHeight)
        .shadow(color: tier.accentColor.opacity(0.25), radius: 18, y: 8)
    }

    private func verticalArcaneCard(tier: ModFrameTier) -> some View {
        let panelWidth: CGFloat = 276
        let backerSide: CGFloat = 212

        return ZStack {
            LinearGradient(
                colors: [Color(hex: "0B171C"), tier.backdropColor, Color(hex: "050B0E")],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 12) {
                ZStack {
                    // This is a source backer, not a generic circular mask:
                    // it carries the etched stone/metal texture of an Arcane
                    // upgrade slot.
                    deFrameImage("ArcaneUpgradeBackerMask.png", contentMode: .fit)
                        .frame(width: backerSide, height: backerSide)
                        .opacity(0.96)

                    ModArtworkView(rawName: card.rawName, isRiven: false, contentMode: .fit)
                        .frame(width: backerSide * 1.28, height: backerSide * 0.92)
                        .shadow(color: .black.opacity(0.78), radius: 5, y: 2)
                }
                .frame(width: backerSide + 18, height: backerSide)
                .shadow(color: tier.accentColor.opacity(0.20), radius: 14)
                .padding(.top, 18)

                Text(card.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.92), radius: 2.5, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                Text("赋能")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(tier.accentColor)

                if card.effectiveMaxRank > 0 {
                    deRankBar(
                        current: card.effectiveRank,
                        maxRank: card.effectiveMaxRank,
                        dotSize: 12,
                        spacing: 4,
                        lineWidth: 160
                    )
                    .padding(.top, 1)
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, tier.accentColor.opacity(0.48), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .padding(.horizontal, 26)
                    .padding(.top, 5)

                VStack(spacing: 6) {
                    ForEach(Array(card.effectLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.94))
                            .shadow(color: .black.opacity(0.72), radius: 1.25, y: 1)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 2)
                .padding(.bottom, 22)
            }
        }
        .frame(width: panelWidth)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, tier.accentColor.opacity(0.72), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, tier.accentColor.opacity(0.52), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .shadow(color: tier.accentColor.opacity(0.20), radius: 16, y: 8)
    }
}
