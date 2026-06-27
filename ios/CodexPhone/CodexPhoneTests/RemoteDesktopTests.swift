import Foundation
import XCTest
@testable import CodexPhone

final class RemoteDesktopTests: XCTestCase {
    func testCanonicalRemoteInputEventDecodes() throws {
        let fixture = #"{"sessionId":"s1","sequence":4,"kind":"pointer","x":0.25,"y":0.75,"button":0,"keyCode":null,"text":null,"deltaX":null,"deltaY":null}"#.data(using: .utf8)!

        let event = try JSONDecoder().decode(RemoteInputEvent.self, from: fixture)

        XCTAssertEqual(event.sessionId, "s1")
        XCTAssertEqual(event.sequence, 4)
        XCTAssertEqual(event.kind, .pointer)
        XCTAssertEqual(event.x, 0.25)
        XCTAssertEqual(event.y, 0.75)
        XCTAssertEqual(event.button, 0)
        XCTAssertNil(event.keyCode)
        XCTAssertNil(event.text)
        XCTAssertNil(event.deltaX)
        XCTAssertNil(event.deltaY)
    }
}
