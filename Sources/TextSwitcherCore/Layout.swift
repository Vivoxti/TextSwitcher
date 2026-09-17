import Foundation

public struct KeyPosition: Hashable {
    public let code: UInt16
    public let modifiers: UInt32
    public init(code: UInt16, modifiers: UInt32 = 0) { self.code = code; self.modifiers = modifiers }
}

public struct KeyboardLayout: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let characters: [KeyPosition: Character]
    public init(id: String, title: String, characters: [KeyPosition: Character]) {
        self.id = id; self.title = title; self.characters = characters
    }
    fileprivate var letters: Set<Character> {
        var letters = Set(characters.values.filter(\.isLetter))
        for letter in Array(letters) {
            for variant in [String(letter).lowercased(), String(letter).uppercased()] where variant.count == 1 {
                if let character = variant.first { letters.insert(character) }
            }
        }
        return letters
    }
}

public struct LayoutConverter {
    private let replacements: [Character: String]
    public let requiresDirection: Bool
    public init(first: KeyboardLayout, second: KeyboardLayout, activeSourceID: String? = nil) {
        func mapping(from source: KeyboardLayout, to target: KeyboardLayout) -> [Character: String] {
            var candidates: [Character: Set<String>] = [:]
            for (position, a) in source.characters {
                guard a.isLetter, let b = target.characters[position], b.isLetter else { continue }
                let sameCase = a.isUppercase ? String(b).uppercased() : a.isLowercase ? String(b).lowercased() : String(b)
                for (key, value) in [(String(a), sameCase), (String(a).lowercased(), String(b).lowercased()), (String(a).uppercased(), String(b).uppercased())] {
                    guard key.count == 1, value.count == 1, let character = key.first else { continue }
                    candidates[character, default: []].insert(value)
                }
            }
            // A letter occurring on several keys is converted only if its target
            // is unambiguous; never choose a random key from a dictionary.
            return candidates.compactMapValues { $0.count == 1 ? $0.first : nil }
        }
        let forward = mapping(from: first, to: second)
        let reverse = mapping(from: second, to: first)
        let firstLetters = first.letters
        let secondLetters = second.letters
        let shared = firstLetters.intersection(secondLetters)
        requiresDirection = shared.contains { forward[$0] != reverse[$0] }
        var map: [Character: String] = [:]
        for letter in firstLetters.union(secondLetters) {
            if shared.contains(letter) {
                if forward[letter] == reverse[letter] { map[letter] = forward[letter] }
                else if activeSourceID == first.id { map[letter] = forward[letter] }
                else if activeSourceID == second.id { map[letter] = reverse[letter] }
            } else { map[letter] = firstLetters.contains(letter) ? forward[letter] : reverse[letter] }
        }
        replacements = map
    }
    public func convert(_ text: String) -> String {
        text.map { character in
            let normalized = String(character).precomposedStringWithCanonicalMapping
            return normalized.first.flatMap { replacements[$0] } ?? String(character)
        }.joined()
    }
}
