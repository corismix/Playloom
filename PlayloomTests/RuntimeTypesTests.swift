import XCTest
@testable import Playloom

final class RuntimeTypesTests: XCTestCase {
    func testDecodesKnownBridgeMessages() {
        XCTAssertEqual(RuntimeEvent(message: ["type": "ready"]), .ready)
        XCTAssertEqual(RuntimeEvent(message: ["type": "heartbeat", "frame": 42]), .heartbeat(42))
        XCTAssertEqual(RuntimeEvent(message: ["type": "input"]), .inputReceived)
        XCTAssertEqual(RuntimeEvent(message: ["type": "restarted"]), .restarted)
        XCTAssertEqual(RuntimeEvent(message: ["type": "fatal", "message": "boom"]), .fatal("boom"))
        XCTAssertNil(RuntimeEvent(message: ["type": "credentialPlease"]))
    }

    func testPixelThreshold() {
        XCTAssertFalse(PixelSample(changedRatio: 0.009, width: 10, height: 10).isNonBlank)
        XCTAssertTrue(PixelSample(changedRatio: 0.01, width: 10, height: 10).isNonBlank)
    }
}
