import Foundation

/// A standalone modifier tap, excluding typing, mouse selection and other modifiers.
public struct ShiftTapDetector {
    private var candidate: (side: UInt16, started: TimeInterval)?
    public init() {}
    public mutating func cancel() { candidate = nil }
    public mutating func flagsChanged(keyCode: UInt16, shift: Bool, otherModifiers: Bool, time: TimeInterval) -> Bool {
        guard (keyCode == 56 || keyCode == 60), !otherModifiers else { cancel(); return false }
        if shift {
            if candidate == nil { candidate = (keyCode, time) }
            else { cancel() }
            return false
        }
        defer { cancel() }
        guard let candidate, candidate.side == keyCode else { return false }
        let duration = time - candidate.started
        return duration >= 0 && duration <= 0.75
    }
}

public enum SublimeCopyKind: Equatable {
    case selection, currentLine, unsupported
    public init(metadata: Data?) {
        // Sublime Text's version-3 clipboard metadata begins with a little-endian
        // version UInt32 and a Boolean marking a copy of an empty selection's line.
        guard let metadata, metadata.count >= 9,
              Array(metadata.prefix(4)) == [3, 0, 0, 0], metadata[4] <= 1 else {
            self = .unsupported; return
        }
        self = metadata[4] == 1 ? .currentLine : .selection
    }
}
