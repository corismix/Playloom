import XCTest
@testable import Playloom

@MainActor
final class RuntimeIntegrationTests: XCTestCase {
    func testBundledGamePassesUniversalRuntimeChecksEndToEnd() async throws {
        let session = GameRuntimeSession()
        let webView = session.makeWebView()
        XCTAssertNotNil(webView.navigationDelegate)

        let report = try await UniversalRuntimeChecker().run(session: session)

        XCTAssertTrue(report.isPassing, report.failures.joined(separator: ", "))
        XCTAssertEqual(Set(report.passed), Set([
            "WebKit bridge ready",
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
