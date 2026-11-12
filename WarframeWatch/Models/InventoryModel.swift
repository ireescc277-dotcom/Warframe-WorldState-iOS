import Combine
import CryptoKit
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
    public let source: Source?
    public let marketAt: String?
    public let profile: Profile
    public let totals: Totals
    public let aya: AyaShop
    public let sets: [PrimeSet]
    public let relics: [RelicRow]
    public let ownedWeapons: [OwnedWeapon]

    private enum CodingKeys: String, CodingKey {
        case builtAt, source, marketAt, profile, totals, aya, sets, relics, ownedWeapons
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Old bundled samples intentionally remain readable.  Remote data uses
        // InventoryManifest for identity; builtAt is only legacy display data.
        builtAt = try c.decodeIfPresent(String.self, forKey: .builtAt)
            ?? "1970-01-01T00:00:00Z"
        source = try c.decodeIfPresent(Source.self, forKey: .source)
        marketAt = try c.decodeIfPresent(String.self, forKey: .marketAt)
        profile = try c.decode(Profile.self, forKey: .profile)
        totals = try c.decode(Totals.self, forKey: .totals)
        aya = try c.decode(AyaShop.self, forKey: .aya)
        sets = try c.decodeIfPresent([PrimeSet].self, forKey: .sets) ?? []
        relics = try c.decodeIfPresent([RelicRow].self, forKey: .relics) ?? []
        ownedWeapons = try c.decodeIfPresent([OwnedWeapon].self, forKey: .ownedWeapons) ?? []
    }

    /// Provenance of the account snapshot consumed by this payload.  The
    /// value is a SHA-256, never a DE account/item identifier.
    public struct Source: Decodable, Hashable {
        public let accountHash: String
        public let accountSync: String?
    }

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

    /// One owned weapon *instance*.  Same-name weapons deliberately stay as
    /// separate rows because Kuva/Tenet progenitor values and A/B/C configs
    /// are per instance, not per public weapon definition.
    public struct OwnedWeapon: Decodable, Identifiable, Hashable {
        public let id: String
        /// Calculator's canonical English weapon name, nil when its static
        /// data is not yet included in this app build.
        public let calcName: String?
        public let z: String
        public let category: String
        public let inventoryCategory: String
        public let progenitorElements: [String: Double]
        /// Per-unlocked-tier choices from the instance's DE SkillTree string.
        /// The calculator maps their positions to its own tier IDs after the
        /// weapon definition has loaded.
        public let incarnonChoices: [Int]
        public let configs: [Config]

        private enum CodingKeys: String, CodingKey {
            case id, n, z, c, k, p, inc, cfg
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            calcName = try c.decodeIfPresent(String.self, forKey: .n)
            z = try c.decode(String.self, forKey: .z)
            category = try c.decodeIfPresent(String.self, forKey: .c) ?? "Unknown"
            inventoryCategory = try c.decodeIfPresent(String.self, forKey: .k) ?? "Unknown"
            progenitorElements = try c.decodeIfPresent([String: Double].self, forKey: .p) ?? [:]
            incarnonChoices = try c.decodeIfPresent([Int].self, forKey: .inc) ?? []
            configs = try c.decodeIfPresent([Config].self, forKey: .cfg) ?? []
        }

        public var isCalculable: Bool { calcName != nil }

        public var categoryLabel: String {
            switch category {
            case "Primary": return "主武器"
            case "Secondary": return "副武器"
            case "Melee": return "近战"
            case "Archgun": return "Archwing 枪械"
            case "Archmelee": return "Archwing 近战"
            case "Companion": return "同伴武器"
            default: return category
            }
        }

        public struct Config: Decodable, Hashable, Identifiable {
            public let label: String
            /// DamageKit's stable slots: 0...8, melee stance 9, Arcane 10.
            public let slots: [String?]
            public let riven: ImportedRiven?
            public let rivenSlot: Int?
            /// False means a slot was intentionally not promoted to a max-rank
            /// Mod.  The app must show that fact rather than silently changing
            /// a player's build.
            public let isExactImport: Bool
            public let issues: [String]

            public var id: String { label }
            public var normalizedSlots: [String?] {
                Array(slots.prefix(11)) + Array(repeating: nil, count: max(0, 11 - slots.count))
            }

            private enum CodingKeys: String, CodingKey {
                case l, s, r, rs, exact, issues
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                label = try c.decodeIfPresent(String.self, forKey: .l) ?? "A"
                slots = try c.decodeIfPresent([String?].self, forKey: .s) ?? []
                riven = try c.decodeIfPresent(ImportedRiven.self, forKey: .r)
                rivenSlot = try c.decodeIfPresent(Int.self, forKey: .rs)
                isExactImport = try c.decodeIfPresent(Bool.self, forKey: .exact) ?? true
                issues = try c.decodeIfPresent([String].self, forKey: .issues) ?? []
            }
        }

        /// Resolved numerical purple-card effects.  Values use DamageKit's
        /// decimal units (0.9 = +90%); no private Riven instance data leaves
        /// the local Aleca snapshot.
        public struct ImportedRiven: Decodable, Hashable {
            public let name: String
            public let damage: Double?
            public let multishot: Double?
            public let critChance: Double?
            public let critDamage: Double?
            public let statusChance: Double?
            public let statusDuration: Double?
            public let fireRate: Double?
            public let reloadSpeed: Double?
            public let faction: Double?
            public let factionBonuses: [String: Double]?
            public let elements: [String: Double]?
            public let physical: [String: Double]?
        }
    }
}

public struct PrimeSet: Decodable, Identifiable {
    public let id: String
    public let zh: String
    public let cat: String
    public let i: String?           // Asset Catalog 里的缩略图名
    public let u: String?           // CDN 相对路径，本地没有图时兜底
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
    public let i: String?            // 同一纪元的遗物共用一张图
    public let u: String?
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
        public let i: String?
        public let u: String?
        public let p: Int
        public let owned: Bool
    }
}

// MARK: - 加载

/// The immutable pointer published by `scripts/wf_publish.py`.
///
/// The payload is uploaded and SHA-256 verified on the VPS *before* this
/// small manifest is atomically switched.  `publishedAt` therefore describes
/// the exact bytes named by `snapshotId`, not when an unrelated build ran.
public struct InventoryManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let snapshotId: String
    public let contentHash: String
    public let payload: String
    public let bytes: Int
    public let publishedAt: String
    public let sourceHash: String?
    public let sourceSync: String?
    public let sourceObservedAt: String?

    public var isValid: Bool {
        schemaVersion == 2
            && snapshotId == contentHash
            && InventoryStore.isSHA256(contentHash)
            && !payload.isEmpty
            && !payload.hasPrefix("/")
            && !payload.contains("..")
            && (sourceHash == nil || InventoryStore.isSHA256(sourceHash ?? ""))
            && bytes >= 0
    }
}

enum InventorySnapshotError: LocalizedError {
    case invalidManifest
    case invalidPayloadURL
    case badHTTP(Int)
    case contentHashMismatch
    case badPayload

    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "背包版本清单无效"
        case .invalidPayloadURL: return "背包版本清单中的数据地址无效"
        case .badHTTP(let code): return "背包同步请求返回 HTTP \(code)"
        case .contentHashMismatch: return "背包数据校验和与版本清单不一致"
        case .badPayload: return "背包数据无法解码"
        }
    }
}

struct InventoryStoredSnapshot {
    let data: InventoryData
    let manifest: InventoryManifest?
}

public enum InventoryStore {
    /// 远端 manifest 的位置。账号数据在 VPS 上，App 只负责验证、取和缓存。
    ///
    /// 地址不写在源码里：CI 打包后用 PlistBuddy 写进 Info.plist，
    /// 值来自仓库 secret。仓库公开也读不到这个链接。
    public static var remote: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: InventoryRemote.key) as? String,
              !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// First launch uses one coherent cached pair, otherwise the bundled
    /// sample.  There is deliberately no `max(builtAt)` comparison here: a
    /// timestamp can never select a payload from another snapshot.
    static func localized() -> InventoryStoredSnapshot? {
        cached() ?? bundled()
    }

    static func bundled() -> InventoryStoredSnapshot? {
        let urls: [URL?] = [
            Bundle.main.url(forResource: "InventoryData", withExtension: "json"),
            Bundle.main.url(forResource: "InventoryData", withExtension: "json",
                            subdirectory: "Resources"),
            Bundle.main.bundleURL.appendingPathComponent("InventoryData.json"),
        ]
        for case let url? in urls {
            if let data = try? Data(contentsOf: url), let doc = decode(data) {
                return InventoryStoredSnapshot(data: doc, manifest: nil)
            }
        }
        return nil
    }

    static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("InventorySnapshots", isDirectory: true)
    }

    static var cacheManifestURL: URL {
        cacheDirectory.appendingPathComponent("current-manifest.json")
    }

    static func payloadURL(snapshotID: String) -> URL? {
        guard isSHA256(snapshotID) else { return nil }
        return cacheDirectory.appendingPathComponent("\(snapshotID).json")
    }

    static func cached() -> InventoryStoredSnapshot? {
        guard let rawManifest = try? Data(contentsOf: cacheManifestURL),
              let manifest = try? JSONDecoder().decode(InventoryManifest.self, from: rawManifest),
              manifest.isValid,
              let payloadURL = payloadURL(snapshotID: manifest.snapshotId),
              let rawPayload = try? Data(contentsOf: payloadURL),
              sha256(rawPayload) == manifest.contentHash,
              let doc = decode(rawPayload)
        else { return nil }
        return InventoryStoredSnapshot(data: doc, manifest: manifest)
    }

    static func decode(_ data: Data) -> InventoryData? {
        do {
            return try JSONDecoder().decode(InventoryData.self, from: data)
        } catch {
            print("InventoryData 解码失败：\(error)")
            return nil
        }
    }

    static func persist(_ rawPayload: Data, manifest: InventoryManifest) throws {
        guard manifest.isValid, sha256(rawPayload) == manifest.contentHash,
              let payloadURL = payloadURL(snapshotID: manifest.snapshotId) else {
            throw InventorySnapshotError.contentHashMismatch
        }
        try FileManager.default.createDirectory(at: cacheDirectory,
                                                withIntermediateDirectories: true)
        // Immutable payload first, pointer second.  A termination between the
        // two leaves the old manifest usable; it can never point to partial
        // bytes from the new version.
        try rawPayload.write(to: payloadURL, options: .atomic)
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: cacheManifestURL, options: .atomic)
    }

    static func payloadURL(for manifest: InventoryManifest, relativeTo remote: URL) -> URL? {
        guard manifest.isValid else { return nil }
        return URL(string: manifest.payload, relativeTo: remote)?.absoluteURL
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value)
        }
    }
}

/// 拿到新数据后，界面要跟着换，所以套一层可观察对象。
///
/// 类本身不是 `@MainActor`：`shared` 要在 View 的属性初始化器里访问，
/// 那里是同步的非隔离上下文。只有写 `@Published` 的 `refresh` 标了主线程。
public final class InventoryFeed: ObservableObject {
    public static let shared = InventoryFeed()

    @Published public private(set) var data: InventoryData?
    @Published public private(set) var manifest: InventoryManifest?
    @Published public private(set) var fetching = false
    @Published public private(set) var failed = false
    /// Local time when this device successfully verified and applied the
    /// current manifest/payload pair.  It is never presented as server time.
    @Published public private(set) var appliedAt: String?
    @Published public private(set) var lastError: String?

    private init() {
        if let local = InventoryStore.localized() {
            data = local.data
            manifest = local.manifest
        }
    }

    /// 拉 VPS 上的那一份。失败就继续用手里的，不清空。
    @MainActor
    public func refresh() async {
        guard let remote = InventoryStore.remote else { return }
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }

        var request = URLRequest(url: remote)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (rawManifest, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw InventorySnapshotError.badHTTP((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let candidate = try JSONDecoder().decode(InventoryManifest.self, from: rawManifest)
            guard candidate.isValid else { throw InventorySnapshotError.invalidManifest }

            // Same immutable content means exactly the same display version;
            // do not update a time label merely because the user pulled again.
            if let current = manifest,
               current.snapshotId == candidate.snapshotId,
               current.contentHash == candidate.contentHash {
                failed = false
                lastError = nil
                return
            }

            guard let payloadURL = InventoryStore.payloadURL(for: candidate, relativeTo: remote) else {
                throw InventorySnapshotError.invalidPayloadURL
            }
            var payloadRequest = URLRequest(url: payloadURL)
            payloadRequest.timeoutInterval = 20
            payloadRequest.cachePolicy = .reloadIgnoringLocalCacheData
            let (rawPayload, payloadResponse) = try await URLSession.shared.data(for: payloadRequest)
            guard let payloadHTTP = payloadResponse as? HTTPURLResponse,
                  payloadHTTP.statusCode == 200 else {
                throw InventorySnapshotError.badHTTP((payloadResponse as? HTTPURLResponse)?.statusCode ?? -1)
            }
            guard rawPayload.count == candidate.bytes,
                  InventoryStore.sha256(rawPayload) == candidate.contentHash else {
                throw InventorySnapshotError.contentHashMismatch
            }
            guard let doc = InventoryStore.decode(rawPayload) else {
                throw InventorySnapshotError.badPayload
            }
            if let sourceHash = candidate.sourceHash,
               doc.source?.accountHash != sourceHash {
                throw InventorySnapshotError.badPayload
            }
            try InventoryStore.persist(rawPayload, manifest: candidate)
            data = doc
            manifest = candidate
            appliedAt = Self.isoNow()
            failed = false
            lastError = nil
        } catch {
            failed = true
            lastError = error.localizedDescription
        }
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

/// 部署时改这里。空的就只用内置快照。
public enum InventoryRemote {
    /// 这个地址由 CI 写进 Info.plist，源码里不出现。
    public static let key = "InventoryURL"
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
