import XCTest
@testable import Playloom

@MainActor
final class RuntimeIntegrationTests: XCTestCase {
    func testBundledGamePassesUniversalRuntimeChecksEndToEnd() async {
        let session = GameRuntimeSession()
        let webView = session.makeWebView()
        XCTAssertNotNil(webView.navigationDelegate)

        let report = await UniversalRuntimeChecker().run(session: session)

        XCTAssertTrue(report.isPassing, report.failures.joined(separator: ", "))
        XCTAssertEqual(Set(report.passed), Set([
            "loads",
            "no JavaScript crash",
            "canvas not blank",
            "heartbeat alive",
            "input works",
            "restart works"
        ]))
        XCTAssertTrue(session.blockedNavigations.isEmpty)
        XCTAssertEqual(session.contentProcessTerminations, 0)
    }

    func testNavigationPolicyRejectsExternalURL() {
        let session = GameRuntimeSession()
        _ = session.makeWebView()
        guard let url = URL(string: "https://example.com") else { return XCTFail("URL") }

        XCTAssertFalse(session.isAllowedNavigation(url))
    }
}

extension RuntimeIntegrationTests {
    func testPixelSamplerFallsBackToRenderedCanvasWhenGeneratedProbeThrows() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let html = """
        <!doctype html><html><body><canvas width="320" height="240"></canvas><script>
        const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');
        ctx.fillStyle='#101522';ctx.fillRect(0,0,320,240);ctx.fillStyle='#50e3c2';ctx.fillRect(30,30,100,100);
        window.playloomPixelSampleText=()=>{throw new Error('bad generated probe')};
        window.webkit.messageHandlers.playloom.postMessage({type:'ready'});
        </script></body></html>
        """
        try html.write(to: directory.appending(path: "index.html"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = GameRuntimeSession(projectDirectory: directory)
        _ = session.makeWebView()
        XCTAssertTrue(await session.waitFor({ $0 == .ready }, timeout: .seconds(5)))
        let sample = try await session.samplePixels()
        XCTAssertTrue(sample.isNonBlank)
        XCTAssertEqual(sample.width, 320)
        XCTAssertEqual(sample.height, 240)
    }
}
