import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var trusted = AXIsProcessTrusted()
    @State private var enlargedID: UUID?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Accessibility access") {
                    if trusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open Privacy Settings…") { WindowMover.openAccessibilitySettings() }
                    }
                }
            }

            Section("Dim Background") {
                Toggle("Dim windows behind the focused window", isOn: $store.dimEnabled)
                LabeledContent("Opacity") {
                    HStack {
                        Slider(value: $store.dimOpacity, in: 0.1...0.9)
                            .frame(width: 200)
                        Text("\(Int((store.dimOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Toggle shortcut") {
                    HStack {
                        if let warning = warning(id: Store.dimToggleID, hotKey: store.dimHotKey) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help(warning)
                        }
                        HotKeyRecorder(hotKey: $store.dimHotKey)
                    }
                }
            }

            Section("Grid") {
                NumberField(label: "Columns", value: $store.columns)
                NumberField(label: "Rows", value: $store.rows)
            }

            Section {
                ForEach($store.shortcuts) { $shortcut in
                    ShortcutRow(
                        shortcut: $shortcut,
                        grid: store.grid(for: shortcut),
                        warning: warning(for: shortcut),
                        onEnlarge: { enlargedID = shortcut.id },
                        onDelete: { store.delete(shortcut.id) }
                    )
                }
                Button("Add Shortcut", systemImage: "plus") { store.addShortcut() }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Drag across a grid to choose where the window goes, or click it to enlarge. Click a shortcut field and press a key combination (Esc cancels).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .overlay {
            if let index = store.shortcuts.firstIndex(where: { $0.id == enlargedID }) {
                EnlargedGridEditor(
                    shortcut: $store.shortcuts[index],
                    globalGrid: GridSize(columns: store.columns, rows: store.rows),
                    warning: warning(for: store.shortcuts[index]),
                    onDone: { enlargedID = nil }
                )
            }
        }
        .frame(width: 640)
        .frame(minHeight: 520, idealHeight: 720)
        .onReceive(timer) { _ in trusted = AXIsProcessTrusted() }
    }

    private func warning(for shortcut: Shortcut) -> String? {
        warning(id: shortcut.id, hotKey: shortcut.hotKey)
    }

    private func warning(id: UUID, hotKey: HotKey?) -> String? {
        guard let hotKey else { return nil }
        if store.allHotKeys.filter({ $0 == hotKey }).count > 1 {
            return "This key combination is used by more than one shortcut."
        }
        if store.unavailable.contains(id) {
            return "This key combination is already in use by macOS or another app."
        }
        return nil
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            loginError = "Approve GridSnap in System Settings → General → Login Items."
        }
    }
}

private struct ShortcutRow: View {
    @Binding var shortcut: Shortcut
    let grid: GridSize
    let warning: String?
    let onEnlarge: () -> Void
    let onDelete: () -> Void

    private var area: Binding<GridArea> {
        Binding(get: { shortcut.area(in: grid) }, set: { shortcut.setArea($0, in: grid) })
    }

    var body: some View {
        HStack(spacing: 12) {
            GridPicker(area: area, columns: grid.columns, rows: grid.rows, onTap: onEnlarge)
                .frame(width: 96, height: 60)
                .overlay(alignment: .topTrailing) {
                    if shortcut.grid != nil {
                        Text("\(grid.columns)×\(grid.rows)")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 4)
                            .background(.orange, in: Capsule())
                            .foregroundStyle(.white)
                            .offset(x: 6, y: -6)
                            .allowsHitTesting(false)
                    }
                }
                .help(shortcut.grid == nil
                      ? "Click to enlarge, or drag to select"
                      : "Uses its own \(grid.columns) × \(grid.rows) grid. Click to enlarge, or drag to select")
            TextField("Name", text: $shortcut.name)
                .labelsHidden()
            if let warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(warning)
            }
            HotKeyRecorder(hotKey: $shortcut.hotKey)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete shortcut")
        }
        .padding(.vertical, 2)
    }
}

/// A number that can be typed in or stepped, clamped to `range`.
/// Typed values apply on Return or when the field loses focus.
private struct NumberField: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...16

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(label, text: $text)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 40)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
                Stepper(label, value: $value, in: range)
                    .labelsHidden()
            }
        }
        .monospacedDigit()
        .onAppear { text = String(value) }
        .onChange(of: value) { _, newValue in text = String(newValue) }
    }

    private func commit() {
        if let typed = Int(text.trimmingCharacters(in: .whitespaces)) {
            value = min(max(typed, range.lowerBound), range.upperBound)
        }
        // Always reformat, so out-of-range or invalid input snaps back.
        text = String(value)
    }
}

/// Full-window grid editor for precise selection on dense grids.
private struct EnlargedGridEditor: View {
    @Binding var shortcut: Shortcut
    let globalGrid: GridSize
    let warning: String?
    let onDone: () -> Void

    private var grid: GridSize { shortcut.grid ?? globalGrid }
    private var columns: Int { grid.columns }
    private var rows: Int { grid.rows }

    private var area: Binding<GridArea> {
        Binding(get: { shortcut.area(in: grid) }, set: { shortcut.setArea($0, in: grid) })
    }

    private var customGrid: Binding<Bool> {
        Binding(
            get: { shortcut.grid != nil },
            set: { shortcut.grid = $0 ? globalGrid : nil }
        )
    }

    private func gridValue(_ keyPath: WritableKeyPath<GridSize, Int>) -> Binding<Int> {
        Binding(
            get: { (shortcut.grid ?? globalGrid)[keyPath: keyPath] },
            set: { shortcut.grid?[keyPath: keyPath] = $0 }
        )
    }

    /// Match the main screen's shape so the grid looks like the real layout.
    private var aspectRatio: CGFloat {
        let frame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 16, height: 10)
        return frame.width / frame.height
    }

    private var summary: String {
        let a = shortcut.area(in: grid)
        func range(_ start: Int, _ span: Int) -> String {
            span == 1 ? "\(start + 1)" : "\(start + 1)–\(start + span)"
        }
        return "Columns \(range(a.col, a.colSpan)) of \(columns) · Rows \(range(a.row, a.rowSpan)) of \(rows)"
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shortcut.name).font(.headline)
                    Text(summary).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if let warning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(warning)
                }
                HotKeyRecorder(hotKey: $shortcut.hotKey)
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 20) {
                Toggle("Custom grid for this shortcut", isOn: customGrid)
                Spacer()
                Group {
                    NumberField(label: "Columns", value: gridValue(\.columns))
                    NumberField(label: "Rows", value: gridValue(\.rows))
                }
                .disabled(shortcut.grid == nil)
            }
            .monospacedDigit()

            GridPicker(area: area, columns: columns, rows: rows)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Drag across the grid to choose where the window goes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Lets Esc close the editor too.
            Button("Close", action: onDone)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

/// A grid; drag across cells to select the target area.
private struct GridPicker: View {
    @Binding var area: GridArea
    let columns: Int
    let rows: Int
    var onTap: (() -> Void)? = nil
    @State private var dragStart: (col: Int, row: Int)?

    var body: some View {
        GeometryReader { geo in
            let cellW = geo.size.width / CGFloat(columns)
            let cellH = geo.size.height / CGFloat(rows)
            let shown = area.clamped(columns: columns, rows: rows)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor)
                    .frame(width: cellW * CGFloat(shown.colSpan) - 2, height: cellH * CGFloat(shown.rowSpan) - 2)
                    .offset(x: cellW * CGFloat(shown.col) + 1, y: cellH * CGFloat(shown.row) + 1)

                Path { path in
                    for c in 1..<max(columns, 1) {
                        let x = cellW * CGFloat(c)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    for r in 1..<max(rows, 1) {
                        let y = cellH * CGFloat(r)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)

                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                // With onTap set, a plain click falls through to the tap; otherwise
                // even a click selects a single cell.
                DragGesture(minimumDistance: onTap == nil ? 0 : 3)
                    .onChanged { value in
                        func cell(_ p: CGPoint) -> (col: Int, row: Int) {
                            (min(max(Int(p.x / cellW), 0), columns - 1),
                             min(max(Int(p.y / cellH), 0), rows - 1))
                        }
                        let start = dragStart ?? cell(value.startLocation)
                        dragStart = start
                        let end = cell(value.location)
                        area = GridArea(
                            col: min(start.col, end.col),
                            row: min(start.row, end.row),
                            colSpan: abs(start.col - end.col) + 1,
                            rowSpan: abs(start.row - end.row) + 1
                        )
                    }
                    .onEnded { _ in dragStart = nil }
                    .exclusively(before: TapGesture().onEnded { onTap?() })
            )
        }
    }
}

private struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Press keys…" : (hotKey?.displayString ?? "Record Shortcut"))
                    .frame(minWidth: 110)
            }
            if hotKey != nil && !recording {
                Button { hotKey = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear shortcut")
            }
        }
        .onDisappear { if recording { stop() } }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc cancels
                stop()
                return nil
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.subtracting(.shift).isEmpty else {
                NSSound.beep() // require ⌘, ⌥ or ⌃ so plain typing isn't hijacked
                return nil
            }
            hotKey = HotKey(keyCode: UInt32(event.keyCode), modifiers: mods.rawValue, key: HotKey.keyName(for: event))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKeyManager.shared.resume()
    }
}
