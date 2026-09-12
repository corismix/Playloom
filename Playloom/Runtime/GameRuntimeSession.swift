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
        _ = try? await webView.callAsyncJavaScript("window.playloomProbeInput?.()", arguments: [:], in: nil, contentWorld: .page)
        if await waitFor({ $0 == .inputReceived }, timeout: .milliseconds(350)) { return }
        _ = try await webView.callAsyncJavaScript(Self.touchPointerProbeScript, arguments: [:], in: nil, contentWorld: .page)
    }

    func sampleVisiblePixels() async throws -> PixelSample {
        guard let webView else { throw RuntimeSessionError.notStarted }
        let image = try await webView.takeSnapshot(configuration: nil)
        guard let cgImage = image.cgImage else { throw RuntimeSessionError.badPixelSample }
        let width = min(cgImage.width, 128), height = min(cgImage.height, 128)
        guard width > 0, height > 0 else { throw RuntimeSessionError.badPixelSample }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw RuntimeSessionError.badPixelSample }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var buckets: [UInt32: Int] = [:]; var largest = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let key = UInt32(pixels[index] >> 3) << 15 | UInt32(pixels[index+1] >> 3) << 10 | UInt32(pixels[index+2] >> 3) << 5 | UInt32(pixels[index+3] >> 3)
            let count = (buckets[key] ?? 0) + 1; buckets[key] = count; largest = max(largest, count)
        }
        return PixelSample(changedRatio: 1 - Double(largest) / Double(width * height), width: cgImage.width, height: cgImage.height)
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

    func diagnosticSnapshot() async -> String {
        guard let webView else { return "webView=missing" }
        let hierarchy = "frame=\(webView.frame.debugDescription); superview=\(String(describing: type(of: webView.superview))); window=\(String(describing: type(of: webView.window))); hidden=\(webView.isHidden); alpha=\(webView.alpha)"
        let javascript = #"""
        (() => {
          const canvas = document.querySelector('canvas');
          let generatedPixel = 'missing';
          try { generatedPixel = String(window.playloomPixelSampleText?.()); } catch (error) { generatedPixel = `throws:${error}`; }
          let directPixel = 'unavailable';
          if (canvas) {
            try {
              const context = canvas.getContext('2d', {willReadFrequently:true});
              const width = Math.min(canvas.width, 128), height = Math.min(canvas.height, 128);
              if (context && width && height) {
                const data = context.getImageData(Math.max(0, (canvas.width-width)>>1), Math.max(0, (canvas.height-height)>>1), width, height).data;
                let opaque=0, nonzero=0, min=255, max=0;
                for (let i=0;i<data.length;i+=4) { if(data[i+3]) opaque++; if(data[i]||data[i+1]||data[i+2]) nonzero++; min=Math.min(min,data[i],data[i+1],data[i+2]); max=Math.max(max,data[i],data[i+1],data[i+2]); }
                directPixel=`sample=${width}x${height},opaque=${opaque},nonzero=${nonzero},min=${min},max=${max}`;
              }
            } catch(error) { directPixel=`throws:${error}`; }
          }
          const probe = typeof window.playloomProbeInput === 'function'
            ? String(window.playloomProbeInput).replace(/\s+/g, ' ').slice(0, 700)
            : String(typeof window.playloomProbeInput);
          return JSON.stringify({readyState:document.readyState, url:location.href, canvas:canvas ? {width:canvas.width,height:canvas.height,clientWidth:canvas.clientWidth,clientHeight:canvas.clientHeight,rect:Array.from([canvas.getBoundingClientRect().x,canvas.getBoundingClientRect().y,canvas.getBoundingClientRect().width,canvas.getBoundingClientRect().height])} : null, generatedPixel, directPixel, probeType:typeof window.playloomProbeInput, probeSource:probe, restartType:typeof window.playloomRestart, domListeners:window.__playloomDOMListeners || {}});
        })()
        """#
        let page: String
        do {
            let value = try await webView.evaluateJavaScript(javascript)
            page = String(describing: value)
        } catch { page = "snapshotError=\(error.localizedDescription)" }
        let heartbeatCount = events.reduce(into: 0) { count, event in if case .heartbeat = event { count += 1 } }
        let inputCount = events.filter { $0 == .inputReceived }.count
        let eventSummary = "events=\(events.count),heartbeats=\(heartbeatCount),inputs=\(inputCount),console=\(events.compactMap { if case let .console(level,message) = $0 { return "[\(level)] \(message)" }; return nil }.suffix(5))"
        return "\(startupDiagnostic); \(hierarchy); page=\(page); \(eventSummary)"
    }

    func waitForHeartbeat(after count: Int, timeout: Duration) async -> Bool {
        let clock = ContinuousClock(); let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            let current = events.filter { if case .heartbeat = $0 { return true }; return false }.count
            if current > count { return true }
            try? await clock.sleep(for: .milliseconds(100))
        }
        return false
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

    // iOS hardware does not translate synthetic mouse events into touch input the way
    // Simulator does. Dispatch the Pointer Events sequence WebKit gives Phaser for touch.
    nonisolated private static let touchPointerProbeScript = #"""
    (() => {
      const target = document.querySelector('canvas') || document.querySelector('#game') || document.body;
      const rect = target.getBoundingClientRect();
      const x = rect.left + Math.max(1, rect.width / 2), y = rect.top + Math.max(1, rect.height / 2);
      const common = {pointerId:937, pointerType:'touch', isPrimary:true, clientX:x, clientY:y,
                      screenX:x, screenY:y, bubbles:true, composed:true, cancelable:true};
      target.dispatchEvent(new PointerEvent('pointerdown', {...common, buttons:1, button:0, pressure:0.5}));
      target.dispatchEvent(new PointerEvent('pointermove', {...common, clientX:x+8, buttons:1, button:0, pressure:0.5}));
      target.dispatchEvent(new PointerEvent('pointerup', {...common, clientX:x+8, buttons:0, button:0, pressure:0}));
      target.dispatchEvent(new MouseEvent('click', {clientX:x+8, clientY:y, bubbles:true, composed:true, cancelable:true}));
      return true;
    })()
    """#

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
      const listenerCounts = Object.create(null);
      const originalAdd = EventTarget.prototype.addEventListener;
      EventTarget.prototype.addEventListener = function(type, listener, options) {
        const target = this === window ? 'window' : this === document ? 'document'
          : this instanceof Element ? `${this.tagName.toLowerCase()}${this.id ? '#' + this.id : ''}` : this.constructor?.name || 'target';
        const key = `${target}:${String(type)}`;
        listenerCounts[key] = (listenerCounts[key] || 0) + 1;
        return originalAdd.call(this, type, listener, options);
      };
      Object.defineProperty(window, '__playloomDOMListeners', {value: listenerCounts, configurable: false});
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
