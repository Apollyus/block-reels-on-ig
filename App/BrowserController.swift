import SwiftUI
import WebKit
import MyGramCore

/// Vlastní jediný WKWebView, vkládá do něj filtry a rozhoduje o navigaci přes URLPolicy.
@MainActor
final class BrowserController: NSObject, ObservableObject {
    static let shared = BrowserController()

    @Published var warning: String?

    let webView: WKWebView

    private let filterConfig: FilterConfig
    private let enabledOptional: Set<String>
    private var policy: URLPolicy
    private var started = false
    private var pendingURL: URL?
    private let refreshControl = UIRefreshControl()
    private let home = URL(string: "https://www.instagram.com/")!

    override init() {
        UserDefaults.standard.register(defaults: ["hideCounts": false])

        let config: FilterConfig
        let scriptBody: String
        do {
            config = try FilterResources.loadConfig()
            scriptBody = try FilterResources.scriptSource()
        } catch {
            fatalError("Chybí filters.json / filters.js v balíčku MyGramCore: \(error)")
        }
        filterConfig = config
        policy = URLPolicy(config: config)
        enabledOptional = UserDefaults.standard.bool(forKey: "hideCounts") ? ["counts"] : []

        let wk = WKWebViewConfiguration()
        wk.websiteDataStore = .default()               // trvalé cookies = přihlášení přežije restart
        wk.allowsInlineMediaPlayback = true
        wk.mediaTypesRequiringUserActionForPlayback = .all

        let ucc = wk.userContentController
        // Vrstva 2: CSS před prvním vykreslením.
        let css = FilterBuilder.css(config, enabledOptional: enabledOptional)
        ucc.addUserScript(WKUserScript(
            source: FilterBuilder.cssInjectionScript(css),
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Vrstva 3: MutationObserver + hook na History API (čeká si DOM sám).
        ucc.addUserScript(WKUserScript(
            source: FilterBuilder.userScript(config, enabledOptional: enabledOptional, scriptBody: scriptBody),
            injectionTime: .atDocumentStart, forMainFrameOnly: true))

        webView = WKWebView(frame: .zero, configuration: wk)
        super.init()

        ucc.add(self, name: "route")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = Self.safariUserAgent()
        webView.isOpaque = false
        #if DEBUG
        webView.isInspectable = true
        #endif

        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
    }

    // MARK: Start a vstupy

    func startIfNeeded() {
        guard !started else { return }
        started = true
        Task {
            await installContentRules()   // Vrstva 1 musí být přidaná před prvním načtením.
            webView.load(URLRequest(url: pendingURL ?? home))
            pendingURL = nil
        }
    }

    func openInbox() {
        open(URL(string: "https://www.instagram.com" + filterConfig.inboxPath)!)
    }

    func handle(url: URL) {
        if let target = DeepLink.resolve(url, config: filterConfig) { open(target) }
    }

    private func open(_ url: URL) {
        if started { webView.load(URLRequest(url: url)) } else { pendingURL = url }
    }

    private func installContentRules() async {
        guard let json = FilterBuilder.contentRuleListJSON(filterConfig, enabledOptional: enabledOptional) else { return }
        do {
            let list = try await WKContentRuleListStore.default()
                .compileContentRuleList(forIdentifier: "mygram", encodedContentRuleList: json)
            if let list { webView.configuration.userContentController.add(list) }
        } catch {
            // CSS a JS vrstva fungují i bez ní.
            NSLog("MyGram: WKContentRuleList se nepodařilo zkompilovat: \(error)")
        }
    }

    @objc private func refresh() {
        webView.reload()
    }

    /// Safari-like UA, ať Instagram nenabízí "Otevřít v aplikaci".
    private static func safariUserAgent() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(v.majorVersion)_\(v.minorVersion) like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(v.majorVersion).\(v.minorVersion) "
            + "Mobile/15E148 Safari/604.1"
    }

    private func runHealthCheck() async {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard webView.url?.path == "/" else { return }
        let result = try? await webView.evaluateJavaScript(
            "JSON.stringify(window.__mygramHealth ? window.__mygramHealth() : null)")
        guard let json = result as? String else { return }
        let problems = FilterHealth.problems(fromJSON: json)
        warning = problems.isEmpty
            ? nil
            : "Filtry možná nefungují (\(problems.joined(separator: ", "))). Instagram mohl změnit web – uprav filters.json."
    }
}

// MARK: - Navigace

extension BrowserController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              navigationAction.targetFrame?.isMainFrame ?? true
        else { return decisionHandler(.allow) }   // iframy neřešíme

        let decision = policy.decide(
            from: webView.url, to: url, userInitiated: navigationAction.navigationType == .linkActivated)
        switch decision {
        case .allow:
            decisionHandler(.allow)
        case .redirectHome:
            decisionHandler(.cancel)
            webView.load(URLRequest(url: home))
        case .openInSafari:
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        case .blockAndGoBack:
            decisionHandler(.cancel)   // k přechodu ještě nedošlo, zůstaneme na místě
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
        Task { await runHealthCheck() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
    }
}

// MARK: - SPA trasy z filters.js

extension BrowserController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "route",
              let body = message.body as? [String: Any],
              let toString = body["to"] as? String, let to = URL(string: toString)
        else { return }
        let from = (body["from"] as? String).flatMap(URL.init(string:))
        let userInitiated = body["userInitiated"] as? Bool ?? false

        switch policy.decide(from: from, to: to, userInitiated: userInitiated) {
        case .allow:
            break
        case .redirectHome:
            webView.evaluateJavaScript("location.replace('/')")
        case .blockAndGoBack:
            webView.evaluateJavaScript("history.back()")
        case .openInSafari:
            webView.evaluateJavaScript("history.back()")
            UIApplication.shared.open(to)
        }
    }
}

// MARK: - Nová okna, kamera/mikrofon

extension BrowserController: WKUIDelegate {
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // target=_blank: Instagram zůstane v aplikaci, vše ostatní do Safari.
        if let url = navigationAction.request.url {
            if policy.isAllowedHost(url.host) { webView.load(navigationAction.request) }
            else { UIApplication.shared.open(url) }
        }
        return nil
    }

    func webView(
        _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(policy.isAllowedHost(origin.host) ? .prompt : .deny)
    }
}
