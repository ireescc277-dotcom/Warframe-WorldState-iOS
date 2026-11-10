import SwiftUI
import WebKit

/// 伤害计算器。页面本体是 `web/app`，作为 folder reference 打进 App 包，
/// 通过自定义 scheme `wfapp://` 读——用 file:// 加载的话，页面里那些
/// `fetch('site/weapons.json')` 会被 WebKit 当成跨源请求拒掉。
public struct DamageCalcView: View {
    /// nil 表示空计算器：进去自己选武器、自己配卡。
    private let weapon: String?
    private let title: String

    @State private var ready = false

    public init(weapon: String? = nil, title: String = "伤害计算") {
        self.weapon = weapon
        self.title = title
    }

    public var body: some View {
        ZStack {
            WFTheme.bgPrimary.ignoresSafeArea()

            CalcWebView(weapon: weapon, ready: $ready)
                .ignoresSafeArea(edges: .bottom)

            if !ready {
                VStack(spacing: WFUI.s3) {
                    ProgressView()
                        .tint(WFTheme.gold)
                    Text("加载计算内核…")
                        .font(.wfLabel)
                        .foregroundColor(WFTheme.textMuted)
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

    func makeCoordinator() -> Coordinator { Coordinator(ready: $ready) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if let root = WeaponCatalog.bundleRoot {
            config.setURLSchemeHandler(BundleSchemeHandler(root: root), forURLScheme: BundleSchemeHandler.scheme)
        }
        // 站点脚本用 localStorage 存少量界面偏好，给它一个持久化的数据目录
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

        var comps = URLComponents()
        comps.scheme = BundleSchemeHandler.scheme
        comps.host = "local"
        comps.path = "/index.html"
        if let weapon = weapon {
            comps.queryItems = [URLQueryItem(name: "weapon", value: weapon)]
        }
        if let url = comps.url {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let ready: Binding<Bool>

        init(ready: Binding<Bool>) { self.ready = ready }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 页面文档加载完还要等内核 boot（iframe 里 448KB 站点脚本 + 武器数据）
            waitForKernel(webView, tries: 40)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            ready.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            ready.wrappedValue = true
        }

        private func waitForKernel(_ webView: WKWebView, tries: Int) {
            guard tries > 0 else {
                ready.wrappedValue = true
                return
            }
            webView.evaluateJavaScript("!!(window.WFK && window.WFK.W)") { value, _ in
                if (value as? Bool) == true {
                    self.ready.wrappedValue = true
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self.waitForKernel(webView, tries: tries - 1)
                    }
                }
            }
        }
    }
}

// MARK: - 包内资源

/// `wfapp://local/<path>` → App 包里 DamageCalc 目录下的同名文件。
///
/// 同源的自定义 scheme，页面里的相对 fetch 才能成立；顺便给每个响应挂上
/// CORS 头，避免 WebKit 把 iframe 里的数据请求当成跨源。
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "wfapp"

    private let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            finish(task, status: 400, body: Data())
            return
        }

        var rel = url.path
        if rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { rel = "index.html" }
        if let decoded = rel.removingPercentEncoding { rel = decoded }

        let file = root.appendingPathComponent(rel).standardizedFileURL
        // 不允许跳出资源目录
        guard file.path.hasPrefix(root.path) else {
            finish(task, status: 403, body: Data())
            return
        }
        guard let data = try? Data(contentsOf: file) else {
            finish(task, status: 404, body: Data())
            return
        }

        let mime = BundleSchemeHandler.mimeType(rel)
        let header = [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache",
        ]
        // 自定义 scheme 上 HTTPURLResponse 未必总能构造，兜一个普通响应
        let response: URLResponse
        if let http = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                      headerFields: header) {
            response = http
        } else {
            response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count,
                                   textEncodingName: "utf-8")
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func finish(_ task: WKURLSchemeTask, status: Int, body: Data) {
        guard let url = task.request.url else { return }
        if let r = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "text/plain; charset=utf-8",
                                                  "Access-Control-Allow-Origin": "*"]) {
            task.didReceive(r)
        }
        task.didReceive(body)
        task.didFinish()
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
