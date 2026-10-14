import AppKit
import ApplicationServices
import os

let log = Logger(subsystem: "local.gridsnap.GridSnap", category: "move")

enum WindowMover {
    /// The last non-GridSnap app to be active, used when GridSnap itself is frontmost
    /// (e.g. the Settings window is open).
    static var lastExternalApp: NSRunningApplication?

    private static var hasPrompted = false

    /// Shows the system Accessibility prompt at most once per launch.
    static func promptIfNeeded() {
        guard !hasPrompted else { return }
        hasPrompted = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func move(to area: GridArea, columns: Int, rows: Int) {
        guard AXIsProcessTrusted() else {
            log.error("Not trusted for Accessibility")
            NSSound.beep()
            promptIfNeeded()
            return
        }
        guard let app = targetApp() else {
            log.error("No target app")
            return
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = focusedWindow(of: axApp), let current = frame(of: window) else {
            log.error("No focused window for \(app.bundleIdentifier ?? "?", privacy: .public)")
            NSSound.beep()
            return
        }

        let screen = screen(containing: current)
        let target = targetFrame(for: area, columns: columns, rows: rows, in: screen.visibleFrame)

        // Some apps (notably Chromium/Electron) animate or fight resizes while
        // AXEnhancedUserInterface is on, so switch it off for the duration.
        let enhancedUI = "AXEnhancedUserInterface" as CFString
        var enhancedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, enhancedUI, &enhancedRef)
        let wasEnhanced = (enhancedRef as? Bool) == true
        if wasEnhanced { AXUIElementSetAttributeValue(axApp, enhancedUI, kCFBooleanFalse) }

        // Size → position → size: the first resize lets the window fit on the
        // destination screen, the second corrects any clamping from the move.
        setSize(window, target.size)
        setPosition(window, target.origin)
        setSize(window, target.size)

        if wasEnhanced { AXUIElementSetAttributeValue(axApp, enhancedUI, kCFBooleanTrue) }
    }

    private static func targetApp() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            return front
        }
        return lastExternalApp
    }

    private static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    private static func setSize(_ window: AXUIElement, _ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }

    private static func setPosition(_ window: AXUIElement, _ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    // Accessibility uses a top-left origin anchored to the primary screen;
    // AppKit uses bottom-left. These helpers convert between the two.
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func screen(containing axFrame: CGRect) -> NSScreen {
        let center = CGPoint(x: axFrame.midX, y: primaryHeight - axFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Returns the target frame in Accessibility (top-left origin) coordinates.
    private static func targetFrame(for area: GridArea, columns: Int, rows: Int, in visible: CGRect) -> CGRect {
        let cellW = visible.width / CGFloat(columns)
        let cellH = visible.height / CGFloat(rows)

        // Round edges rather than sizes so adjacent windows meet without gaps.
        let left = (visible.minX + CGFloat(area.col) * cellW).rounded()
        let right = (visible.minX + CGFloat(area.col + area.colSpan) * cellW).rounded()
        let top = (visible.maxY - CGFloat(area.row) * cellH).rounded()
        let bottom = (visible.maxY - CGFloat(area.row + area.rowSpan) * cellH).rounded()

        return CGRect(x: left, y: primaryHeight - top, width: right - left, height: top - bottom)
    }
}
