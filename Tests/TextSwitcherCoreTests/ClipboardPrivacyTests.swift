import AppKit
import XCTest
@testable import TextSwitcherCore

final class ClipboardPrivacyTests: XCTestCase {
    func testTemporaryWriteKeepsTextAndReplacesPreviousDataWithPrivacyMarkers() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("previous clipboard", forType: .string)
        pasteboard.setData(Data([1, 2, 3]), forType: .png)
        XCTAssertTrue(ClipboardPrivacy.writeTemporaryText("Привет Hello", to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "Привет Hello")
        XCTAssertNil(pasteboard.data(forType: .png))
        for marker in ClipboardPrivacy.markers { XCTAssertNotNil(pasteboard.data(forType: marker)) }
    }

    func testMarkingSavedItemPreservesOriginalRepresentationsAndExistingMarkers() {
        let item = NSPasteboardItem()
        item.setString("saved text", forType: .string)
        item.setData(Data([4, 5, 6]), forType: .png)
        item.setData(Data([7]), forType: ClipboardPrivacy.markers[0])
        ClipboardPrivacy.markTemporary(item)
        XCTAssertEqual(item.string(forType: .string), "saved text")
        XCTAssertEqual(item.data(forType: .png), Data([4, 5, 6]))
        XCTAssertEqual(item.data(forType: ClipboardPrivacy.markers[0]), Data([7]))
        for marker in ClipboardPrivacy.markers { XCTAssertNotNil(item.data(forType: marker)) }
    }
}
