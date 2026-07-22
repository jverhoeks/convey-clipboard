import Foundation
import WebKit

@MainActor
public final class WebRuntime: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var isReady = false

    public override init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
        guard let url = Bundle.module.url(
            forResource: "runtime",
            withExtension: "html",
            subdirectory: "web"
        ) else {
            fatalError("runtime.html missing from ConveyCore bundle")
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    public func whenReady() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { continuation in
            self.readyContinuation = continuation
        }
    }

    public func call(_ body: String, arguments: [String: Any]) async throws -> Any? {
        try await whenReady()
        return try await webView.callAsyncJavaScript(
            body,
            arguments: arguments,
            in: nil,
            contentWorld: .page
        )
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        readyContinuation?.resume()
        readyContinuation = nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
    }
}
