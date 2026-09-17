import Foundation

public enum L10n {
    public enum Key: String, CaseIterable {
        case subtitle, layouts, firstLayout, secondLayout, convert, recordShortcut, changeShortcut
        case automaticHint, launchAtLogin, accessibilityAllowed, accessibilityRequired
        case allow, lettersHint, recordingHint, shiftHint, localOnly, settingsTitle, settingsMenu, quitMenu
        case loginApproval, loginFailed, shortcutFailed, registrationFailed
        case permissionError, noFieldError, secureFieldError, focusChangedError, copyFailedError
        case selectFailedError, pasteFailedError, unsupportedClipboardError
        case systemLayoutsHint, chooseTwoLayouts, activeLayoutRequired, unsupportedSources
        case keySpace, keyDecimal, keyHome, keyEnd, keyPageUp, keyPageDown, keyUnknown
    }
    public static let supportedLanguages = ["en", "ru", "uk", "de", "fr", "es", "it", "pt", "pl", "ja", "ko", "zh-Hans", "zh-Hant"]
    public static func language(for preferences: [String]) -> String {
        Bundle.preferredLocalizations(from: supportedLanguages, forPreferences: preferences + ["en"]).first ?? "en"
    }
    public static var currentLanguage: String { language(for: Locale.preferredLanguages) }
    static func bundle(for language: String) -> Bundle? {
        // Installed apps have native .lproj resources; SwiftPM builds use their
        // resource bundle. Avoid touching Bundle.module in installed applications.
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) { return bundle }
        let resources: Bundle
        if let url = Bundle.main.resourceURL?.appendingPathComponent("TextSwitcher_TextSwitcherCore.bundle"), let installed = Bundle(url: url) {
            resources = installed
        } else { resources = Bundle.module }
        for identifier in [language, language.lowercased()] {
            if let path = resources.path(forResource: identifier, ofType: "lproj"), let bundle = Bundle(path: path) { return bundle }
        }
        return nil
    }
    public static func text(_ key: Key, language: String? = nil) -> String {
        let selected = language.map { self.language(for: [$0]) } ?? currentLanguage
        let fallback = bundle(for: "en")?.localizedString(forKey: key.rawValue, value: nil, table: nil) ?? key.rawValue
        return bundle(for: selected)?.localizedString(forKey: key.rawValue, value: fallback, table: nil) ?? fallback
    }
}
