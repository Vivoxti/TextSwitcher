import AppKit
import Carbon
import ApplicationServices
import TextSwitcherCore

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    static let shift = Shortcut(keyCode: 56, modifiers: 0)
    var isShift: Bool { keyCode == 56 && modifiers == 0 }
    var display: String {
        if isShift { return "⇧ Shift" }
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        let label: String
        switch keyCode {
        case 49: label = L10n.text(.keySpace)
        case 65: label = L10n.text(.keyDecimal)
        case 115: label = L10n.text(.keyHome)
        case 119: label = L10n.text(.keyEnd)
        case 116: label = L10n.text(.keyPageUp)
        case 121: label = L10n.text(.keyPageDown)
        default: label = Self.keyNames[keyCode] ?? "\(L10n.text(.keyUnknown)) \(keyCode)"
        }
        return text + label
    }
    static let keyNames: [UInt32: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",
        12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",
        24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",
        36:"↩",37:"L",38:"J",39:"′",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",
        48:"⇥",49:"Space",50:"`",51:"⌫",65:"Decimal",67:"×",69:"+",75:"÷",76:"Enter",78:"−",
        82:"0",83:"1",84:"2",85:"3",86:"4",87:"5",88:"6",89:"7",91:"8",92:"9",
        122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",
        105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20",
        115:"Home",116:"Page Up",117:"⌦",119:"End",121:"Page Down",123:"←",124:"→",125:"↓",126:"↑"
    ]
    static func from(_ event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags
        // Require a modifier for ordinary keys, preventing accidental typing interception.
        let functionKeys: Set<UInt16> = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) || functionKeys.contains(event.keyCode) else { return nil }
        guard keyNames[UInt32(event.keyCode)] != nil else { return nil }
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        return Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods)
    }
}

final class HotkeyManager {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var shortcuts: [UInt32: Shortcut] = [:]
    private var handler: EventHandlerRef?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var shiftDetector = ShiftTapDetector()
    var onPress: ((UInt32) -> Void)?
    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if result == noErr { Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().onPress?(id.id) }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcut: Shortcut, id: UInt32) -> Bool {
        if shortcuts[id] == shortcut, refs[id] != nil { return true }
        let previous = shortcuts[id]
        if let old = refs.removeValue(forKey: id) { UnregisterEventHotKey(old) }
        shortcuts.removeValue(forKey: id)
        stopShiftMonitor()
        if shortcut.isShift {
            // Registration can precede granting Accessibility. The permission poll
            // in the app retries creation once access is available.
            shortcuts[id] = shortcut
            return !AXIsProcessTrusted() || startShiftMonitor()
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x54535754, id: id), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            if let previous { _ = register(previous, id: id) }
            return false
        }
        refs[id] = ref
        shortcuts[id] = shortcut
        return true
    }
    func retryShiftMonitor() {
        if shortcuts.values.contains(where: \.isShift), tap == nil, AXIsProcessTrusted() { _ = startShiftMonitor() }
    }
    private func startShiftMonitor() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, data in
            guard let data else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(data).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                manager.shiftDetector.cancel()
                if let tap = manager.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if type == .flagsChanged {
                let flags = event.flags
                let trigger = manager.shiftDetector.flagsChanged(
                    keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                    shift: flags.contains(.maskShift),
                    otherModifiers: !flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn]).isEmpty,
                    time: ProcessInfo.processInfo.systemUptime)
                if trigger { DispatchQueue.main.async { manager.onPress?(1) } }
            } else { manager.shiftDetector.cancel() }
            // Pass every event through: Shift continues to work normally everywhere.
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    private func stopShiftMonitor() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil; shiftDetector.cancel()
    }
    func suspend() { refs.values.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); shortcuts.removeAll(); stopShiftMonitor() }
    deinit { suspend(); if let handler { RemoveEventHandler(handler) } }
}
