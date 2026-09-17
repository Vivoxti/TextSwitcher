import XCTest
@testable import TextSwitcherCore

final class TriggerTests: XCTestCase {
    func testStandaloneShiftAndBothSides() {
        for side: UInt16 in [56, 60] {
            var detector = ShiftTapDetector()
            XCTAssertFalse(detector.flagsChanged(keyCode: side, shift: true, otherModifiers: false, time: 0))
            XCTAssertTrue(detector.flagsChanged(keyCode: side, shift: false, otherModifiers: false, time: 0.1))
            XCTAssertFalse(detector.flagsChanged(keyCode: side, shift: false, otherModifiers: false, time: 0.2))
        }
    }
    func testTypingAndMouseSelectionDoNotTrigger() {
        var detector = ShiftTapDetector()
        _ = detector.flagsChanged(keyCode: 56, shift: true, otherModifiers: false, time: 0)
        detector.cancel()
        XCTAssertFalse(detector.flagsChanged(keyCode: 56, shift: false, otherModifiers: false, time: 0.2))
        _ = detector.flagsChanged(keyCode: 56, shift: true, otherModifiers: false, time: 1)
        XCTAssertFalse(detector.flagsChanged(keyCode: 56, shift: false, otherModifiers: false, time: 2))
    }
    func testOtherModifiersAndTwoShiftsDoNotTrigger() {
        var detector = ShiftTapDetector()
        _ = detector.flagsChanged(keyCode: 56, shift: true, otherModifiers: false, time: 0)
        _ = detector.flagsChanged(keyCode: 59, shift: true, otherModifiers: true, time: 0.1)
        XCTAssertFalse(detector.flagsChanged(keyCode: 56, shift: false, otherModifiers: false, time: 0.2))
        _ = detector.flagsChanged(keyCode: 56, shift: true, otherModifiers: false, time: 1)
        _ = detector.flagsChanged(keyCode: 60, shift: true, otherModifiers: false, time: 1.1)
        XCTAssertFalse(detector.flagsChanged(keyCode: 60, shift: false, otherModifiers: false, time: 1.2))
    }
    func testSublimeLineCopyIsNotMistakenForSelection() {
        XCTAssertEqual(SublimeCopyKind(metadata: Data([3,0,0,0,1,0,0,0,0])), .currentLine)
        XCTAssertEqual(SublimeCopyKind(metadata: Data([3,0,0,0,0,0,0,0,0])), .selection)
        XCTAssertEqual(SublimeCopyKind(metadata: nil), .unsupported)
        XCTAssertEqual(SublimeCopyKind(metadata: Data([4,0,0,0,1,0,0,0,0])), .unsupported)
    }
}
