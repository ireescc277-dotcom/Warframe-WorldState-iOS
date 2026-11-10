import Network
import SwiftUI
import WebKit

/// 伤害计算器。页面本体是 `web/app`，作为 folder reference 打进 App 包。
///
/// 用了一个 127.0.0.1 上的极简静态服务来喂页面，而不是 `loadFileURL` 或自定义
/// scheme：WebKit 的 `fetch()` 只认 http/https，file:// 和 wfapp:// 下页面里的
/// 数据请求会被直接拒掉，内核就永远起不来。回环 http 和线上环境一致，没有特例。
public struct DamageCalcView: View {
    /// nil 表示空计算器：进去自己选武器、自己配卡。
    private let weapon: String?
    private let title: String

    @State private var ready = false
    @State private var failure: String?

    public init(weapon: String? = nil, title: String = "伤害计算") {
        self.weapon = weapon
        self.title = title
    }

    public var body: some View {
        ZStack {
            WFTheme.bgPrimary.ignoresSafeArea()

            CalcWebView(weapon: weapon, ready: $ready, failure: $failure)
                .ignoresSafeArea(edges: .bottom)

            if !ready {
                VStack(spacing: WFUI.s3) {
                    if let failure = failure {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 22))
                            .foregroundColor(WFTheme.red)
                        Text(failure)
                            .font(.wfBody)
                            .foregroundColor(WFTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else {
                        ProgressView()
                            .tint(WFTheme.gold)
                        Text("加载计算内核…")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.textMuted)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(WFTheme.bgSecondary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - WebView

private struct CalcWebView: UIViewRepresentable {
    let weapon: String?
    @Binding var ready: Bool
    @Binding var failure: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(ready: $ready, failure: $failure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = UIColor(WFTheme.bgPrimary)
        web.scrollView.backgroundColor = UIColor(WFTheme.bgPrimary)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) { web.isInspectable = true }

        guard let root = WeaponCatalog.bundleRoot else {
            DispatchQueue.main.async { failure = "App 包里没有计算器资源（ios/DamageCalc）" }
            return web
        }

        let server = LocalStaticServer.shared(root: root)
        let port = server.start()
        guard port > 0 else {
            DispatchQueue.main.async { failure = "本地计算服务没能启动" }
            return web
        }
        context.coordinator.server = server

        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = "127.0.0.1"
        comps.port = Int(port)
        comps.path = "/index.html"
        if let weapon = weapon {
            comps.queryItems = [URLQueryItem(name: "weapon", value: weapon)]
        }
        if let url = comps.url {
            web.load(URLRequest(url: url))
            // 兜底：didFinish 不一定会来（有资源一直挂着就不会来），
            // 那 waitForKernel 根本不会启动，页面就永远转圈、且看不到任何原因。
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak coordinator = context.coordinator] in
                guard let c = coordinator, !c.ready.wrappedValue else { return }
                c.diagnose(web, then: "9 秒还没就绪")
            }
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 服务故意不关：它是共享的，关了下次启动要重新抢端口，抢不到就换 origin。
        // 回环网卡上挂个只读文件服务，代价可以忽略，App 退出时随进程一起没。
        coordinator.server = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let ready: Binding<Bool>
        let failure: Binding<String?>
        var server: LocalStaticServer?

        init(ready: Binding<Bool>, failure: Binding<String?>) {
            self.ready = ready
            self.failure = failure
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 页内状态打到构建日志：iOS 上这层出问题看不见控制台，只能靠这行
            webView.evaluateJavaScript("""
            (function(){try{return JSON.stringify({inline:!!window.__WF_INLINE,
              wfk:!!window.WFK, ready:!!(window.WFK&&window.WFK.W),
              body:document.body?document.body.innerHTML.length:-1})}catch(e){return 'err:'+e.message}})()
            """) { value, error in
                print("[calc] page state: \(value ?? error?.localizedDescription ?? "nil")")
            }
            // 页面文档加载完还要等内核 boot（iframe 里 448KB 站点脚本 + 内联数据）
            waitForKernel(webView, tries: 40)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(with: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(with: error)
        }

        private func fail(with error: Error) {
            DispatchQueue.main.async {
                self.failure.wrappedValue = "页面加载失败：\(error.localizedDescription)"
                self.ready.wrappedValue = true
            }
        }

        private func waitForKernel(_ webView: WKWebView, tries: Int) {
            guard tries > 0 else {
                diagnose(webView, then: "计算内核没有起来")
                return
            }
            webView.evaluateJavaScript("!!(window.WFK && window.WFK.W)") { value, _ in
                if (value as? Bool) == true {
                    // CI 拍结果区用：simctl 不能滚动，靠启动参数把页面滚到底
                    if CommandLine.arguments.contains("-calcScroll") {
                        webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight)")
                    }
                    DispatchQueue.main.async { self.ready.wrappedValue = true }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self.waitForKernel(webView, tries: tries - 1)
                    }
                }
            }
        }

        /// 失败时把页内状态摊开显示——模拟器里没有控制台可看。
        /// `__wfStep` 是页面自己写的启动进度，比猜有用：它停在哪一步，
        /// 就知道是内核没起、还是武器数据没回来、还是卡在恢复存档。
        func diagnose(_ webView: WKWebView, then message: String?) {
            webView.evaluateJavaScript("""
            (function(){
              var o = {url: location.href, ready: document.readyState,
                       step: window.__wfStep || '', jsErr: window.__jsErr || '',
                       wfErr: window.__wfErr || '', inline: !!window.__WF_INLINE,
                       wfk: !!window.WFK, frame: !!document.getElementById('wf-kernel')};
              o.pending = performance.getEntriesByType('resource')
                .filter(function(r){ return !r.responseEnd })
                .map(function(r){ return r.name.split('/').pop() });
              return JSON.stringify(o);
            })()
            """) { value, error in
                let detail = (value as? String) ?? (error?.localizedDescription ?? "no detail")
                print("[calc] diagnose: \(detail)")
                DispatchQueue.main.async {
                    self.failure.wrappedValue = (message ?? "") + "\n" + detail
                    self.ready.wrappedValue = true
                }
            }
        }
    }
}

// MARK: - 本地静态服务

/// 只做一件事：把 `GET /path` 映射成 App 包里的文件，回一个 Connection: close
/// 的响应。没有 keep-alive、没有 Range，WKWebView 取静态资源不需要这些。
///
/// 整个 App 共用一个实例：端口固定 → origin 固定 → 页面里的配卡存档才是同一份。
/// 若让每个页面各起一个，第二个会抢不到 41888 而落到 41889，等于换了个站点。
final class LocalStaticServer {
    private static var sharedInstance: LocalStaticServer?

    static func shared(root: URL) -> LocalStaticServer {
        let norm = root.standardizedFileURL
        if let s = sharedInstance, s.root == norm { return s }
        let s = LocalStaticServer(root: norm)
        sharedInstance = s
        return s
    }

    private let root: URL
    private let queue = DispatchQueue(label: "wf.calc.static", attributes: .concurrent)
    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    deinit { stop() }

    /// 固定端口。localStorage 按 origin（scheme + host + port）隔离，端口每次启动
    /// 都换就等于换了个站点——页面里存的配卡会全空。所以先抢这几个端口，
    /// 抢不到（被别的进程占着）才退回系统分配，那种情况下存档读不到，但页面照常能用。
    private static let preferredPorts: [NWEndpoint.Port] =
        ([41888, 41889, 41890] as [UInt16]).compactMap { NWEndpoint.Port(rawValue: $0) }

    func start() -> UInt16 {
        if listener != nil { return port }
        for preferred in LocalStaticServer.preferredPorts {
            if let got = listen(on: preferred) { return got }
        }
        return listen(on: .any) ?? 0
    }

    private func listen(on endpoint: NWEndpoint.Port) -> UInt16? {
        port = 0
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: endpoint)
            let sem = DispatchSemaphore(value: 0)

            l.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.port = l.port?.rawValue ?? 0
                    sem.signal()
                case .failed, .cancelled:
                    sem.signal()
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }

            l.start(queue: queue)
            _ = sem.wait(timeout: .now() + 3)
            // 「绑上了」不等于「能收请求」：这里自己取一次首页，取不到就换下一个端口。
            // 抢端口失败、旧进程还挂着这类情况都会走到这儿。
            if port > 0, probe(port: port) {
                listener = l
                return port
            }
            l.cancel()
            port = 0
            return nil
        } catch {
            return nil
        }
    }

    private func probe(port: UInt16) -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/index.html") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, (data?.count ?? 0) > 0 {
                ok = true
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 3.5)
        return ok
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self = self, let data = data,
                  let head = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }
            let firstLine = head.components(separatedBy: "\r\n").first ?? ""
            let fields = firstLine.split(separator: " ")
            guard fields.count >= 2 else { conn.cancel(); return }

            let isHead = fields[0] == "HEAD"
            var rawPath = String(fields[1])
            if let cut = rawPath.firstIndex(of: "?") { rawPath = String(rawPath[..<cut]) }
            var rel = rawPath
            if rel.hasPrefix("/") { rel.removeFirst() }
            if rel.isEmpty { rel = "index.html" }
            rel = rel.removingPercentEncoding ?? rel

            let file = self.root.appendingPathComponent(rel).standardizedFileURL
            guard file.path.hasPrefix(self.root.path),
                  let body = try? Data(contentsOf: file) else {
                self.respond(conn, status: "404 Not Found", type: "text/plain; charset=utf-8",
                             body: Data("not found".utf8), head: isHead)
                return
            }
            self.respond(conn, status: "200 OK", type: LocalStaticServer.mimeType(rel),
                         body: body, head: isHead)
        }
    }

    private func respond(_ conn: NWConnection, status: String, type: String, body: Data, head: Bool) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(type)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "Connection: close\r\n\r\n"
        var out = Data(header.utf8)
        if !head { out.append(body) }
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    static func mimeType(_ path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "webp": return "image/webp"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "woff2": return "font/woff2"
        case "ico": return "image/x-icon"
        default: return "application/octet-stream"
        }
    }
}
