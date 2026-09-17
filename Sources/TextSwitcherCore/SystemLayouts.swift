import Foundation
import Carbon

public struct InputSourceSnapshot {
    public let layouts: [KeyboardLayout]
    public let unsupportedNames: [String]
}

public enum SystemLayouts {
    public static var changeNotification: Notification.Name { Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String) }
    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
    public static var currentID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return string(source, kTISPropertyInputSourceID)
    }
    public static func enabled() -> InputSourceSnapshot {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ]
        guard let sources = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] else {
            return InputSourceSnapshot(layouts: [], unsupportedNames: [])
        }
        var layouts: [KeyboardLayout] = []
        var unsupported: [String] = []
        for source in sources {
            guard let id = string(source, kTISPropertyInputSourceID), let title = string(source, kTISPropertyLocalizedName) else { continue }
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { unsupported.append(title); continue }
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            guard CFDataGetLength(data) >= MemoryLayout<UCKeyboardLayout>.size, let bytes = CFDataGetBytePtr(data) else { unsupported.append(title); continue }
            let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
            var characters: [KeyPosition: Character] = [:]
            // Ordinary, Shift and Caps Lock layers. Dead-key compositions and
            // Option-only characters have no simple letter-to-letter counterpart.
            let modifiers: [UInt32] = [0, UInt32(shiftKey), UInt32(alphaLock), UInt32(shiftKey | alphaLock)]
            for code: UInt16 in 0..<128 {
                for flags in modifiers {
                    var deadState: UInt32 = 0
                    var length = 0
                    var output = [UniChar](repeating: 0, count: 8)
                    let result = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), flags >> 8, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadState, output.count, &length, &output)
                    guard result == noErr, length > 0, length <= output.count else { continue }
                    let value = String(utf16CodeUnits: output, count: length).precomposedStringWithCanonicalMapping
                    if value.count == 1, let character = value.first { characters[KeyPosition(code: code, modifiers: flags)] = character }
                }
            }
            let keyboard = KeyboardLayout(id: id, title: title, characters: characters)
            if characters.values.contains(where: \.isLetter) { layouts.append(keyboard) }
            else { unsupported.append(title) }
        }
        return InputSourceSnapshot(layouts: layouts, unsupportedNames: Array(Set(unsupported)).sorted())
    }
}
