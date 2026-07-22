import Foundation
import WebKit

@MainActor
public final class WebRuntime: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var started = false
    private var isReady = false
    private var loadError: Error?
    private var waiters: [CheckedContinuation<Void, Error>] = []

    public override init() { super.init() }

    private func start() {
        guard !started else { return }
        started = true

        let config = WKWebViewConfiguration()
        // Retain the controller we actually configure; `webView.configuration` returns
        // a copy, so adding the rule list through it later would be a silent no-op.
        let userContentController = config.userContentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        guard let url = Bundle.module.url(forResource: "runtime", withExtension: "html", subdirectory: "web") else {
            finishAll(with: ConversionError.engineFailed("runtime.html missing from bundle"))
            return
        }

        // Block only remote network schemes; MUST allow file: (local scripts) and data: (SVG rasterization).
        let rules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "convey-block-remote",
            encodedContentRuleList: rules
        ) { [weak self] list, _ in
            // completion is on the main queue; hop to the actor to be safe.
            Task { @MainActor in
                guard let self, let webView = self.webView else { return }
                if let list { userContentController.add(list) }
                // If compilation fails, proceed without the rule list rather than hang.
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        }
    }

    public func whenReady() async throws {
        if isReady { return }
        if let loadError { throw loadError }
        start()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            // Re-check after `start()` in case it resolved synchronously (e.g. the
            // runtime.html-missing path) before this continuation is registered.
            if isReady { c.resume(); return }
            if let loadError { c.resume(throwing: loadError); return }
            waiters.append(c)
        }
    }

    public func call(_ body: String, arguments: [String: Any]) async throws -> Any? {
        try await whenReady()
        guard let webView else { throw ConversionError.engineFailed("webview unavailable") }
        return try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page)
    }

    private func finishReady() {
        isReady = true
        let pending = waiters; waiters = []
        pending.forEach { $0.resume() }
    }

    private func finishAll(with error: Error) {
        loadError = error
        let pending = waiters; waiters = []
        pending.forEach { $0.resume(throwing: error) }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishReady() }
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishAll(with: error) }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishAll(with: error) }
}
