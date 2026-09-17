import Foundation

public enum KeyboardLayout: String, CaseIterable, Codable, Identifiable {
    case english, russian, ukrainian, greek
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .english: return L10n.text(.layoutEnglish)
        case .russian: return L10n.text(.layoutRussian)
        case .ukrainian: return L10n.text(.layoutUkrainian)
        case .greek: return L10n.text(.layoutGreek)
        }
    }
    // Corresponding physical positions, including punctuation positions.
    public var keys: String {
        switch self {
        case .english: return "`qwertyuiop[]asdfghjkl;'zxcvbnm,."
        case .russian: return "ёйцукенгшщзхъфывапролджэячсмитьбю"
        case .ukrainian: return "'йцукенгшщзхїфівапролджєячсмитьбю"
        case .greek: return "`;ςερτυθιοπ[]ασδφγηξκλ΄'ζχψωβνμ,."
        }
    }
    private var script: Int {
        switch self { case .english: return 0; case .russian, .ukrainian: return 1; case .greek: return 2 }
    }
    public func isCompatible(with other: KeyboardLayout) -> Bool { script != other.script }
}

public struct LayoutConverter {
    private let replacements: [Character: String]
    public init(first: KeyboardLayout, second: KeyboardLayout) {
        var map: [Character: String] = [:]
        if first.isCompatible(with: second) {
            for (a, b) in zip(first.keys, second.keys) where a.isLetter && b.isLetter {
                map[a] = String(b)
                map[b] = String(a)
                map[Character(String(a).uppercased())] = String(b).uppercased()
                map[Character(String(b).uppercased())] = String(a).uppercased()
            }
        }
        replacements = map
    }
    public func convert(_ text: String) -> String {
        text.map { replacements[$0] ?? String($0) }.joined()
    }
}
