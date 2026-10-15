import AppKit
import SwiftUI

@main
struct GridSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(store)
        } label: {
            Image(nsImage: MenuBarIcon.image(dimmed: store.dimEnabled))
                .accessibilityLabel("GridSnap")
        }

        Window("GridSnap Settings", id: "settings") {
            SettingsView().environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyManager.shared.onTrigger = { Store.shared.handleHotKey($0) }
        Store.shared.registerHotKeys()
        Store.shared.applyDim()

        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            WindowMover.lastExternalApp = front
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier != getpid() {
                WindowMover.lastExternalApp = app
            }
        }

        log.notice("Launched; Accessibility trusted: \(AXIsProcessTrusted(), privacy: .public)")
        if !AXIsProcessTrusted() { WindowMover.promptIfNeeded() }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(store.shortcuts) { shortcut in
            Button {
                store.apply(shortcut)
            } label: {
                Label {
                    Text(shortcut.name)
                } icon: {
                    Image(nsImage: GridIcon.image(
                        for: store.area(for: shortcut),
                        columns: store.grid(for: shortcut).columns,
                        rows: store.grid(for: shortcut).rows
                    ))
                }
            }
            .modifier(MenuKeyEquivalent(hotKey: shortcut.hotKey))
        }

        Divider()

        Toggle("Dim Background", isOn: $store.dimEnabled)
            .modifier(MenuKeyEquivalent(hotKey: store.dimHotKey))

        Divider()

        Button("Settings…") {
            NSApp.activate()
            openWindow(id: "settings")
        }
        .keyboardShortcut(",")

        Button("Quit GridSnap") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct MenuKeyEquivalent: ViewModifier {
    let hotKey: HotKey?

    func body(content: Content) -> some View {
        if let hotKey, let key = hotKey.keyEquivalent {
            content.keyboardShortcut(key, modifiers: hotKey.eventModifiers)
        } else {
            content
        }
    }
}

enum MenuBarIcon {
    private static let normal = draw(dimmed: false)
    private static let dimmed = draw(dimmed: true)

    static func image(dimmed: Bool) -> NSImage { dimmed ? Self.dimmed : normal }

    /// A 2 × 2 grid of rounded squares, styled like the `square.grid.2x2` symbol.
    /// The top-right square is filled while Dim Background is on.
    private static func draw(dimmed: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.set()
            let cell: CGFloat = 6.4
            let gap: CGFloat = 2.2
            let origin: CGFloat = (16 - cell * 2 - gap) / 2
            for row in 0..<2 {
                for col in 0..<2 {
                    let rect = NSRect(
                        x: origin + CGFloat(col) * (cell + gap),
                        y: origin + CGFloat(row) * (cell + gap),
                        width: cell, height: cell
                    )
                    if dimmed && row == 0 && col == 1 {
                        NSBezierPath(roundedRect: rect, xRadius: 1.6, yRadius: 1.6).fill()
                    } else {
                        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), xRadius: 1.3, yRadius: 1.3)
                        path.lineWidth = 1.2
                        path.stroke()
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

enum GridIcon {
    /// Small template image of a screen with the target area filled, for the menu.
    static func image(for area: GridArea, columns: Int, rows: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 13), flipped: true) { rect in
            NSColor.black.set()
            let outer = rect.insetBy(dx: 0.75, dy: 0.75)
            let border = NSBezierPath(roundedRect: outer, xRadius: 2.5, yRadius: 2.5)
            border.lineWidth = 1.5
            border.stroke()

            let inner = outer.insetBy(dx: 2, dy: 2)
            let cellW = inner.width / CGFloat(columns)
            let cellH = inner.height / CGFloat(rows)
            let fill = NSRect(
                x: inner.minX + CGFloat(area.col) * cellW,
                y: inner.minY + CGFloat(area.row) * cellH,
                width: CGFloat(area.colSpan) * cellW,
                height: CGFloat(area.rowSpan) * cellH
            )
            NSBezierPath(roundedRect: fill, xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
