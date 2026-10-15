import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A rectangle of grid cells. Row 0 is the top row.
struct GridArea: Codable, Equatable, Hashable {
    var col: Int
    var row: Int
    var colSpan: Int
    var rowSpan: Int

    /// Fits the area inside a grid without mutating the stored value, so shrinking
    /// and re-growing the grid doesn't lose the original layout.
    func clamped(columns: Int, rows: Int) -> GridArea {
        let c = min(max(col, 0), columns - 1)
        let r = min(max(row, 0), rows - 1)
        return GridArea(
            col: c,
            row: r,
            colSpan: min(max(colSpan, 1), columns - c),
            rowSpan: min(max(rowSpan, 1), rows - r)
        )
    }
}

struct HotKey: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt   // NSEvent.ModifierFlags raw value
    var key: String       // display name, e.g. "1", "←"

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var displayString: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key
    }

    /// Lets the menu show the shortcut natively, right-aligned like system menus.
    var keyEquivalent: KeyEquivalent? {
        switch keyCode {
        case 123: return .leftArrow
        case 124: return .rightArrow
        case 125: return .downArrow
        case 126: return .upArrow
        case 36: return .return
        case 48: return .tab
        case 49: return .space
        case 51: return .delete
        case 53: return .escape
        default:
            guard key.count == 1, let c = key.lowercased().first else { return nil }
            return KeyEquivalent(c)
        }
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var m: SwiftUI.EventModifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.shift) { m.insert(.shift) }
        return m
    }

    private static let specialKeys: [UInt16: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func keyName(for event: NSEvent) -> String {
        if let name = specialKeys[event.keyCode] { return name }
        return (event.characters(byApplyingModifiers: []) ?? "?").uppercased()
    }

    static let optCmd: UInt = NSEvent.ModifierFlags([.option, .command]).rawValue

    /// ⌃⌥⌘H
    static let defaultDimToggle = HotKey(
        keyCode: 4, modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue, key: "H"
    )
}

struct GridSize: Codable, Equatable, Hashable {
    var columns: Int
    var rows: Int
}

struct Shortcut: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var area: GridArea
    var hotKey: HotKey?
    /// Overrides the global grid for this shortcut when set.
    var grid: GridSize?
}
