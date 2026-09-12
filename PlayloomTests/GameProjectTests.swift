import XCTest
@testable import Playloom

final class GameProjectTests: XCTestCase {
    private let valid = GameProject(title: "Test", files: [
        "index.html": "<script src='vendor/phaser.min.js'></script>", "game.js": "const game = 1", "style.css": "body{}"
    ])

    func testValidProjectPasses() throws { XCTAssertEqual(try valid.validated(), valid) }
    func testTraversalIsRejected() {
        var project = valid; project.files["../escape.js"] = "bad"
        XCTAssertThrowsError(try project.validated()) { XCTAssertEqual($0 as? GameProjectError, .unsafePath) }
    }
    func testMissingPhaserIsRejected() {
        var project = valid; project.files["index.html"] = "<html></html>"
        XCTAssertThrowsError(try project.validated()) { XCTAssertEqual($0 as? GameProjectError, .missingPhaser) }
    }
}
