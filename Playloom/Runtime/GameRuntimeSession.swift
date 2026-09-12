import Foundation
import UIKit
import WebKit

@MainActor
final class GameRuntimeSession: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private(set) var events: [RuntimeEvent] = []
    private(set) var blockedNavigations: [URL] = []
    private(set) var contentProcessTerminations = 0
    private(set) var navigationStarted = false
    private(set) var navigationCommitted = false
    private(set) var navigationFinished = false
    private(set) var navigationError: String?
    private var webView: WKWebView?
    private var validationWindow: UIWindow?
    private var attachedForValidation = false
    private var entryURL: URL?

    override init() {
        entryURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "RuntimeFixture")
            ?? Bundle.main.url(forResource: "index", withExtension: "html")
        super.init()
    }

    init(projectDirectory: URL) {
        entryURL = projectDirectory.appending(path: "index.html")
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

        // Phaser sizes itself from the viewport during boot. A zero-sized, unattached
        // validation view can stay throttled on physical devices, so validate at a real viewport.
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        view.navigationDelegate = self
        view.isInspectable = false
        view.scrollView.bounces = false
        webView = view
        loadFixture()
        return view
    }

    func beginValidationPresentation() {
        let view = makeWebView()
        guard view.superview == nil else { return }
        attachedForValidation = true
        view.isUserInteractionEnabled = false
        view.alpha = 0.01
        if let host = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: { $0.isKeyWindow })?.rootViewController?.view {
            host.addSubview(view)
        } else if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let window = UIWindow(windowScene: scene)
            let controller = UIViewController()
            window.rootViewController = controller
            window.frame = scene.screen.bounds
            window.windowLevel = .normal - 1
            window.isHidden = false
            controller.view.addSubview(view)
            validationWindow = window
        }
    }

    func endValidationPresentation() {
        guard attachedForValidation, let webView else { return }
        webView.removeFromSuperview()
        webView.alpha = 1
        webView.isUserInteractionEnabled = true
        validationWindow?.isHidden = true
        validationWindow = nil
        attachedForValidation = false
    }

    func loadFixture() {
        guard let webView, let entryURL else {
            events.append(.fatal("Bundled runtime fixture is missing"))
            return
        }
        events.removeAll()
        navigationStarted = false; navigationCommitted = false; navigationFinished = false; navigationError = nil
        webView.loadFileURL(entryURL, allowingReadAccessTo: entryURL.deletingLastPathComponent())
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
            webView.evaluateJavaScript(Self.pixelSamplerScript) { value, error in
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

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { navigationStarted = true }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { navigationCommitted = true }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { navigationFinished = true }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationError = error.localizedDescription }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationError = error.localizedDescription }

    var startupDiagnostic: String {
        let bridge = events.contains(.bridgeReady)
        let ready = events.contains(.ready)
        return "stage=webview; navigation(started=\(navigationStarted),committed=\(navigationCommitted),finished=\(navigationFinished)); bridge=\(bridge); gameReady=\(ready); processTerminations=\(contentProcessTerminations); navigationError=\(navigationError ?? "none")"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if isAllowedNavigation(url) { decisionHandler(.allow) }
        else { blockedNavigations.append(url); decisionHandler(.cancel) }
    }

    func isAllowedNavigation(_ url: URL) -> Bool {
        if url.scheme == "about" { return true }
        return url.isFileURL && entryURL.map { url.path.hasPrefix($0.deletingLastPathComponent().path) } == true
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        contentProcessTerminations += 1
        events.append(.fatal("Web content process terminated"))
    }

    // This check belongs to Playloom, not generated code. Accept a valid generated
    // probe for compatibility, then fall back to inspecting the Phaser canvas directly.
    nonisolated private static let pixelSamplerScript = #"""
    (() => {
      try {
        const supplied = window.playloomPixelSampleText?.();
        if (typeof supplied === 'string' && /^([0-9]*\.)?[0-9]+,\d+,\d+$/.test(supplied)) return supplied;
        if (supplied && typeof supplied === 'object') {
          const ratio = Number(supplied.changedRatio), width = Number(supplied.width), height = Number(supplied.height);
          if (Number.isFinite(ratio) && width > 0 && height > 0) return `${ratio},${width},${height}`;
        }
      } catch (_) {}
      const canvas = document.querySelector('canvas');
      if (!canvas || canvas.width < 1 || canvas.height < 1) return '0,0,0';
      const context = canvas.getContext('2d', {willReadFrequently:true});
      if (!context) return `0,${canvas.width},${canvas.height}`;
      const width = Math.min(canvas.width, 96), height = Math.min(canvas.height, 96);
      const pixels = context.getImageData(0, 0, width, height).data;
      const colors = new Map(); let largest = 0;
      for (let i = 0; i < pixels.length; i += 4) {
        const key = `${pixels[i] >> 3},${pixels[i+1] >> 3},${pixels[i+2] >> 3},${pixels[i+3] >> 5}`;
        const count = (colors.get(key) || 0) + 1; colors.set(key, count); largest = Math.max(largest, count);
      }
      return `${1 - largest / (pixels.length / 4)},${canvas.width},${canvas.height}`;
    })()
    """#

    nonisolated private static let errorCaptureScript = #"""
    (() => {
      const send = value => window.webkit.messageHandlers.playloom.postMessage(value);
      send({type:'bridge'});
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
