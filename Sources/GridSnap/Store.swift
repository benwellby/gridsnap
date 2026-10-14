import Foundation

final class Store: ObservableObject {
    static let shared = Store()

    @Published var columns: Int { didSet { save() } }
    @Published var rows: Int { didSet { save() } }
    @Published var shortcuts: [Shortcut] { didSet { save(); registerHotKeys() } }

    @Published var dimEnabled: Bool { didSet { save(); applyDim() } }
    @Published var dimOpacity: Double { didSet { save(); applyDim() } }
    @Published var dimHotKey: HotKey? { didSet { save(); registerHotKeys() } }

    /// Hotkey id for toggling dimming, alongside the shortcut ids.
    static let dimToggleID = UUID(uuidString: "00000000-0000-0000-0000-00000000D1A0")!

    /// Shortcuts whose key combo couldn't be registered (taken by macOS or another app).
    @Published private(set) var unavailable: Set<UUID> = []

    private struct Persisted: Codable {
        var columns: Int
        var rows: Int
        var shortcuts: [Shortcut]
        var dim: DimSettings?
    }

    private struct DimSettings: Codable {
        var enabled: Bool
        var opacity: Double
        var hotKey: HotKey?
    }

    private static let defaultsKey = "config"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Persisted.self, from: data) {
            columns = saved.columns
            rows = saved.rows
            shortcuts = saved.shortcuts
            dimEnabled = saved.dim?.enabled ?? false
            dimOpacity = saved.dim?.opacity ?? 0.5
            dimHotKey = saved.dim == nil ? HotKey.defaultDimToggle : saved.dim?.hotKey
        } else {
            columns = 4
            rows = 2
            shortcuts = Self.defaultShortcuts
            dimEnabled = false
            dimOpacity = 0.5
            dimHotKey = HotKey.defaultDimToggle
        }
    }

    private func save() {
        let data = try? JSONEncoder().encode(Persisted(
            columns: columns, rows: rows, shortcuts: shortcuts,
            dim: DimSettings(enabled: dimEnabled, opacity: dimOpacity, hotKey: dimHotKey)
        ))
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    func registerHotKeys() {
        var bindings = shortcuts.compactMap { s in s.hotKey.map { (id: s.id, hotKey: $0) } }
        if let dimHotKey { bindings.append((id: Self.dimToggleID, hotKey: dimHotKey)) }
        let failed = HotKeyManager.shared.register(bindings)
        if failed != unavailable { unavailable = failed }
    }

    func handleHotKey(_ id: UUID) {
        if id == Self.dimToggleID {
            dimEnabled.toggle()
        } else {
            apply(id: id)
        }
    }

    func applyDim() {
        Dimmer.shared.update(enabled: dimEnabled, opacity: dimOpacity)
    }

    /// Every assigned hotkey, for spotting duplicates.
    var allHotKeys: [HotKey] {
        shortcuts.compactMap(\.hotKey) + [dimHotKey].compactMap { $0 }
    }

    /// The grid a shortcut uses: its own override, or the global grid.
    func grid(for shortcut: Shortcut) -> GridSize {
        shortcut.grid ?? GridSize(columns: columns, rows: rows)
    }

    func clampedArea(_ shortcut: Shortcut) -> GridArea {
        let grid = grid(for: shortcut)
        return shortcut.area.clamped(columns: grid.columns, rows: grid.rows)
    }

    func apply(_ shortcut: Shortcut) {
        let grid = grid(for: shortcut)
        WindowMover.move(to: clampedArea(shortcut), columns: grid.columns, rows: grid.rows)
    }

    func apply(id: UUID) {
        if let s = shortcuts.first(where: { $0.id == id }) { apply(s) }
    }

    func addShortcut() {
        shortcuts.append(Shortcut(name: "Move & Resize", area: GridArea(col: 0, row: 0, colSpan: 1, rowSpan: 1)))
    }

    func delete(_ id: UUID) {
        shortcuts.removeAll { $0.id == id }
    }

    // Defaults for a 4 × 2 grid, using ⌃⌥ to avoid clashing with common app shortcuts.
    private static let defaultShortcuts: [Shortcut] = {
        func hk(_ code: UInt32, _ key: String) -> HotKey { HotKey(keyCode: code, modifiers: HotKey.ctrlOpt, key: key) }
        return [
            Shortcut(name: "Left Half", area: GridArea(col: 0, row: 0, colSpan: 2, rowSpan: 2), hotKey: hk(123, "←")),
            Shortcut(name: "Right Half", area: GridArea(col: 2, row: 0, colSpan: 2, rowSpan: 2), hotKey: hk(124, "→")),
            Shortcut(name: "Top Left", area: GridArea(col: 0, row: 0, colSpan: 2, rowSpan: 1), hotKey: hk(32, "U")),
            Shortcut(name: "Top Right", area: GridArea(col: 2, row: 0, colSpan: 2, rowSpan: 1), hotKey: hk(34, "I")),
            Shortcut(name: "Bottom Left", area: GridArea(col: 0, row: 1, colSpan: 2, rowSpan: 1), hotKey: hk(38, "J")),
            Shortcut(name: "Bottom Right", area: GridArea(col: 2, row: 1, colSpan: 2, rowSpan: 1), hotKey: hk(40, "K")),
            Shortcut(name: "Centre", area: GridArea(col: 1, row: 0, colSpan: 2, rowSpan: 2), hotKey: hk(8, "C")),
            Shortcut(name: "Maximise", area: GridArea(col: 0, row: 0, colSpan: 4, rowSpan: 2), hotKey: hk(36, "↩")),
        ]
    }()
}
