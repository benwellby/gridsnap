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
            if shortcuts.contains(where: { $0.legacyArea != nil }) {
                shortcuts = shortcuts.map(convertLegacyArea)
                save()
            }
        } else {
            columns = 16
            rows = 16
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

    /// The shortcut's region snapped to the cells of its grid.
    func area(for shortcut: Shortcut) -> GridArea {
        shortcut.region.snapped(to: grid(for: shortcut))
    }

    func apply(_ shortcut: Shortcut) {
        let grid = grid(for: shortcut)
        WindowMover.move(to: area(for: shortcut), columns: grid.columns, rows: grid.rows)
    }

    /// Older saves stored cell numbers relative to the shortcut's grid at the time.
    /// Fit them to that grid, then store them as a proportional region.
    private func convertLegacyArea(_ shortcut: Shortcut) -> Shortcut {
        guard let legacy = shortcut.legacyArea else { return shortcut }
        var converted = shortcut
        let grid = grid(for: shortcut)
        converted.region = UnitRect(legacy.clamped(columns: grid.columns, rows: grid.rows), in: grid)
        converted.legacyArea = nil
        return converted
    }

    func apply(id: UUID) {
        if let s = shortcuts.first(where: { $0.id == id }) { apply(s) }
    }

    func addShortcut() {
        let grid = GridSize(columns: columns, rows: rows)
        shortcuts.append(Shortcut(name: "Move & Resize", region: UnitRect(GridArea(col: 0, row: 0, colSpan: 1, rowSpan: 1), in: grid)))
    }

    func delete(_ id: UUID) {
        shortcuts.removeAll { $0.id == id }
    }

    // Defaults, all on ⌥⌘. The corners and full screen use their own simpler grids;
    // the centred layouts use the fine 16 × 16 global grid.
    private static let defaultShortcuts: [Shortcut] = {
        func hk(_ code: UInt32, _ key: String) -> HotKey { HotKey(keyCode: code, modifiers: HotKey.optCmd, key: key) }
        func cells(_ col: Int, _ row: Int, _ colSpan: Int, _ rowSpan: Int, of grid: GridSize) -> UnitRect {
            UnitRect(GridArea(col: col, row: row, colSpan: colSpan, rowSpan: rowSpan), in: grid)
        }
        let quarters = GridSize(columns: 2, rows: 2)
        let fine = GridSize(columns: 16, rows: 16)
        return [
            Shortcut(name: "Top Left", region: cells(0, 0, 1, 1, of: quarters), hotKey: hk(18, "1"), grid: quarters),
            Shortcut(name: "Top Right", region: cells(1, 0, 1, 1, of: quarters), hotKey: hk(19, "2"), grid: quarters),
            Shortcut(name: "Bottom Right", region: cells(1, 1, 1, 1, of: quarters), hotKey: hk(20, "3"), grid: quarters),
            Shortcut(name: "Bottom Left", region: cells(0, 1, 1, 1, of: quarters), hotKey: hk(21, "4"), grid: quarters),
            Shortcut(name: "Centre", region: cells(3, 2, 10, 12, of: fine), hotKey: hk(23, "5")),
            Shortcut(name: "Centre full", region: cells(3, 0, 10, 16, of: fine), hotKey: hk(22, "6")),
            Shortcut(name: "Full screen", region: .full, hotKey: hk(14, "E"), grid: GridSize(columns: 1, rows: 1)),
        ]
    }()
}
