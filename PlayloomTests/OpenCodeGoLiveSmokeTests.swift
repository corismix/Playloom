import XCTest
@testable import Playloom

@MainActor final class OpenCodeGoLiveSmokeTests:XCTestCase {
 func testOneRealGenerationPassesFullValidationLoop() async throws {
  guard let key=ProcessInfo.processInfo.environment["PLAYLOOM_OPENCODE_GO_KEY"],!key.isEmpty else { throw XCTSkip("No live key") }
  let provider=OpenCodeGoProvider(keyStore:EphemeralKeyStore(key:key),model:"deepseek-v4.1-flash")
  let project=try await provider.generateProject(prompt:"Make a polished one-screen game where a teal ship dodges falling amber meteors. Touch moves the ship. Show score and a clear game-over and restart state.")
  let directory=try ProjectWorkspace().stage(project);let session=GameRuntimeSession(projectDirectory:directory);_=session.makeWebView()
  let report=await UniversalRuntimeChecker().run(session:session)
  XCTAssertTrue(report.isPassing,"title=\(project.title); files=\(project.files.keys.sorted()); failures=\(report.failures); passed=\(report.passed); console=\(report.console)")
 }
}
private struct EphemeralKeyStore:APIKeyStoring{let key:String;func read()throws->String?{key};func save(_ key:String)throws{};func delete()throws{}}
