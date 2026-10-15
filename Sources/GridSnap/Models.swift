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

/// A rectangle as fractions of the screen (0–1, origin top-left).
///
/// Shortcuts store this rather than cell numbers so their layout survives grid
/// size changes: it's snapped to whichever grid is in use, and changing the grid
/// back restores the exact original.
struct UnitRect: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ area: GridArea, in grid: GridSize) {
        let columns = Double(grid.columns), rows = Double(grid.rows)
        self.init(
            x: Double(area.col) / columns,
            y: Double(area.row) / rows,
            width: Double(area.colSpan) / columns,
            height: Double(area.rowSpan) / rows
        )
    }

    /// The nearest whole cells on `grid`, always at least one cell.
    /// Exact ties widen the area (start rounds down, end rounds up), so a
    /// centred area stays centred.
    func snapped(to grid: GridSize) -> GridArea {
        func snap(_ start: Double, _ length: Double, _ count: Int) -> (start: Int, span: Int) {
            let n = Double(count)
            let first = min(max(Int((start * n - 0.5 - 1e-9).rounded(.up)), 0), count - 1)
            let end = min(max(Int(((start + length) * n + 0.5 + 1e-9).rounded(.down)), first + 1), count)
            return (first, end - first)
        }
        let cols = snap(x, width, grid.columns)
        let rows = snap(y, height, grid.rows)
        return GridArea(col: cols.start, row: rows.start, colSpan: cols.span, rowSpan: rows.span)
    }

    static let full = UnitRect(x: 0, y: 0, width: 1, height: 1)
}

struct Shortcut: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Where the window goes, independent of grid size.
    var region: UnitRect
    var hotKey: HotKey?
    /// Overrides the global grid for this shortcut when set.
    var grid: GridSize?
    /// Cell numbers from saves made before `region` existed. The store converts
    /// these on load (it knows the grid they referred to); never written back.
    var legacyArea: GridArea?

    /// The region as cells of `grid`, for editing. Setting it stores the cells'
    /// exact proportions.
    func area(in grid: GridSize) -> GridArea { region.snapped(to: grid) }

    mutating func setArea(_ area: GridArea, in grid: GridSize) {
        region = UnitRect(area, in: grid)
    }

    init(name: String, region: UnitRect, hotKey: HotKey? = nil, grid: GridSize? = nil) {
        self.name = name
        self.region = region
        self.hotKey = hotKey
        self.grid = grid
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, region, hotKey, grid
        case area // legacy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        hotKey = try c.decodeIfPresent(HotKey.self, forKey: .hotKey)
        grid = try c.decodeIfPresent(GridSize.self, forKey: .grid)
        if let region = try c.decodeIfPresent(UnitRect.self, forKey: .region) {
            self.region = region
        } else {
            region = .full
            legacyArea = try c.decode(GridArea.self, forKey: .area)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(region, forKey: .region)
        try c.encodeIfPresent(hotKey, forKey: .hotKey)
        try c.encodeIfPresent(grid, forKey: .grid)
    }
}
