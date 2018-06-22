import XCTest
import FlatBuffers
@testable import swift_test_suite

final class swift_test_suiteTests: XCTestCase {

    func testGain() {

        let builder = Builder()

        // Create buffer with a Gain table in it
        Gain.startGain(builder: builder)
        Gain.addValue(builder, 7)
        let buffer = Gain.endGain(builder)

        Gain.finishGainBuffer(builder: builder, offset: buffer)

        // Get table back out of buffer and check its properities are what we expect
        let data = builder.getFlatBufferData()

        let gain = Gain(data: data , tablePosition: buffer)

        XCTAssertEqual(gain.value, 7)
    }

    static var allTests = [
        ("testGain", testGain),
    ]
}
