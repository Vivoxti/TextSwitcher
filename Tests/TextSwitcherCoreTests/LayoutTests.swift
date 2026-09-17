import XCTest
@testable import TextSwitcherCore

final class LayoutTests: XCTestCase {
    private func layout(_ id: String, _ keys: String) -> KeyboardLayout {
        KeyboardLayout(id: id, title: id, characters: Dictionary(uniqueKeysWithValues: keys.enumerated().map { (KeyPosition(code: UInt16($0.offset)), $0.element) }))
    }
    private var english: KeyboardLayout { layout("english", "`qwertyuiop[]asdfghjkl;'zxcvbnm,.") }
    private var russian: KeyboardLayout { layout("russian", "ёйцукенгшщзхъфывапролджэячсмитьбю") }
    private var converter: LayoutConverter { LayoutConverter(first: english, second: russian) }
    func testBothDirectionsAndMixedCase() {
        XCTAssertEqual(converter.convert("Ghbdtn Vbh"), "Привет Мир")
        XCTAssertEqual(converter.convert("Руддщ Цщкдв"), "Hello World")
        XCTAssertEqual(converter.convert("Gривет h"), "Пhbdtn р")
        XCTAssertFalse(converter.requiresDirection)
    }
    func testSymbolsAndUnpairedLettersStayIntact() {
        XCTAssertEqual(converter.convert("123 [] {};:,.!? @#$ ёЁхХъЪжЖэЭбБюЮ 🧑‍💻\n"), "123 [] {};:,.!? @#$ ёЁхХъЪжЖэЭбБюЮ 🧑‍💻\n")
    }
    func testRoundTrip() {
        let text = "aBcDeF xyz ПрИвЕт 123! 🐈"
        XCTAssertEqual(converter.convert(converter.convert(text)), text)
    }
    func testSharedAlphabetUsesActiveSourceForNonSymmetricMapping() {
        let a = layout("a", "abc")
        let b = layout("b", "bca")
        let forward = LayoutConverter(first: a, second: b, activeSourceID: "a")
        let reverse = LayoutConverter(first: a, second: b, activeSourceID: "b")
        XCTAssertTrue(forward.requiresDirection)
        XCTAssertEqual(forward.convert("aBc"), "bCa")
        XCTAssertEqual(reverse.convert("bCa"), "aBc")
        XCTAssertEqual(LayoutConverter(first: a, second: b).convert("abc"), "abc")
    }
    func testSharedLettersWithSymmetricMappingNeedNoDirection() {
        let converter = LayoutConverter(first: layout("a", "xyz"), second: layout("b", "xzy"))
        XCTAssertFalse(converter.requiresDirection)
        XCTAssertEqual(converter.convert("xYz"), "xZy")
    }
    func testDuplicateSourceLettersWithDifferentTargetsStayIntact() {
        let converter = LayoutConverter(first: layout("a", "aa"), second: layout("b", "бв"), activeSourceID: "a")
        XCTAssertEqual(converter.convert("aA"), "aA")
    }
    func testCaseMappingDoesNotCrashOnExpandingUppercase() {
        let converter = LayoutConverter(first: layout("a", "ß"), second: layout("b", "ж"))
        XCTAssertEqual(converter.convert("ß"), "ж")
    }
    func testEnabledSystemLayoutsHaveUniqueIDsAndReadableKeys() {
        let snapshot = SystemLayouts.enabled()
        XCTAssertEqual(Set(snapshot.layouts.map(\.id)).count, snapshot.layouts.count)
        for layout in snapshot.layouts {
            XCTAssertFalse(layout.title.isEmpty)
            XCTAssertTrue(layout.characters.values.contains(where: \.isLetter))
        }
    }
    func testNativeQwertyAndRussianWhenEnabled() throws {
        let layouts = SystemLayouts.enabled().layouts
        let normalA = KeyPosition(code: 0)
        let normalQ = KeyPosition(code: 12)
        guard let english = layouts.first(where: { $0.characters[normalA] == "a" && $0.characters[normalQ] == "q" }),
              let russian = layouts.first(where: { $0.characters[normalA] == "ф" && $0.characters[normalQ] == "й" }) else {
            throw XCTSkip("QWERTY and Russian are not both enabled on this Mac")
        }
        let converter = LayoutConverter(first: english, second: russian)
        XCTAssertEqual(converter.convert("Ghbdtn Vbh"), "Привет Мир")
        XCTAssertEqual(converter.convert("Руддщ"), "Hello")
    }
}
