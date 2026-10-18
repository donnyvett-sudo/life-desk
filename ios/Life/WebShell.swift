import SwiftUI
import WebKit

/// Serves the bundled web client under lifedesk://app/ (stable origin, strict CSP) — same scheme Life Desk uses.
final class MiniAppScheme: NSObject, WKURLSchemeHandler {
    private let root: URL
    init(root: URL) { self.root = root }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        var rel = url.path
        if rel.isEmpty || rel == "/" { rel = "/index.html" }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let file = root.appendingPathComponent(rel).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(base.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            task.didFinish(); return
        }
        let mime: String
        switch file.pathExtension.lowercased() {
        case "html": mime = "text/html"
        case "js": mime = "text/javascript"
        case "css": mime = "text/css"
        case "svg": mime = "image/svg+xml"
        case "woff2": mime = "font/woff2"
        case "json": mime = "application/json"
        case "png": mime = "image/png"
        default: mime = "application/octet-stream"
        }
        let csp = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
            + "font-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; form-action 'none'; base-uri 'self'"
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)",
                                               "Content-Security-Policy": csp, "X-Content-Type-Options": "nosniff"])!
        task.didReceive(r); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// The page's only way to the API: it sends {method, path, body}; the app validates, adds the token, calls the fixed host.
final class LifeBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let maxResponse = 4_000_000

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "lifedesk" else { return replyHandler(nil, "refused") }
        guard let req = BridgeRequest.parse(message.body) else { return replyHandler(nil, "bad request") }
        Task {
            do {
                let (status, data) = try await LifeAPI.raw(req.method, req.path, body: req.body)
                guard data.count <= Self.maxResponse else { return replyHandler(nil, "response too large") }
                let json = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull()
                replyHandler(["status": status, "json": json], nil)
            } catch LifeAPI.Err.noToken {
                replyHandler(nil, "no token")
            } catch {
                replyHandler(nil, "network")
            }
        }
    }
}

/// Only the bundled page may load; a tapped https link opens in Safari.
final class NavGuard: NSObject, WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.scheme == "lifedesk", url.host == "app" { return decisionHandler(.allow) }
        if url.scheme == "https", action.navigationType == .linkActivated { UIApplication.shared.open(url) }
        decisionHandler(.cancel)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { @MainActor in LifeWebHolder.shared.pageLoaded() } }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
}

/// The web view of the Life tab, so the native selector can switch the page inside it.
@MainActor
final class LifeWebHolder {
    static let shared = LifeWebHolder()
    weak var view: WKWebView?
    private var loaded = false
    private var pending: String?
    /// The Mini App follows the chosen colour theme (it defines window.__setAccent).
    func applyAccent() {
        let t = AccentTheme.current
        func hex(_ v: UInt32) -> String { String(format: "#%06x", v) }
        view?.evaluateJavaScript("window.__setAccent && window.__setAccent('\(hex(t.accent.light))', '\(hex(t.accent.dark))')")
    }
    func pageLoaded() { applyAccent(); loaded = true; if let t = pending { pending = nil; show(tab: t) } }
    /// The Mini App keeps its own language in localStorage; switch it and reload so the page matches the app.
    func setLanguage(_ code: String) {
        view?.evaluateJavaScript("try { localStorage.setItem('lang', '\(code)') } catch (e) {}; location.reload()")
        loaded = false
    }
    func show(tab: String) {
        guard loaded else { pending = tab; return }   // the page is not listening yet: apply it when it has loaded
        view?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('lifedesk:tab', { detail: '\(tab)' }))")
    }
}

struct LifeWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let dir = Bundle.main.resourceURL!.appendingPathComponent("miniapp")
        cfg.setURLSchemeHandler(MiniAppScheme(root: dir), forURLScheme: "lifedesk")
        cfg.userContentController.addScriptMessageHandler(context.coordinator.bridge, contentWorld: .page, name: "lifedesk")
        cfg.userContentController.addUserScript(WKUserScript(
            source: "window.__LIFE_IOS__ = true; try { localStorage.setItem('lang', '\(LanguageSync.effective)') } catch (e) {}", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.navigationDelegate = context.coordinator.guardian
        v.uiDelegate = context.coordinator.guardian
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.contentInsetAdjustmentBehavior = .automatic
        v.load(URLRequest(url: URL(string: "lifedesk://app/index.html")!))
        LifeWebHolder.shared.view = v
        return v
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { let bridge = LifeBridge(); let guardian = NavGuard() }
}
