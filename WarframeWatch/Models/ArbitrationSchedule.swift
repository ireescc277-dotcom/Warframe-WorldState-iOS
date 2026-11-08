import Foundation

/// 仲裁排程。
///
/// 仲裁不是随机的：browse.wf 的轮换表是确定性的，每小时换一个节点，已经排到
/// 2029 年。所以对仲裁算「24 小时内出现的概率」是降级——真正该显示的是
/// 「下一场几点、哪个节点」。
///
/// 附带解决另一件事：`api.warframestat.us/pc/arbitration` 现在永远返回
/// `SolNode000` 占位（activation 1970、expiry +275760），这份排程是唯一
/// 还能用的来源。
public struct ArbitrationSchedule: Decodable {
    struct Slot: Decodable {
        let t: Int
        let n: String
    }

    enum CodingKeys: String, CodingKey {
        case builtAt, slot, slots
    }

    /// 生成时间（epoch 秒）。远端比手里旧就不替换。
    public let builtAt: Int
    /// 单场时长，目前固定 3600。
    public let slot: Int

    private let starts: [Date]
    private let nodes: [String]
    private let byNode: [String: [Date]]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        builtAt = (try? container.decode(Int.self, forKey: .builtAt)) ?? 0
        let length = (try? container.decode(Int.self, forKey: .slot)) ?? 3600
        slot = length > 0 ? length : 3600

        let raw = (try? container.decode([Slot].self, forKey: .slots)) ?? []
        let sorted = raw.sorted { $0.t < $1.t }
        starts = sorted.map { Date(timeIntervalSince1970: TimeInterval($0.t)) }
        nodes = sorted.map(\.n)

        var index: [String: [Date]] = [:]
        for entry in sorted {
            index[entry.n, default: []].append(Date(timeIntervalSince1970: TimeInterval(entry.t)))
        }
        byNode = index
    }

    public var isEmpty: Bool { starts.isEmpty }

    /// 排程覆盖到哪一刻为止。过了这一刻就不能再拿它当依据。
    public var coverageEnd: Date? {
        starts.last.map { $0.addingTimeInterval(TimeInterval(slot)) }
    }

    public func covers(_ now: Date) -> Bool {
        guard let first = starts.first, let end = coverageEnd else { return false }
        return now >= first && now < end
    }

    /// 此刻正在跑的那一场。排程有缺口时返回 nil，不硬凑。
    public func current(at now: Date) -> (node: String, start: Date, end: Date)? {
        guard let index = lastIndex(atOrBefore: now) else { return nil }
        let end = starts[index].addingTimeInterval(TimeInterval(slot))
        guard now < end else { return nil }
        return (nodes[index], starts[index], end)
    }

    public func next(after now: Date) -> (node: String, start: Date)? {
        let index = firstIndex(after: now)
        guard index < starts.count else { return nil }
        return (nodes[index], starts[index])
    }

    /// 某个节点下一次出现的时间。界面上的「下次 04:00」用它。
    public func nextDate(forNode node: String, after now: Date) -> Date? {
        guard let dates = byNode[node], !dates.isEmpty else { return nil }
        var low = 0
        var high = dates.count - 1
        var found = dates.count
        while low <= high {
            let mid = (low + high) / 2
            if dates[mid] > now {
                found = mid
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return found < dates.count ? dates[found] : nil
    }

    private func lastIndex(atOrBefore date: Date) -> Int? {
        var low = 0
        var high = starts.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= date {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    private func firstIndex(after date: Date) -> Int {
        var low = 0
        var high = starts.count - 1
        var found = starts.count
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] > date {
                found = mid
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return found
    }
}

// MARK: - 取用

/// 排程的三种来源：VPS、本机缓存、包里带的。
///
/// 地址不单独配置：它和背包快照放在同一个目录，由背包地址推出来。
/// 少一个 secret，也就不会出现「背包换了地址、排程还指着旧域名」。
public enum ArbitrationScheduleStore {
    public static var remote: URL? {
        guard let inventory = InventoryStore.remote else { return nil }
        return inventory.deletingLastPathComponent().appendingPathComponent("arb.json")
    }

    public static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("ArbSchedule.json")
    }

    /// 现在能用的那一份：优先远端缓存，其次包里那份；两者都要覆盖此刻，
    /// 否则宁可显示「排程未更新」，也不拿一个月前的表糊弄人。
    public static func localized(at now: Date = Date()) -> ArbitrationSchedule? {
        let candidates = [cached(), bundled()].compactMap { $0 }.filter { $0.covers(now) }
        return candidates.max { $0.builtAt < $1.builtAt }
    }

    static func decode(_ data: Data) -> ArbitrationSchedule? {
        do {
            return try JSONDecoder().decode(ArbitrationSchedule.self, from: data)
        } catch {
            print("ArbSchedule 解码失败：\(error)")
            return nil
        }
    }

    static func bundled() -> ArbitrationSchedule? {
        let urls: [URL?] = [
            Bundle.main.url(forResource: "ArbSchedule", withExtension: "json"),
            Bundle.main.url(forResource: "ArbSchedule", withExtension: "json", subdirectory: "Resources"),
            Bundle.main.bundleURL.appendingPathComponent("ArbSchedule.json"),
        ]
        for case let url? in urls {
            if let data = try? Data(contentsOf: url), let doc = decode(data) {
                return doc
            }
        }
        return nil
    }

    static func cached() -> ArbitrationSchedule? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return decode(data)
    }

    /// 拉 VPS 上那份。失败返回 nil，调用方保留手里的旧表。
    public static func fetch() async -> ArbitrationSchedule? {
        guard let url = ArbitrationScheduleStore.remote else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadRevalidatingCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let doc = decode(data), !doc.isEmpty else { return nil }
            try? data.write(to: cacheURL, options: .atomic)
            return doc
        } catch {
            return nil
        }
    }
}
