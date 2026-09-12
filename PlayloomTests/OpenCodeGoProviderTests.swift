import XCTest
@testable import Playloom
final class OpenCodeGoProviderTests: XCTestCase {
 func testExtractsFencedJSON() throws { XCTAssertEqual(try OpenCodeGoProvider.extractJSONObject("preface\n```json\n{\"title\":\"A\"}\n```\nafter"),"{\"title\":\"A\"}") }
 func testExtractorStopsAtBalancedObjectAndIgnoresBraceInString() throws { XCTAssertEqual(try OpenCodeGoProvider.extractJSONObject("analysis {\"x\":\"}\",\"nested\":{\"y\":1}} suffix"),"{\"x\":\"}\",\"nested\":{\"y\":1}}") }
 func testResponseShapeIsBounded() { let shape=OpenCodeGoProvider.responseShape(String(repeating:"a",count:1000)); XCTAssertLessThan(shape.count,240); XCTAssertTrue(shape.contains("chars=1000")) }
 func testConversationIDCanBeStable(){let provider=OpenCodeGoProvider(keyStore:TestKeyStore(),conversationID:"project-conversation-1");XCTAssertNotNil(provider)}
 func testSanitizedErrorIsBoundedAndRedactsBearerMarker(){let data=Data(("{\"error\":\"Bearer secret\"}"+String(repeating:"x",count:2000)).utf8);let message=OpenCodeGoProvider.sanitizedError(data);XCTAssertFalse(message.contains("Bearer secret"));XCTAssertLessThanOrEqual(message.count,1010)}
}
private struct TestKeyStore:APIKeyStoring{func read()throws->String?{"x"};func save(_ key:String)throws{};func delete()throws{}}
