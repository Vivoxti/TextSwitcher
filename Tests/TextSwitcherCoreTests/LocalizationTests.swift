import XCTest
@testable import TextSwitcherCore

final class LocalizationTests: XCTestCase {
    func testRegionalLanguageMatchingAndFallback() {
        let cases = ["en-US": "en", "ru-RU": "ru", "uk-UA": "uk", "de-CH": "de", "fr-CA": "fr",
                     "es-MX": "es", "pt-BR": "pt", "pl-PL": "pl", "ja-JP": "ja", "ko-KR": "ko",
                     "zh-CN": "zh-Hans", "zh-TW": "zh-Hant"]
        for (preference, expected) in cases {
            XCTAssertEqual(L10n.language(for: [preference]), expected, preference)
        }
        XCTAssertEqual(L10n.language(for: ["cs-CZ", "uk-UA", "en-US"]), "uk")
        XCTAssertEqual(L10n.language(for: ["cs-CZ"]), "en")
        XCTAssertEqual(L10n.language(for: []), "en")
    }
    func testEveryLanguageHasAllInterfaceAndErrorStrings() throws {
        let expected = Set(L10n.Key.allCases.map(\.rawValue))
        for language in L10n.supportedLanguages {
            let bundle = try XCTUnwrap(L10n.bundle(for: language), language)
            let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"), language)
            let translations = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String], language)
            XCTAssertEqual(Set(translations.keys), expected, language)
            XCTAssertTrue(translations.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, language)
        }
    }
    func testUkrainianTranslationAndUnsupportedLanguage() {
        XCTAssertEqual(L10n.text(.settingsMenu, language: "uk-UA"), "Параметри…")
        XCTAssertEqual(L10n.text(.secureFieldError, language: "uk"), "Поля паролів не підтримуються.")
        XCTAssertEqual(L10n.text(.settingsMenu, language: "cs"), "Settings…")
        XCTAssertEqual(L10n.text(.chooseTwoLayouts, language: "en"), "Choose two different layouts enabled in macOS.")
    }
}
