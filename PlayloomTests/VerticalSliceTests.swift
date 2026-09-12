import XCTest
@testable import Playloom

@MainActor
final class VerticalSliceTests: XCTestCase {
    func testPromptThenEditStagesChecksAndReloadsPlayableProject() async throws {
        let initial = try fixtureProject(title: "First game", accent: "#50e3c2")
        let edited = try fixtureProject(title: "Faster game", accent: "#ffcc33")
        let provider = FakeModelProvider(initial: initial, edited: edited)
        let model = GenerationModel(provider: provider)
        model.prompt = "Make a dodge game"

        await model.generate()

        XCTAssertEqual(model.project?.title, "First game")
        XCTAssertNotNil(model.session)
        XCTAssertEqual(model.status, "Playable", model.detail)

        model.edit = "Make it faster and yellow"
        await model.applyEdit()

        XCTAssertEqual(model.project?.title, "Faster game")
        XCTAssertNotNil(model.session)
        XCTAssertEqual(model.status, "Playable", model.detail)
        let requests = await provider.requests
        XCTAssertEqual(requests, ["generate:Make a dodge game", "edit:Make it faster and yellow"])
    }

    private func fixtureProject(title: String, accent: String) throws -> GameProject {
        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html"),
              let scriptURL = Bundle.main.url(forResource: "fixture", withExtension: "js"),
              let styleURL = Bundle.main.url(forResource: "style", withExtension: "css") else {
            throw FixtureError.missing
        }
        var index = try String(contentsOf: indexURL, encoding: .utf8)
        index = index.replacingOccurrences(of: "<script src=\"fixture.js\"></script>", with: "<script src=\"vendor/phaser.min.js\"></script><script src=\"game.js\"></script>")
        let script = try String(contentsOf: scriptURL, encoding: .utf8).replacingOccurrences(of: "#50e3c2", with: accent)
        let style = try String(contentsOf: styleURL, encoding: .utf8)
        return GameProject(title: title, files: ["index.html": index, "game.js": script, "style.css": style])
    }
}

private actor FakeModelProvider: ModelProvider {
    nonisolated let displayName = "Test Provider"
    let initial: GameProject
    let edited: GameProject
    private(set) var requests: [String] = []

    init(initial: GameProject, edited: GameProject) { self.initial = initial; self.edited = edited }
    func generateProject(prompt: String) async throws -> GameProject { requests.append("generate:\(prompt)"); return initial }
    func editProject(_ project: GameProject, instruction: String) async throws -> GameProject { requests.append("edit:\(instruction)"); return edited }
}

private enum FixtureError: Error { case missing }
