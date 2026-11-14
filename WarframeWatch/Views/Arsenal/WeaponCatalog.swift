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

/// App bundle 中 DamageData 的统一定位器。
///
/// XcodeGen 把这个目录作为 folder reference 拷入 `.app/DamageData`。系统的
/// `url(forResource:withExtension:)` 面向单个资源文件，不能可靠地发现这一类
/// 文件夹引用；因此直接从 bundle 的资源根目录检查真实目录与必需 JSON 文件。
/// 所有武器列表和计算器入口必须经过这里，避免两个页面各自猜测资源路径。
enum DamageDataBundle {
    static func root(in bundle: Bundle = .main) -> URL? {
        let fileManager = FileManager.default
        let bases = [bundle.resourceURL, bundle.bundleURL].compactMap { $0 }

        for base in bases {
            let candidate = base.appendingPathComponent("DamageData", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            let requiredFiles = [
                "weapons-list.json",
                "zh-Hans.json",
                "data/json/enemies-min.json",
            ]
            guard requiredFiles.allSatisfy({
                fileManager.fileExists(atPath: candidate.appendingPathComponent($0).path)
            }) else { continue }

            return candidate
        }

        // Preserve compatibility with a manually flattened resource bundle,
        // but still require the same complete data set before accepting it.
        for base in bases {
            let requiredFiles = [
                "weapons-list.json",
                "zh-Hans.json",
                "data/json/enemies-min.json",
            ]
            if requiredFiles.allSatisfy({
                fileManager.fileExists(atPath: base.appendingPathComponent($0).path)
            }) {
                return base
            }
        }

        return nil
    }
}

/// 从 App 包里读武器表。目录由 project.yml 以 folder reference 打进 bundle，
/// 名字是 DamageData；它只含 JSON 与图片，不含网页运行时。
public final class WeaponCatalog: ObservableObject {
    public static let shared = WeaponCatalog()

    @Published public private(set) var weapons: [WeaponEntry] = []
    @Published public private(set) var failed = false
    private var extraIconIndex: [String: String] = [:]

    private init() {}

    /// App 包内计算器根目录。找不到时返回 nil，调用方负责降级。
    public static var bundleRoot: URL? {
        DamageDataBundle.root()
    }

    /// 打包进 App 的武器缩略图目录（webp）。
    public static var iconsDir: URL? {
        bundleRoot?.appendingPathComponent("icons")
    }

    /// 补充装备 / Mod / 赋能缩略图目录（webp）。
    public static var extraIconsDir: URL? {
        bundleRoot?.appendingPathComponent("extra-icons")
    }

    public func load() {
        if extraIconIndex.isEmpty, let dir = WeaponCatalog.extraIconsDir {
            let indexURL = dir.appendingPathComponent("index.json")
            if let data = try? Data(contentsOf: indexURL),
               let raw = try? JSONDecoder().decode([String: String].self, from: data) {
                var normalized: [String: String] = [:]
                normalized.reserveCapacity(raw.count * 2)
                for (key, filename) in raw {
                    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    normalized[trimmed.lowercased()] = filename
                    let clean = Self.normalizeLookupKey(trimmed)
                    if !clean.isEmpty {
                        normalized[clean] = filename
                    }
                }
                extraIconIndex = normalized
            }
        }
        guard weapons.isEmpty else { return }
        failed = false
        guard let root = WeaponCatalog.bundleRoot else {
            failed = true
            return
        }
        let url = root.appendingPathComponent("weapons-list.json")
        do {
            let data = try Data(contentsOf: url)
            weapons = try JSONDecoder().decode([WeaponEntry].self, from: data)
            failed = weapons.isEmpty
        } catch {
            failed = true
        }
    }

    /// 在额外图标表里按英文名 / 中文名 / 去后缀名解析本地图标 URL。
    public func extraIconURL(forName rawName: String?) -> URL? {
        guard let rawName else { return nil }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let dir = WeaponCatalog.extraIconsDir else { return nil }
        if extraIconIndex.isEmpty {
            load()
        }
        let filename = extraIconIndex[trimmed.lowercased()]
            ?? extraIconIndex[Self.normalizeLookupKey(trimmed)]
        guard let filename, !filename.isEmpty else { return nil }
        let fileURL = dir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    private static func normalizeLookupKey(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.uppercased().hasPrefix("<ARCHWING>") {
            text = String(text.dropFirst("<ARCHWING>".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parenRange = text.range(of: " ("), text.hasSuffix(")") {
            text = String(text[..<parenRange.lowerBound])
        } else if let parenRange = text.range(of: "（"), text.hasSuffix("）") {
            text = String(text[..<parenRange.lowerBound])
        }
        return text
            .lowercased()
            .replacingOccurrences(of: "·", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
