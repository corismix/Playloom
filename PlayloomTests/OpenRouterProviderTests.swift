import XCTest
@testable import Playloom

final class OpenRouterProviderTests: XCTestCase {
    func testMissingKeyFailsBeforeNetwork() async {
        let provider = OpenRouterProvider(keyStore: EmptyKeyStore())
        do { _ = try await provider.generateProject(prompt: "game"); XCTFail("Expected failure") }
        catch { guard case ProviderError.missingKey = error else { return XCTFail("Wrong error: \(error)") } }
    }
}
private struct EmptyKeyStore: APIKeyStoring { func read() throws -> String? { nil }; func save(_ key: String) throws {}; func delete() throws {} }
