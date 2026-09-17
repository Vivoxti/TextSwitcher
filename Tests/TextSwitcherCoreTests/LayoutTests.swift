import XCTest
@testable import TextSwitcherCore

final class LayoutTests: XCTestCase {
    let converter = LayoutConverter(first: .english, second: .russian)
    func testBothDirectionsAndMixedCase() {
        XCTAssertEqual(converter.convert("Ghbdtn Vbh"), "Привет Мир")
        XCTAssertEqual(converter.convert("Руддщ Цщкдв"), "Hello World")
        XCTAssertEqual(converter.convert("Gривет h"), "Пhbdtn р")
    }
    func testSymbolsAndUnpairedLettersStayIntact() {
        XCTAssertEqual(converter.convert("123 [] {};:,.!? @#$ ёЁхХъЪжЖэЭбБюЮ 🧑‍💻\n"), "123 [] {};:,.!? @#$ ёЁхХъЪжЖэЭбБюЮ 🧑‍💻\n")
    }
    func testRoundTrip() {
        let text = "aBcDeF xyz ПрИвЕт 123! 🐈"
        XCTAssertEqual(converter.convert(converter.convert(text)), text)
    }
    func testAllLayoutPositionsAndCompatibility() {
        for layout in KeyboardLayout.allCases { XCTAssertEqual(layout.keys.count, KeyboardLayout.english.keys.count) }
        XCTAssertFalse(KeyboardLayout.russian.isCompatible(with: .ukrainian))
        XCTAssertTrue(KeyboardLayout.greek.isCompatible(with: .ukrainian))
    }
    func testUkrainianAndGreek() {
        XCTAssertEqual(LayoutConverter(first: .english, second: .ukrainian).convert("sSbB"), "іІиИ")
        XCTAssertEqual(LayoutConverter(first: .english, second: .greek).convert("aAeE"), "αΑεΕ")
    }
}
