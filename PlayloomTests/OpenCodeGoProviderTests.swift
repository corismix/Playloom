import XCTest
@testable import Playloom
final class OpenCodeGoProviderTests: XCTestCase {
 func testExtractsFencedJSON() throws { XCTAssertEqual(try OpenCodeGoProvider.extractJSONObject("preface\n```json\n{\"title\":\"A\"}\n```\nafter"),"{\"title\":\"A\"}") }
 func testExtractorStopsAtBalancedObjectAndIgnoresBraceInString() throws { XCTAssertEqual(try OpenCodeGoProvider.extractJSONObject("analysis {\"x\":\"}\",\"nested\":{\"y\":1}} suffix"),"{\"x\":\"}\",\"nested\":{\"y\":1}}") }
 func testResponseShapeIsBounded() { let shape=OpenCodeGoProvider.responseShape(String(repeating:"a",count:1000)); XCTAssertLessThan(shape.count,240); XCTAssertTrue(shape.contains("chars=1000")) }
 func testConversationIDCanBeStable(){let provider=OpenCodeGoProvider(keyStore:TestKeyStore(),conversationID:"project-conversation-1");XCTAssertNotNil(provider)}
 func testSanitizedErrorIsBoundedAndRedactsBearerMarker(){let data=Data(("{\"error\":\"Bearer secret\"}"+String(repeating:"x",count:2000)).utf8);let message=OpenCodeGoProvider.sanitizedError(data);XCTAssertFalse(message.contains("Bearer secret"));XCTAssertLessThanOrEqual(message.count,1010)}
 func testDefaultOutputAdapterPreservesLegacyProviderAndHasNoTransfers() async throws {
     let provider = LegacyProvider()
     let output = try await provider.generateProjectOutput(request: GenerationRequest(operation: .generate, projectID: ProjectID(), runID: RunID(), baseRevisionID: BaseRevisionID(), prompt: "game"))
     XCTAssertEqual(output.project.title, "Legacy")
     XCTAssertTrue(output.backgroundTransfers.isEmpty)
     try await provider.acknowledge(output)
 }
}
private struct LegacyProvider: ModelProvider {
    let displayName = "Legacy"
    func generateProject(prompt: String) async throws -> GameProject { project }
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject { project }
    private var project: GameProject { GameProject(title: "Legacy", files: ["index.html": "", "game.js": "", "style.css": ""]) }
}
private struct TestKeyStore:APIKeyStoring{func read()throws->String?{"x"};func save(_ key:String)throws{};func delete()throws{}}

final class OpenCodeGoReasoningTests: XCTestCase {
    override func tearDown() {
        RequestCaptureURLProtocol.reset()
        super.tearDown()
    }

    func testGenerationUsesMaxReasoning() async throws {
        RequestCaptureURLProtocol.responses = [Self.validResponse(title: "Generated")]
        let provider = makeProvider()
        _ = try await provider.generateProject(prompt: "game")
        XCTAssertEqual(RequestCaptureURLProtocol.efforts, ["max"])
    }

    func testEditUsesHighReasoning() async throws {
        RequestCaptureURLProtocol.responses = [Self.validResponse(title: "Edited")]
        let provider = makeProvider()
        _ = try await provider.editProject(Self.project(title: "Original"), instruction: "faster")
        XCTAssertEqual(RequestCaptureURLProtocol.efforts, ["high"])
    }

    func testMalformedJSONRepairUsesLowAfterRequestedEffort() async throws {
        RequestCaptureURLProtocol.responses = [Self.response(content: "not json"), Self.validResponse(title: "Repaired")]
        let provider = makeProvider()
        _ = try await provider.generateProject(prompt: "game")
        XCTAssertEqual(RequestCaptureURLProtocol.efforts, ["max", "low"])
    }

    func testExtractionIsLocalAndMakesNoRequest() throws {
        XCTAssertEqual(try OpenCodeGoProvider.extractJSONObject("before {\"ok\":true} after"), "{\"ok\":true}")
        XCTAssertTrue(RequestCaptureURLProtocol.efforts.isEmpty)
    }

    private func makeProvider() -> OpenCodeGoProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCaptureURLProtocol.self]
        return OpenCodeGoProvider(keyStore: TestKeyStore(), session: URLSession(configuration: configuration))
    }

    private static func project(title: String) -> GameProject {
        GameProject(title: title, files: ["index.html": "<script src=\"vendor/phaser.min.js\"></script>", "game.js": "", "style.css": ""])
    }

    private static func validResponse(title: String) -> Data {
        let project = project(title: title)
        let projectData = try! JSONEncoder().encode(project)
        return response(content: String(data: projectData, encoding: .utf8)!)
    }

    private static func response(content: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
    }
}

private final class RequestCaptureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [Data] = []
    nonisolated(unsafe) static var efforts: [String] = []
    private static let lock = NSLock()

    static func reset() {
        lock.withLock { responses = []; efforts = [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body: Data
        if let httpBody = request.httpBody { body = httpBody }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                collected.append(buffer, count: count)
            }
            body = collected
        } else { body = Data() }
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let responseData = Self.lock.withLock { () -> Data in
            Self.efforts.append(object?["reasoning_effort"] as? String ?? "missing")
            XCTAssertEqual((object?["thinking"] as? [String: String])?["type"], "enabled")
            return Self.responses.removeFirst()
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
