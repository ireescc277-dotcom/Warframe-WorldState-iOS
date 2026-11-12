import Combine
import Foundation

/// 武器清单。数据来自 `ios/DamageData/weapons-list.json`，由
/// `scripts/build_native_damage_data.py` 从站点数据生成——和计算器用的是同一份，
/// 中文名也来自站点自带的 localeLang，不会出现两套译名。
public struct WeaponEntry: Decodable, Identifiable, Hashable {
    public let n: String        // 英文名，计算器只认这个
    public let z: String        // 中文名
    public let c: String        // Primary / Secondary / Melee / Archgun
    public let t: String        // Rifle / Bow / Staff ...
    public let img: String      // 缩略图文件名
    public let mr: Int
    public let atk: [String]    // 攻击段
    public let inc: Bool        // 有灵化形态

    public var id: String { n }

    /// 站点把武器图放在自己的 /data/img/ 下，文件名就是 imageName。
    /// 包里带了一份（assets/weapon-icons），这里作为联网兜底。
    public var iconURL: URL? {
        guard !img.isEmpty else { return nil }
        return URL(string: "https://warframe-damage.com/data/img/\(img)")
    }

    public var categoryLabel: String {
        switch c {
        case "Primary": return "主武器"
        case "Secondary": return "副武器"
        case "Melee": return "近战"
        case "Archgun": return "Archwing 枪械"
        case "Exalted Weapon": return "显赫武器"
        default: return c
        }
    }

    public var typeLabel: String {
        // 近战数据里的 type 字段一律是 Rifle，没有参考价值
        c == "Melee" ? "近战" : t
    }
}

public enum WeaponCategory: String, CaseIterable, Identifiable {
    case all, primary, secondary, melee, archgun

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "全部"
        case .primary: return "主武器"
        case .secondary: return "副武器"
        case .melee: return "近战"
        case .archgun: return "Archwing"
        }
    }

    func matches(_ w: WeaponEntry) -> Bool {
        switch self {
        case .all: return true
        case .primary: return w.c == "Primary"
        case .secondary: return w.c == "Secondary"
        case .melee: return w.c == "Melee"
        case .archgun: return w.c == "Archgun" || w.c == "Exalted Weapon"
        }
    }
}

/// 从 App 包里读武器表。目录由 project.yml 以 folder reference 打进 bundle，
/// 名字是 DamageData；它只含 JSON 与图片，不含网页运行时。
public final class WeaponCatalog: ObservableObject {
    public static let shared = WeaponCatalog()

    @Published public private(set) var weapons: [WeaponEntry] = []
    @Published public private(set) var failed = false

    private init() {}

    /// App 包内计算器根目录。找不到时返回 nil，调用方负责降级。
    public static var bundleRoot: URL? {
        if let u = Bundle.main.url(forResource: "DamageData", withExtension: nil) {
            return u
        }
        // xcodegen 的 folder reference 偶尔会把目录压平到包根
        if let u = Bundle.main.url(forResource: "weapons-list", withExtension: "json") {
            return u.deletingLastPathComponent()
        }
        return nil
    }

    /// 打包进 App 的武器缩略图目录（webp）。
    public static var iconsDir: URL? {
        bundleRoot?.appendingPathComponent("icons")
    }

    public func load() {
        guard weapons.isEmpty else { return }
        guard let root = WeaponCatalog.bundleRoot else {
            failed = true
            return
        }
        let url = root.appendingPathComponent("site").appendingPathComponent("weapons-list.json")
        do {
            let data = try Data(contentsOf: url)
            weapons = try JSONDecoder().decode([WeaponEntry].self, from: data)
        } catch {
            failed = true
        }
    }
}
