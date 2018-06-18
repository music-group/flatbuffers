import XCTest

import FlatBuffersTests

var tests = [XCTestCaseEntry]()
tests += FlatBuffersTests.allTests()
XCTMain(tests)