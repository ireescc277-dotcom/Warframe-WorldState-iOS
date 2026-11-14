import Combine
import Foundation

/// On-demand downloader & persistent disk cache for static Warframe artwork,
/// icons, polarity glyphs, and Mod card chrome (~55 MB) hosted on the server
/// instead of bundled inside the `.ipa`.
///
/// Lookup priority for every asset relative path (e.g. `mod-frames/GoldFrame.png`):
///   1. Local disk cache (`Library/Application Support/DamageAssets/...`)
///   2. App bundle (`DamageData/...`, present in CI offline simulator builds)
///   3. Background HTTPS download from `baseURL` with atomic disk write &
///      debounced SwiftUI invalidation via `@Published var revision`.
public final class RemoteAssetStore: ObservableObject, @unchecked Sendable {
    public static let shared = RemoteAssetStore()

    public struct ManifestEntry: Codable, Hashable {
        public let p: String
        public let s: Int
        public let h: String?
    }

    public struct Manifest: Codable {
        public let version: String
        public let generatedAt: String?
        public let fileCount: Int
        public let totalBytes: Int
        public let files: [ManifestEntry]
    }

    /// Bumped whenever one or more new assets land on disk so observing SwiftUI
    /// views redraw automatically without polling.
    @Published public private(set) var revision: UInt64 = 0
    @Published public private(set) var manifestCount: Int = 0
    @Published public private(set) var manifestBytes: Int64 = 0
    @Published public private(set) var cachedCount: Int = 0
    @Published public private(set) var cachedBytes: Int64 = 0
    @Published public private(set) var isDownloadingPack: Bool = false
    @Published public private(set) var packProgress: Double = 0
    @Published public private(set) var lastErrorMessage: String?

    public let baseURL: URL
    public let cacheRoot: URL

    private let session: URLSession
    private let lock = NSLock()
    private var diskPaths: Set<String> = []
    private var missingBundlePaths: Set<String> = []
    private var inFlight: Set<String> = []
    private var failedAt: [String: Date] = [:]
    private var pendingQueue: [String] = []
    private var activeDownloads: Int = 0
    private var notifyScheduled: Bool = false
    private var manifestEntries: [ManifestEntry] = []
    private var prefetchStarted = false

    private let maxConcurrent = 8
    private let failureCooldown: TimeInterval = 30
    private static let defaultPublicURL = URL(string: "https://data.ireescc.com/wf-assets/")!

    public init(
        baseURL: URL? = nil,
        cacheRoot: URL? = nil,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL ?? Self.resolveBaseURL()
        self.cacheRoot = cacheRoot ?? Self.defaultCacheRoot()

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 60
            config.httpMaximumConnectionsPerHost = 8
            config.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: config)
        }

        ensureCacheRootExcludedFromBackup()
        loadCachedManifestSummary()
        scanDiskCacheIndex()
    }

    private static func resolveBaseURL() -> URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "AssetBaseURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed.hasSuffix("/") ? trimmed : trimmed + "/") {
                return url
            }
        }
        if let inv = InventoryStore.remote,
           var comps = URLComponents(url: inv, resolvingAgainstBaseURL: false) {
            comps.path = "/wf-assets/"
            comps.query = nil
            comps.fragment = nil
            if let derived = comps.url {
                return derived
            }
        }
        return defaultPublicURL
    }

    private static func defaultCacheRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DamageAssets", isDirectory: true)
    }

    private func ensureCacheRootExcludedFromBackup() {
        let fm = FileManager.default
        try? fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        var url = cacheRoot
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func scanDiskCacheIndex() {
        let fm = FileManager.default
        let root = cacheRoot
        var found = Set<String>()
        var bytes: Int64 = 0

        if let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            let basePath = root.standardizedFileURL.path
            for case let fileURL as URL in enumerator {
                guard let rv = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      rv.isRegularFile == true else { continue }
                let fullPath = fileURL.standardizedFileURL.path
                guard fullPath.hasPrefix(basePath + "/") else { continue }
                let rel = String(fullPath.dropFirst(basePath.count + 1))
                if rel == "manifest.json" || rel.hasSuffix(".tmp") { continue }
                found.insert(rel)
                bytes += Int64(rv.fileSize ?? 0)
            }
        }

        lock.lock()
        diskPaths = found
        lock.unlock()

        DispatchQueue.main.async {
            self.cachedCount = found.count
            self.cachedBytes = bytes
        }
    }

    private func loadCachedManifestSummary() {
        let manifestURL = cacheRoot.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode(Manifest.self, from: data) else { return }
        lock.lock()
        manifestEntries = decoded.files
        lock.unlock()
        manifestCount = decoded.fileCount
        manifestBytes = Int64(decoded.totalBytes)
    }

    /// Returns the server HTTPS URL for any asset relative path (e.g. `icons/Torid.webp`).
    public func remoteURL(forRelativePath rawPath: String) -> URL? {
        let rel = normalize(rawPath)
        guard !rel.isEmpty else { return nil }
        return rel.split(separator: "/").reduce(baseURL) { partial, segment in
            partial.appendingPathComponent(String(segment))
        }
    }

    /// Returns an existing local file URL (from persistent disk cache or app bundle).
    /// When absent, enqueues an asynchronous server download and returns `nil`.
    public func resolveOrFetch(relativePath rawPath: String, highPriority: Bool = false) -> URL? {
        let rel = normalize(rawPath)
        guard !rel.isEmpty else { return nil }

        let diskURL = cacheRoot.appendingPathComponent(rel)
        lock.lock()
        let onDisk = diskPaths.contains(rel)
        let bundleKnownMissing = missingBundlePaths.contains(rel)
        lock.unlock()

        if onDisk {
            if FileManager.default.fileExists(atPath: diskURL.path) {
                return diskURL
            }
            lock.lock()
            diskPaths.remove(rel)
            lock.unlock()
        }

        if !bundleKnownMissing, let bundleURL = DamageDataBundle.root()?.appendingPathComponent(rel) {
            if FileManager.default.fileExists(atPath: bundleURL.path) {
                return bundleURL
            }
            lock.lock()
            missingBundlePaths.insert(rel)
            lock.unlock()
        }

        enqueueDownload(rel, highPriority: highPriority)
        return nil
    }

    /// Fetches `manifest.json` from the server and immediately caches Mod card chrome
    /// (`mod-frames/` and `polarities/`, ~2.1 MB total) on launch.
    public func prefetchCoreChromeIfNeeded() {
        lock.lock()
        let shouldStart = !prefetchStarted
        if shouldStart { prefetchStarted = true }
        lock.unlock()
        guard shouldStart else { return }

        Task.detached(priority: .utility) { [weak self] in
            await self?.syncManifestAndCoreChrome()
        }
    }

    public func syncManifestAndCoreChrome() async {
        guard let manifest = await fetchManifest() else { return }
        let chromePaths = manifest.files
            .map(\.p)
            .filter { $0.hasPrefix("mod-frames/") || $0.hasPrefix("polarities/") }
        enqueueBatchIfMissing(chromePaths, entriesByPath: Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.p, $0) }))
    }

    /// Downloads every asset listed in the server manifest so the app can run
    /// 100% offline. Safe to invoke multiple times; already-cached matching files
    /// are skipped.
    @MainActor
    public func downloadAllAssets() async {
        guard !isDownloadingPack else { return }
        isDownloadingPack = true
        lastErrorMessage = nil
        packProgress = 0
        defer { isDownloadingPack = false }

        guard let manifest = await fetchManifest() else {
            lastErrorMessage = "无法连接资源服务器获取清单"
            return
        }

        let files = manifest.files
        let total = max(1, files.count)
        let missing = await Task.detached(priority: .utility) { [weak self] () -> [String] in
            guard let self else { return [] }
            return files.compactMap { entry -> String? in
                self.needsDownload(entry: entry) ? entry.p : nil
            }
        }.value

        if missing.isEmpty {
            packProgress = 1.0
            scanDiskCacheIndex()
            return
        }

        let alreadyHave = total - missing.count
        var completed = 0
        packProgress = Double(alreadyHave) / Double(total)

        await withTaskGroup(of: Bool.self) { group in
            var index = 0
            let initial = min(maxConcurrent, missing.count)
            for _ in 0..<initial {
                let rel = missing[index]
                index += 1
                group.addTask { await self.downloadSingle(rel) }
            }
            for await _ in group {
                completed += 1
                self.packProgress = min(1.0, Double(alreadyHave + completed) / Double(total))
                if index < missing.count {
                    let rel = missing[index]
                    index += 1
                    group.addTask { await self.downloadSingle(rel) }
                }
            }
        }

        scanDiskCacheIndex()
        notifyRevision()
    }

    public func clearCache() {
        let fm = FileManager.default
        lock.lock()
        diskPaths.removeAll()
        failedAt.removeAll()
        pendingQueue.removeAll()
        lock.unlock()

        try? fm.removeItem(at: cacheRoot)
        ensureCacheRootExcludedFromBackup()

        DispatchQueue.main.async {
            self.cachedCount = 0
            self.cachedBytes = 0
            self.packProgress = 0
            self.revision &+= 1
        }
    }

    // MARK: - Internal Queue & Validation

    private func fetchManifest() async -> Manifest? {
        guard let url = remoteURL(forRelativePath: "manifest.json") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("WarframeWatch/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            let localManifest = cacheRoot.appendingPathComponent("manifest.json")
            try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            try? data.write(to: localManifest, options: .atomic)

            setManifestEntries(manifest.files)

            await MainActor.run {
                self.manifestCount = manifest.fileCount
                self.manifestBytes = Int64(manifest.totalBytes)
            }
            return manifest
        } catch {
            return nil
        }
    }

    private func setManifestEntries(_ files: [ManifestEntry]) {
        lock.lock()
        manifestEntries = files
        lock.unlock()
    }

    private func popNextQueuedItem() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if !pendingQueue.isEmpty {
            return pendingQueue.removeFirst()
        }
        activeDownloads = max(0, activeDownloads - 1)
        return nil
    }

    private func finishInFlight(_ rel: String) {
        lock.lock()
        inFlight.remove(rel)
        lock.unlock()
    }

    private func markDownloadFailed(_ rel: String) {
        lock.lock()
        failedAt[rel] = Date()
        lock.unlock()
    }

    private func markDownloadSucceeded(_ rel: String) -> Bool {
        lock.lock()
        let isNew = diskPaths.insert(rel).inserted
        failedAt.removeValue(forKey: rel)
        lock.unlock()
        return isNew
    }

    private func needsDownload(entry: ManifestEntry) -> Bool {
        let rel = entry.p
        let diskURL = cacheRoot.appendingPathComponent(rel)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: diskURL.path),
           let size = attrs[.size] as? Int, size == entry.s {
            return false
        }
        if let bundleURL = DamageDataBundle.root()?.appendingPathComponent(rel),
           let attrs = try? FileManager.default.attributesOfItem(atPath: bundleURL.path),
           let size = attrs[.size] as? Int, size == entry.s {
            return false
        }
        return true
    }

    private func enqueueBatchIfMissing(_ paths: [String], entriesByPath: [String: ManifestEntry]) {
        for rel in paths {
            if let entry = entriesByPath[rel] {
                guard needsDownload(entry: entry) else { continue }
                // If an older copy with a different size exists on disk, drop it from
                // the in-memory set so the updated server version is fetched.
                lock.lock()
                diskPaths.remove(rel)
                lock.unlock()
            }
            enqueueDownload(rel, highPriority: true)
        }
    }

    private func enqueueDownload(_ rel: String, highPriority: Bool) {
        let now = Date()
        var toLaunch: [String] = []

        lock.lock()
        if !diskPaths.contains(rel), !inFlight.contains(rel) {
            if let lastFail = failedAt[rel], now.timeIntervalSince(lastFail) < failureCooldown {
                lock.unlock()
                return
            }
            inFlight.insert(rel)
            if highPriority {
                pendingQueue.insert(rel, at: 0)
            } else {
                pendingQueue.append(rel)
            }
        }

        while activeDownloads < maxConcurrent, !pendingQueue.isEmpty {
            let next = pendingQueue.removeFirst()
            activeDownloads += 1
            toLaunch.append(next)
        }
        lock.unlock()

        for item in toLaunch {
            Task.detached(priority: .utility) { [weak self] in
                await self?.processQueueItem(item)
            }
        }
    }

    private func processQueueItem(_ initialItem: String) async {
        var current: String? = initialItem
        while let rel = current {
            _ = await downloadSingle(rel)
            current = popNextQueuedItem()
        }
    }

    @discardableResult
    private func downloadSingle(_ rel: String) async -> Bool {
        defer { finishInFlight(rel) }

        guard let url = remoteURL(forRelativePath: rel) else { return false }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  Self.isValidPayload(data, forRelativePath: rel) else {
                markDownloadFailed(rel)
                return false
            }

            let dst = cacheRoot.appendingPathComponent(rel)
            let parent = dst.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try data.write(to: dst, options: .atomic)

            let isNew = markDownloadSucceeded(rel)
            let deltaBytes = Int64(data.count)
            DispatchQueue.main.async {
                if isNew {
                    self.cachedCount += 1
                    self.cachedBytes += deltaBytes
                }
                self.scheduleRevisionBump()
            }
            return true
        } catch {
            markDownloadFailed(rel)
            return false
        }
    }

    private func scheduleRevisionBump() {
        lock.lock()
        let already = notifyScheduled
        if !already { notifyScheduled = true }
        lock.unlock()
        guard !already else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.lock.lock()
            self.notifyScheduled = false
            self.lock.unlock()
            self.revision &+= 1
        }
    }

    private func notifyRevision() {
        DispatchQueue.main.async {
            self.revision &+= 1
        }
    }

    private func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Rejects non-image responses (e.g. HTML error pages) before writing to disk.
    public static func isValidPayload(_ data: Data, forRelativePath rel: String) -> Bool {
        guard !data.isEmpty else { return false }
        let lower = rel.lowercased()
        if lower.hasSuffix(".png") {
            let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
            return data.count >= 8 && Array(data.prefix(4)) == pngMagic
        }
        if lower.hasSuffix(".webp") {
            guard data.count >= 12 else { return false }
            let head = Array(data.prefix(12))
            return head[0...3] == [0x52, 0x49, 0x46, 0x46] // RIFF
                && head[8...11] == [0x57, 0x45, 0x42, 0x50] // WEBP
        }
        if lower.hasSuffix(".json") {
            guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                let first = text.first else { return false }
            return first == "{" || first == "["
        }
        return true
    }
}
