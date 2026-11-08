import Foundation

/// 背包资产的离线快照。
///
/// 数据由 `scripts/build_app_inventory.py` 生成：背包来自 AlecaFrame 的
/// `lastData.dat`（静态 AES key 本地解密，不联网、不读进程内存），价格来自
/// warframe.market v2，Ducats 来自 DE 的 Components 表。
///
/// 价格口径只用**在线卖家的最低价**。market 上有人挂 1p 钓鱼单，
/// 用「全部卖单最低价」会把 Lavos Prime 套装算成 1p。
public struct InventoryData: Decodable {
    public let builtAt: String
    public let marketAt: String?
    public let profile: Profile
    public let totals: Totals
    public let aya: AyaShop
    public let sets: [PrimeSet]
    public let relics: [RelicRow]

    public struct Profile: Decodable {
        public let mr: Int
        public let plat: Int
        public let credits: Int
        public let sync: String?
    }

    public struct Totals: Decodable {
        public let setsOwned: Int
        public let setsReady: Int
        public let setsClose: Int
        public let setsAll: Int
        public let loosePlat: Int
        public let looseDucats: Int
        public let relicKinds: Int
        public let relicUnits: Int
        public let mods: Int
    }
}

public struct PrimeSet: Decodable, Identifiable {
    public let id: String
    public let zh: String
    public let cat: String
    public let status: String        // owned / ready / missing
    public let have: Int
    public let total: Int
    public let parts: [Part]
    public let setPrice: Int
    public let partsValue: Int
    public let loose: Int            // 可卖散件的白金
    public let relics: [String]

    public struct Part: Decodable, Identifiable {
        public let l: String         // 中文部件名：蓝图 / 机体 / 头部神经光元 / 系统
        public let n: Int            // 持有数
        public let p: Int            // 市场价
        public let d: Int            // Ducats
        public var id: String { l }
        public var owned: Bool { n > 0 }
    }

    public var missing: Int { max(total - have, 0) }
    public var isOwned: Bool { status == "owned" }
    public var isReady: Bool { status == "ready" }

    /// 拆开卖零件比整套卖多的差额。正数说明拆卖更划算。
    public var splitGain: Int { partsValue - setPrice }
}

public struct RelicRow: Decodable, Identifiable {
    public let id: String            // 古纪 C10
    public let era: String
    public let code: String
    public let st: [String: Int]     // I/E/F/R 四档持有
    public let n: Int                // 合计持有
    public let p: Int                // 市场价（按代号，不含精炼档）
    public let miss: Int             // 能出的、我还没有的套装数
    public let own: Int              // 能出的、我已有的套装数

    public var refine: [(String, Int)] {
        [("完整", st["I"] ?? 0), ("优良", st["E"] ?? 0),
         ("无瑕", st["F"] ?? 0), ("光辉", st["R"] ?? 0)]
    }
}

public struct AyaShop: Decodable {
    public let activation: String?
    public let expiry: String?
    public let location: String?
    public let items: [Item]

    public struct Item: Decodable, Identifiable {
        public let id: String
        public let p: Int
        public let owned: Bool
    }
}

// MARK: - 加载

public enum InventoryStore {
    /// 只在首次访问时解码。文件 100 KB 上下，一次性读完留在内存里，
    /// 免得每次切 tab 都去碰磁盘。
    public static let shared: InventoryData? = load()

    private static func load() -> InventoryData? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "InventoryData", withExtension: "json"),
            Bundle.main.url(forResource: "InventoryData", withExtension: "json",
                            subdirectory: "Resources"),
            Bundle.main.bundleURL.appendingPathComponent("InventoryData.json"),
        ]
        for case let url? in candidates {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                return try JSONDecoder().decode(InventoryData.self, from: data)
            } catch {
                print("InventoryData 解码失败：\(error)")
            }
        }
        return nil
    }
}

// MARK: - 格式化

public enum AssetFormat {
    public static func plat(_ value: Int) -> String {
        value >= 1000 ? grouped(value) : "\(value)"
    }

    public static func grouped(_ value: Int) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.groupingSeparator = ","
        return n.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// `2026-11-08T09:38:00Z` → `11-08 17:38`（本地时区）
    ///
    /// DE 的时间戳带毫秒（`...T18:00:00.000Z`），默认的 ISO8601 解析器不认，
    /// 所以带小数秒要再试一次，否则像「本期到 —」这种空值会静默混进界面。
    public static func stamp(_ iso: String?) -> String {
        guard let iso = iso else { return "—" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        var date = parser.date(from: iso)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = parser.date(from: iso)
        }
        guard let parsed = date else { return "—" }
        let out = DateFormatter()
        out.dateFormat = "MM-dd HH:mm"
        return out.string(from: parsed)
    }
}
