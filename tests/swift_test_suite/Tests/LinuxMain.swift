import XCTest

import swift_test_suiteTests

var tests = [XCTestCaseEntry]()
tests += swift_test_suiteTests.allTests()
XCTMain(tests)