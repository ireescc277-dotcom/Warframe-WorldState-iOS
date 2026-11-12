import SwiftUI
import UIKit
import ImageIO

/// 武器库：先列出账号快照里的武器实例，再把选中的 A/B/C 配卡交给计算器。
///
/// 公共武器数据库只提供图标、中文名和空计算器的手动选择器；它不是这个页面的
/// 列表来源。这样同名武器的不同实例、继承元素和配置不会被合并丢掉。
public struct ArsenalView: View {
    @ObservedObject private var catalog = WeaponCatalog.shared
    @ObservedObject private var inventory = InventoryFeed.shared

    @State private var category: WeaponCategory = ArsenalView.seededCategory
    @State private var query = ""
    @State private var pushedOwned: InventoryData.OwnedWeapon?
    @State private var pushedGeneric: WeaponEntry?
    @State private var showCalc = false
    @State private var openCalc = ArsenalView.seededCalc

    public init() {}

    /// `simctl` 点不了屏幕，靠启动参数把分类和计算器直接摆出来给 CI 拍。
    private static var seededCategory: WeaponCategory {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-arsenalCat"), args.index(after: i) < args.endIndex
        else { return .all }
        return WeaponCategory(rawValue: args[args.index(after: i)]) ?? .all
    }

    private static var seededCalc: Bool {
        CommandLine.arguments.contains("-openCalc")
    }

    /// `-calcWeapon Torid`：CI 要一张「从武器列表点进计算器」的图，
    /// simctl 点不了屏，只能在启动时直接把这一跳做掉。
    private static var seededWeapon: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-calcWeapon"), args.index(after: i) < args.endIndex
        else { return nil }
        return args[args.index(after: i)]
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: WFUI.s4) {
                        header
                        searchBox
                        categoryBar
                        list
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 100)
                }
                .refreshable { await inventory.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                catalog.load()
                // Warm the JSON/DataStore once while the user is looking at
                // their owned list.  We do not compute every config eagerly:
                // target/environment options would make such cached answers
                // stale.  The selected config is still prefilled and its real
                // calculation remains off the main thread.
                _ = NativeDamageCatalog.shared
                await inventory.refresh()
                if let want = ArsenalView.seededWeapon,
                   pushedGeneric == nil,
                   let hit = catalog.weapons.first(where: { $0.n == want }) {
                    pushedGeneric = hit
                    showCalc = true
                }
            }
            // iOS 16 没有 navigationDestination(item:)，用 isPresented + 暂存数据
            .navigationDestination(isPresented: $showCalc) {
                if let owned = pushedOwned {
                    DamageCalcView(
                        ownedWeapon: owned,
                        availableWarframes: inventory.data?.ownedWarframes ?? [],
                        title: owned.z
                    )
                } else if let w = pushedGeneric {
                    DamageCalcView(
                        weapon: w.n,
                        availableWarframes: inventory.data?.ownedWarframes ?? [],
                        title: w.z
                    )
                } else {
                    DamageCalcView(
                        weapon: nil,
                        availableWarframes: inventory.data?.ownedWarframes ?? [],
                        title: "伤害计算"
                    )
                }
            }
            .navigationDestination(isPresented: $openCalc) {
                DamageCalcView(
                    weapon: nil,
                    availableWarframes: inventory.data?.ownedWarframes ?? [],
                    title: "伤害计算"
                )
            }
        }
    }

    // MARK: - 头

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("军械库")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(WFTheme.textPrimary)
                Text(weaponSubtitle)
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
            Spacer()
            Button {
                openCalc = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "function")
                        .font(.system(size: 12, weight: .semibold))
                    Text("空计算器")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(WFTheme.gold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(WFTheme.gold.opacity(0.12))
                )
                .overlay(
                    Capsule().stroke(WFTheme.gold.opacity(0.35), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var searchBox: some View {
        HStack(spacing: WFUI.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(WFTheme.textMuted)
            TextField("搜武器名（中英文都行）", text: $query)
                .font(.wfBody)
                .foregroundColor(WFTheme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(WFTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, WFUI.s3)
        .padding(.vertical, 10)
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WFUI.s2) {
                ForEach(WeaponCategory.allCases) { cat in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { category = cat }
                    } label: {
                        Text(cat.label)
                            .font(.system(size: 12, weight: category == cat ? .semibold : .regular))
                            .foregroundColor(category == cat ? Color(hex: "1A1408") : WFTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(category == cat ? WFTheme.gold : WFUI.surface)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - 列表

    private var ownedWeapons: [InventoryData.OwnedWeapon] {
        inventory.data?.ownedWeapons ?? []
    }

    private var weaponSubtitle: String {
        if inventory.data == nil {
            return inventory.fetching ? "正在读取背包快照…" : "尚未取得背包快照"
        }
        if catalog.failed {
            return "背包 \(ownedWeapons.count) 把 · 计算器数据不可用"
        }
        return "背包 \(ownedWeapons.count) 把 · 点入后预填 A/B/C 配卡"
    }

    private func categoryMatches(_ weapon: InventoryData.OwnedWeapon) -> Bool {
        switch category {
        case .all: return true
        case .primary: return weapon.category == "Primary"
        case .secondary: return weapon.category == "Secondary"
        case .melee: return weapon.category == "Melee"
        case .archgun: return weapon.category == "Archgun" || weapon.category == "Archmelee"
        }
    }

    private var filtered: [InventoryData.OwnedWeapon] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return ownedWeapons.filter { w in
            guard categoryMatches(w) else { return false }
            guard !q.isEmpty else { return true }
            return w.z.lowercased().contains(q)
                || (w.calcName?.lowercased().contains(q) ?? false)
        }
    }

    private var list: some View {
        let rows = filtered
        return LazyVStack(spacing: 0) {
            if inventory.data == nil {
                Text(inventory.failed
                     ? "没有可用的背包快照。下拉重试；空计算器仍可手动选武器。"
                     : "正在读取背包快照…")
                    .font(.wfBody)
                    .foregroundColor(inventory.failed ? WFTheme.red : WFTheme.textMuted)
                    .padding(.vertical, WFUI.s4)
            } else if rows.isEmpty {
                Text(ownedWeapons.isEmpty ? "这份背包快照没有武器实例。" : "没有匹配的背包武器")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textMuted)
                    .padding(.vertical, WFUI.s5)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, w in
                    Button {
                        guard canCalculate(w) else { return }
                        pushedOwned = w
                        pushedGeneric = nil
                        showCalc = true
                    } label: {
                        row(w)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCalculate(w))
                    if idx < rows.count - 1 {
                        WFHairline().padding(.leading, 56)
                    }
                }
            }
        }
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private func catalogEntry(for weapon: InventoryData.OwnedWeapon) -> WeaponEntry? {
        guard let name = weapon.calcName else { return nil }
        return catalog.weapons.first(where: { $0.n == name })
    }

    private func canCalculate(_ weapon: InventoryData.OwnedWeapon) -> Bool {
        weapon.calcName != nil && catalogEntry(for: weapon) != nil && !catalog.failed
    }

    private func row(_ w: InventoryData.OwnedWeapon) -> some View {
        let entry = catalogEntry(for: w)
        let supported = canCalculate(w)
        return HStack(spacing: WFUI.s3) {
            WeaponThumb(name: entry?.img, remote: entry?.iconURL, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(w.z)
                    .font(.wfTitle)
                    .foregroundColor(WFTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(w.categoryLabel)
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textSecondary)
                    Text("\(w.configs.count) 套配卡")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                    if w.configs.contains(where: { !$0.isExactImport }) {
                        Text("有未导入槽位")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.gold)
                    }
                }
            }

            Spacer(minLength: WFUI.s2)

            VStack(alignment: .trailing, spacing: 2) {
                Text(supported ? "预填计算" : "暂不支持")
                    .font(.wfLabel)
                    .foregroundColor(supported ? WFTheme.cyan : WFTheme.textMuted)
                if supported {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(WFTheme.textMuted.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, WFUI.s3)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .opacity(supported ? 1 : 0.64)
    }
}

// MARK: - 缩略图

/// 武器图的内存缓存。
///
/// 666 行一次性铺开时，每张 220×220 的 RGBA 解码后接近 200 KB，全解出来是
/// 120 MB 级别——真机上会被系统回收，表现出来就是「列表很卡、图一会儿全没了」。
/// 所以只解码滚到眼前的那几张，解到显示尺寸（40pt × 3 倍 = 120px），按文件名缓存。
final class WeaponIconStore {
    static let shared = WeaponIconStore()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "wf.weapon.icon",
                                      qos: .userInitiated,
                                      attributes: .concurrent)

    private init() {
        cache.countLimit = 320
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func cached(_ name: String) -> UIImage? {
        cache.object(forKey: name as NSString)
    }

    /// 本地包里没有这张图时返回 nil，调用方自己决定要不要走网络。
    func load(_ name: String, maxPixel: CGFloat) async -> UIImage? {
        if let hit = cached(name) { return hit }
        guard let dir = WeaponCatalog.iconsDir else { return nil }
        let url = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        return await withCheckedContinuation { cont in
            queue.async {
                let image = WeaponIconStore.downsample(url: url, maxPixel: maxPixel)
                if let image = image {
                    let cost = Int(maxPixel * maxPixel * 4)
                    self.cache.setObject(image, forKey: name as NSString, cost: cost)
                }
                cont.resume(returning: image)
            }
        }
    }

    /// 让 ImageIO 直接解到目标尺寸，而不是先解全图再缩。
    private static func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

/// 武器图。包里带了一份（`ios/DamageData/icons`，构建时从 assets 复制），
/// 优先读本地，读不到再回站点 CDN。两边都没有就画占位块，保证行高不跳。
struct WeaponThumb: View {
    let name: String?
    let remote: URL?
    let size: CGFloat

    @State private var local: UIImage?
    @State private var tried = false

    var body: some View {
        Group {
            if let local = local {
                Image(uiImage: local)
                    .resizable()
                    .scaledToFit()
            } else if tried, let remote = remote {
                // 本地没有这张图才走网络，避免每行都去撞一次 CDN
                AsyncImage(url: remote) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WFTheme.panel)
        )
        .task(id: name) {
            guard local == nil, !tried else { return }
            guard let name = name, !name.isEmpty else {
                tried = true
                return
            }
            let px = size * UIScreen.main.scale
            let image = await WeaponIconStore.shared.load(name, maxPixel: px)
            if Task.isCancelled { return }
            local = image
            tried = true
        }
    }

    private var placeholder: some View {
        Image(systemName: "scope")
            .font(.system(size: size * 0.36, weight: .light))
            .foregroundColor(WFTheme.textMuted.opacity(0.45))
    }
}
