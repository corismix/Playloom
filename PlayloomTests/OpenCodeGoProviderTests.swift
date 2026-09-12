import XCTest
@testable import Playloom
final class OpenCodeGoProviderTests:XCTestCase {
 func testExtractsJSON(){XCTAssertEqual(OpenCodeGoProvider.extractJSONObject("```json\n{\"title\":\"A\"}\n```"),"{\"title\":\"A\"}")}
 func testConversationIDCanBeStable(){let provider=OpenCodeGoProvider(keyStore:TestKeyStore(),conversationID:"project-conversation-1");XCTAssertNotNil(provider)}
 func testSanitizedErrorIsBoundedAndRedactsBearerMarker(){let data=Data(("{\"error\":\"Bearer secret\"}"+String(repeating:"x",count:2000)).utf8);let message=OpenCodeGoProvider.sanitizedError(data);XCTAssertFalse(message.contains("Bearer secret"));XCTAssertLessThanOrEqual(message.count,1010)}
}

private struct TestKeyStore:APIKeyStoring{func read()throws->String?{"x"};func save(_ key:String)throws{};func delete()throws{}}
