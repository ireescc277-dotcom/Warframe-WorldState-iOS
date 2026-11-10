import SwiftUI

/// 武器库：选一把枪，装进伤害计算器。
///
/// 它本身不算任何东西——计算全在 `DamageCalcView` 的网页内核里。这里只负责
/// 把 666 把武器按类别摆出来、能搜、带图标，点进去把武器名交给计算器预填。
/// 顶部另有一个「空计算器」，对应「不从这里选、进去自己配」那条路。
public struct ArsenalView: View {
    @ObservedObject private var catalog = WeaponCatalog.shared

    @State private var category: WeaponCategory = ArsenalView.seededCategory
    @State private var query = ""
    @State private var pushed: WeaponEntry?
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
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                catalog.load()
                if let want = ArsenalView.seededWeapon,
                   pushed == nil,
                   let hit = catalog.weapons.first(where: { $0.n == want }) {
                    pushed = hit
                    showCalc = true
                }
            }
            // iOS 16 没有 navigationDestination(item:)，用 isPresented + 暂存数据
            .navigationDestination(isPresented: $showCalc) {
                if let w = pushed {
                    DamageCalcView(weapon: w.n, title: w.z)
                }
            }
            .navigationDestination(isPresented: $openCalc) {
                DamageCalcView(weapon: nil, title: "伤害计算")
            }
        }
    }

    // MARK: - 头

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("武器")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(WFTheme.textPrimary)
                Text(catalog.failed ? "资源缺失" : "\(catalog.weapons.count) 把 · 点一把配卡算伤害")
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

    private var filtered: [WeaponEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return catalog.weapons.filter { w in
            guard category.matches(w) else { return false }
            guard !q.isEmpty else { return true }
            return w.z.lowercased().contains(q) || w.n.lowercased().contains(q)
        }
    }

    private var list: some View {
        let rows = filtered
        return VStack(spacing: 0) {
            if catalog.failed {
                Text("App 包里没有计算器资源（web/app）。构建时先跑 scripts/build_web_site.py。")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.red)
                    .padding(.vertical, WFUI.s4)
            } else if rows.isEmpty {
                Text("没有匹配的武器")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textMuted)
                    .padding(.vertical, WFUI.s5)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, w in
                    Button {
                        pushed = w
                        showCalc = true
                    } label: {
                        row(w)
                    }
                    .buttonStyle(.plain)
                    if idx < rows.count - 1 {
                        WFHairline().padding(.leading, 56)
                    }
                }
            }
        }
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private func row(_ w: WeaponEntry) -> some View {
        HStack(spacing: WFUI.s3) {
            WeaponThumb(url: w.iconURL, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(w.z)
                    .font(.wfTitle)
                    .foregroundColor(WFTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(w.typeLabel)
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textSecondary)
                    Text("MR \(w.mr)")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
                    if w.inc {
                        Text("灵化")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.cyan)
                    }
                }
            }

            Spacer(minLength: WFUI.s2)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(w.atk.count) 段")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(WFTheme.textMuted.opacity(0.7))
            }
        }
        .padding(.horizontal, WFUI.s3)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

// MARK: - 缩略图

/// 武器图在站点自己的 CDN 上（`/data/img/<imageName>`）。断网时退化成占位方块，
/// 不让行高抖动。
struct WeaponThumb: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit()
                    case .failure:
                        placeholder
                    default:
                        placeholder.opacity(0.5)
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
    }

    private var placeholder: some View {
        Image(systemName: "scope")
            .font(.system(size: size * 0.36, weight: .light))
            .foregroundColor(WFTheme.textMuted.opacity(0.45))
    }
}
