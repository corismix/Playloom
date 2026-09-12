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

    func testExternalNavigationIsBlocked() async {
        let session = GameRuntimeSession()
        let webView = session.makeWebView()
        guard let url = URL(string: "https://example.com") else { return XCTFail("URL") }

        webView.load(URLRequest(url: url))
        let blocked = await session.waitUntilNavigationBlocked(timeout: .seconds(2))

        XCTAssertTrue(blocked)
        XCTAssertEqual(session.blockedNavigations.last, url)
    }
}
