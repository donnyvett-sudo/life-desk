import SwiftUI
import WebKit

/// Serves the bundled Mini App (Resources/miniapp) under lifedesk://app/ so it has a stable origin for CORS.
final class MiniAppScheme: NSObject, WKURLSchemeHandler {
    private let root: URL
    init(root: URL) { self.root = root }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        var rel = url.path
        if rel.isEmpty || rel == "/" { rel = "/index.html" }
        // Symlinks are resolved on both sides: nothing leaves the bundled folder.
        let file = root.appendingPathComponent(rel).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.standardizedFileURL.resolvingSymlinksInPath().path + "/"),
              let data = try? Data(contentsOf: file) else {
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            task.didReceive(r); task.didFinish(); return
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
        // The page may only talk to itself; the API goes through the native bridge (see LifeBridge).
        let csp = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
            + "font-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; form-action 'none'; base-uri 'self'"
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)",
                                               "Content-Security-Policy": csp, "X-Content-Type-Options": "nosniff"])!
        task.didReceive(r); task.didReceive(data); task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// The web view holds the bot token, so it may only ever show the bundled Mini App: everything else goes to the browser.
final class NavGuard: NSObject, WKNavigationDelegate, WKUIDelegate {
    var onFail: (Bool) -> Void = { _ in }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFail(false); Task { @MainActor in LifeWeb.shared.applyAccent() } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFail(true) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFail(true) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { onFail(true) }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.scheme == "lifedesk", url.host == "app" { return decisionHandler(.allow) }
        // Only a click opens the browser: a page script must not be able to send the user anywhere.
        if url.scheme == "https", action.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.scheme == "https", action.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
        return nil
    }
}

/// The page's way to the bot API. It sends {method, path, body}; Swift checks it, adds the token, calls the fixed host
/// and answers {status, json}. The token never enters the page.
final class LifeBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let maxResponse = 4_000_000

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "lifedesk" else {
            return replyHandler(nil, "refused")
        }
        guard let req = BridgeRequest.parse(message.body) else { return replyHandler(nil, "bad request") }
        Task {
            do {
                let (status, data) = try await BotAPI.raw(req.method, req.path, body: req.body)
                guard data.count <= Self.maxResponse else { return replyHandler(nil, "response too large") }
                let json = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull()
                replyHandler(["status": status, "json": json], nil)
            } catch BotAPI.Err.noToken {
                replyHandler(nil, "no token")
            } catch {
                replyHandler(nil, "network")
            }
        }
    }
}

/// One shared web view for all five Life pages: switching a page sends a tab event instead of reloading.
@MainActor
final class LifeWeb: ObservableObject {
    static let shared = LifeWeb()
    private(set) var view: WKWebView?
    @Published var failed = false
    private var current = "today"
    private let guardian = NavGuard()
    private let bridge = LifeBridge()

    func make() -> WKWebView {
        if let view { return view }
        let cfg = WKWebViewConfiguration()
        let dir = Bundle.main.resourceURL!.appendingPathComponent("miniapp")
        cfg.setURLSchemeHandler(MiniAppScheme(root: dir), forURLScheme: "lifedesk")
        // No token in the page: it only learns that it runs inside Life Desk and gets the native API bridge.
        cfg.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "lifedesk")
        cfg.userContentController.addUserScript(WKUserScript(
            source: "window.__LIFE_DESK__ = true; try { localStorage.setItem('tab', 'today'); localStorage.setItem('lang', 'en') } catch (e) {}",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let v = WKWebView(frame: .zero, configuration: cfg)
        guardian.onFail = { [weak self] f in Task { @MainActor in self?.failed = f } }
        v.navigationDelegate = guardian
        v.uiDelegate = guardian
        v.setValue(false, forKey: "drawsBackground")
        v.load(URLRequest(url: URL(string: "lifedesk://app/index.html")!))
        view = v
        return v
    }

    func reload() { failed = false; view?.load(URLRequest(url: URL(string: "lifedesk://app/index.html")!)) }

    /// Pushes the chosen accent into the page as CSS variables (the page has no hook of its own; a late <style> wins).
    func applyAccent() {
        let t = AccentTheme.current
        func hex(_ v: UInt32) -> String { String(format: "#%06x", v) }
        func rgba(_ v: UInt32, _ a: Double) -> String { "rgba(\((v >> 16) & 255), \((v >> 8) & 255), \(v & 255), \(a))" }
        let css = ":root{--accent:\(hex(t.accent.light));--accent-soft:\(rgba(t.accent.light, 0.14));--on-accent:\(hex(t.onAccent.light))}"
            + ":root[data-theme=\"dark\"]{--accent:\(hex(t.accent.dark));--accent-soft:\(rgba(t.accent.dark, 0.16));--on-accent:\(hex(t.onAccent.dark))}"
        let js = "(function(){var s=document.getElementById('ld-accent');if(!s){s=document.createElement('style');s.id='ld-accent';document.head.appendChild(s)}"
            + "s.textContent='\(css)';if(window.__setAccent)window.__setAccent('\(hex(t.accent.light))','\(hex(t.accent.dark))')})()"
        view?.evaluateJavaScript(js)
    }

    func show(tab: String) {
        guard tab != current else { return }
        current = tab
        view?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('lifedesk:tab', { detail: '\(tab)' }))")
    }
}

/// The page plus a native plaque when it could not load or its process died.
struct LifeWebView: View {
    let tab: String
    @ObservedObject private var web = LifeWeb.shared

    var body: some View {
        ZStack {
            LifeWebPage(tab: tab)
            if web.failed {
                VStack(spacing: 10) {
                    Text("This page could not load").font(.headline)
                    Text("The bundled page failed to start. Try again; if it keeps failing, rebuild the app.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Retry") { web.reload() }.keyboardShortcut(.defaultAction)
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
            }
        }
    }
}

struct LifeWebPage: NSViewRepresentable {
    let tab: String

    func makeNSView(context: Context) -> WKWebView { LifeWeb.shared.make() }
    func updateNSView(_ nsView: WKWebView, context: Context) { LifeWeb.shared.show(tab: tab) }
}
