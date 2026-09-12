import Foundation
import UIKit
import WebKit

@MainActor
final class GameRuntimeSession: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private(set) var events: [RuntimeEvent] = []
    private(set) var blockedNavigations: [URL] = []
    private(set) var contentProcessTerminations = 0
    private var webView: WKWebView?
    private let fixtureURL: URL?

    override init() {
        fixtureURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "RuntimeFixture")
            ?? Bundle.main.url(forResource: "index", withExtension: "html")
        super.init()
    }

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let controller = WKUserContentController()
        controller.add(WeakScriptMessageHandler(delegate: self), name: "playloom")
        controller.addUserScript(WKUserScript(source: Self.errorCaptureScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.isInspectable = false
        view.scrollView.bounces = false
        webView = view
        loadFixture()
        return view
    }

    func loadFixture() {
        guard let webView, let fixtureURL else {
            events.append(.fatal("Bundled runtime fixture is missing"))
            return
        }
        events.removeAll()
        webView.loadFileURL(fixtureURL, allowingReadAccessTo: fixtureURL.deletingLastPathComponent())
    }

    func restart() async throws {
        guard let webView else { throw RuntimeSessionError.notStarted }
        _ = try await webView.callAsyncJavaScript("window.playloomRestart()", arguments: [:], in: nil, contentWorld: .page)
    }

    func probeInput() async throws {
        guard let webView else { throw RuntimeSessionError.notStarted }
        _ = try await webView.callAsyncJavaScript("window.playloomProbeInput()", arguments: [:], in: nil, contentWorld: .page)
    }

    func samplePixels() async throws -> PixelSample {
        guard let webView else { throw RuntimeSessionError.notStarted }
        let text: String = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript("window.playloomPixelSampleText()") { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let text = value as? String { continuation.resume(returning: text) }
                else { continuation.resume(throwing: RuntimeSessionError.badPixelSample) }
            }
        }
        let fields = text.split(separator: ",")
        guard fields.count == 3,
              let ratio = Double(fields[0]),
              let width = Int(fields[1]),
              let height = Int(fields[2]) else { throw RuntimeSessionError.badPixelSample }
        return PixelSample(changedRatio: ratio, width: width, height: height)
    }

    func waitUntilNavigationBlocked(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if !blockedNavigations.isEmpty { return true }
            try? await clock.sleep(for: .milliseconds(25))
        }
        return !blockedNavigations.isEmpty
    }

    func waitFor(_ predicate: @escaping (RuntimeEvent) -> Bool, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if events.contains(where: predicate) { return true }
            try? await clock.sleep(for: .milliseconds(25))
        }
        return events.contains(where: predicate)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "playloom", let event = RuntimeEvent(message: message.body) else { return }
        events.append(event)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if isAllowedNavigation(url) { decisionHandler(.allow) }
        else { blockedNavigations.append(url); decisionHandler(.cancel) }
    }

    func isAllowedNavigation(_ url: URL) -> Bool {
        if url.scheme == "about" { return true }
        return url.isFileURL && fixtureURL.map { url.path.hasPrefix($0.deletingLastPathComponent().path) } == true
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        contentProcessTerminations += 1
        events.append(.fatal("Web content process terminated"))
    }

    nonisolated private static let errorCaptureScript = #"""
    (() => {
      const send = value => window.webkit.messageHandlers.playloom.postMessage(value);
      window.addEventListener('error', event => send({type:'fatal', message:String(event.message || 'JavaScript error')}));
      window.addEventListener('unhandledrejection', event => send({type:'fatal', message:String(event.reason || 'Unhandled rejection')}));
      for (const level of ['error','warn']) {
        const original = console[level];
        console[level] = (...values) => {
          send({type:'console', level, message:values.map(String).join(' ')});
          original.apply(console, values);
        };
      }
    })();
    """#
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

nonisolated enum RuntimeSessionError: Error { case notStarted, badPixelSample }
