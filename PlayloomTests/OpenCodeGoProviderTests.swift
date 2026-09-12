import XCTest
@testable import Playloom
final class OpenCodeGoProviderTests:XCTestCase{func testExtractsJSON(){XCTAssertEqual(OpenCodeGoProvider.extractJSONObject("```json\n{\"title\":\"A\"}\n```"),"{\"title\":\"A\"}")}}
