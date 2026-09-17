import AppKit
import ApplicationServices
import TextSwitcherCore

enum ReplacementFailure: LocalizedError {
    case permission, noField, secureField, focusChanged, copyFailed, selectFailed, pasteFailed, unsupportedClipboard
    var errorDescription: String? {
        switch self {
        case .permission: return "Разрешите TextSwitcher универсальный доступ в Системных настройках."
        case .noField: return "Поместите курсор в поле ввода. Не удалось определить редактируемое поле."
        case .secureField: return "Поля паролей не поддерживаются."
        case .focusChanged: return "Фокус или выделение изменились. Повторите нажатие в нужном поле."
        case .copyFailed: return "Поле не ответило на ⌘C. Проверьте, что курсор находится в тексте."
        case .selectFailed: return "Приложение не разрешило выделить всё поле."
        case .pasteFailed: return "Не удалось отправить команду вставки."
        case .unsupportedClipboard: return "Не удалось определить выделение в этой версии Sublime Text."
        }
    }
}

@MainActor final class TextReplacement {
    nonisolated init() {}
    private var busy = false
    private var accessibleApps: Set<pid_t> = []
    private static let sublimeMetadata = NSPasteboard.PasteboardType("sublime-text-extra")
    private struct Focus {
        let element: AXUIElement
        let pid: pid_t
        func isCurrent() -> Bool {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let current = TextReplacement.focusedElement(pid: pid) else { return false }
            return CFEqual(current, element)
        }
    }
    nonisolated private static func focusedElement(pid: pid_t) -> AXUIElement? {
        for root in [AXUIElementCreateApplication(pid), AXUIElementCreateSystemWide()] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }
        return nil
    }
    private func attribute(_ key: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    private func range(of element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, from: element), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
    @discardableResult private func select(_ range: CFRange, in element: AXUIElement) -> Bool {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }
    private func key(_ code: CGKeyCode, focus: Focus) throws {
        guard focus.isCurrent() else { throw ReplacementFailure.focusChanged }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { throw ReplacementFailure.pasteFailed }
        down.flags = .maskCommand; up.flags = .maskCommand
        // The normal event route is required by custom editors and Electron.
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    private func copiedText(focus: Focus, ownedCount: inout Int?) async throws -> String? {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        ownedCount = pasteboard.changeCount
        let copyCount = pasteboard.changeCount
        try key(8, focus: focus)
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 20_000_000)
            guard focus.isCurrent() else { throw ReplacementFailure.focusChanged }
            if pasteboard.changeCount != copyCount {
                ownedCount = pasteboard.changeCount
                return pasteboard.string(forType: .string)
            }
        }
        return nil
    }
    func replace(converter: LayoutConverter) async throws {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        guard AXIsProcessTrusted() else { throw ReplacementFailure.permission }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw ReplacementFailure.noField }
        let pid = app.processIdentifier
        // Electron exposes its editor only after assistive technology requests it.
        if !accessibleApps.contains(pid) {
            let root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, 1)
            let enabled = AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            accessibleApps.insert(pid)
            if enabled == .success { try await Task.sleep(nanoseconds: 100_000_000) }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let element = Self.focusedElement(pid: pid) else { throw ReplacementFailure.noField }
        let focus = Focus(element: element, pid: pid)
        for _ in 0..<100 {
            if CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              focus.isCurrent() else { throw ReplacementFailure.focusChanged }
        let role = attribute(kAXRoleAttribute, from: element) as? String ?? ""
        let subrole = attribute(kAXSubroleAttribute, from: element) as? String ?? ""
        guard subrole != kAXSecureTextFieldSubrole else { throw ReplacementFailure.secureField }
        let isSublime = ["com.sublimetext.3", "com.sublimetext.4"].contains(app.bundleIdentifier ?? "")
        let isTextField = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
        // A text editor need not expose writable AXValue / AXSelectedText: keyboard
        // paste still works. Sublime exposes its editor as the window itself.
        guard isTextField || (isSublime && role == kAXWindowRole) else { throw ReplacementFailure.noField }
        let oldRange = range(of: element)
        let selectedText = attribute(kAXSelectedTextAttribute, from: element) as? String
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        var ownedCount: Int?
        var selectedAll = false
        var pasted = false
        defer {
            if selectedAll && !pasted && focus.isCurrent() {
                if let oldRange { select(oldRange, in: element) }
                else if isSublime { try? key(32, focus: focus) } // Sublime soft undo restores selection only.
            }
            if let ownedCount, pasteboard.changeCount == ownedCount {
                pasteboard.clearContents()
                let items = saved.map { representations -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    representations.forEach { item.setData($0.1, forType: $0.0) }
                    return item
                }
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
        }
        var text: String?
        var all: Bool
        if let oldRange { all = oldRange.length == 0 }
        else if let selectedText { all = selectedText.isEmpty }
        else if isSublime {
            text = try await copiedText(focus: focus, ownedCount: &ownedCount)
            if text == nil { all = true } // copy_with_empty_selection may be disabled.
            else {
                switch SublimeCopyKind(metadata: pasteboard.data(forType: Self.sublimeMetadata)) {
                case .currentLine: all = true; text = nil
                case .selection: all = false
                case .unsupported: throw ReplacementFailure.unsupportedClipboard
                }
            }
        } else { throw ReplacementFailure.noField }

        if all {
            if let value = attribute(kAXValueAttribute, from: element) as? String,
               value.isEmpty || converter.convert(value) == value { return }
            try key(0, focus: focus)
            selectedAll = true
            try await Task.sleep(nanoseconds: 100_000_000)
            guard focus.isCurrent() else { throw ReplacementFailure.focusChanged }
            if let selection = range(of: element), selection.length == 0 { throw ReplacementFailure.selectFailed }
            text = try await copiedText(focus: focus, ownedCount: &ownedCount)
            if isSublime, text != nil, SublimeCopyKind(metadata: pasteboard.data(forType: Self.sublimeMetadata)) != .selection {
                throw ReplacementFailure.selectFailed
            }
        } else if text == nil {
            text = selectedText
            if text == nil || text?.isEmpty == true { text = try await copiedText(focus: focus, ownedCount: &ownedCount) }
        }
        guard let text else { throw ReplacementFailure.copyFailed }
        if text.isEmpty { return }
        let converted = converter.convert(text)
        if converted == text { return }
        guard focus.isCurrent() else { throw ReplacementFailure.focusChanged }
        if !all, let oldRange, let current = range(of: element),
           oldRange.location != current.location || oldRange.length != current.length { throw ReplacementFailure.focusChanged }
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        ownedCount = pasteboard.changeCount
        try key(9, focus: focus)
        pasted = true
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}
