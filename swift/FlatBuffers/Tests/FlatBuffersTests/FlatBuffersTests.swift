import XCTest
@testable import FlatBuffers

final class FlatBuffersTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(FlatBuffers().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
