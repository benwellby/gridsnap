import AppKit
import ApplicationServices
import os

let log = Logger(subsystem: "com.benwellby.gridsnap", category: "move")

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
        // Don't hang on an unresponsive app.
        AXUIElementSetMessagingTimeout(axApp, 1)
        let appName = app.bundleIdentifier ?? app.localizedName ?? "?"

        guard let window = focusedWindow(of: axApp, appName: appName) else {
            NSSound.beep()
            return
        }
        guard let current = frame(of: window) else {
            log.error("Couldn't read the window frame for \(appName, privacy: .public)")
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

        // Some apps limit window sizes (e.g. a minimum size, or Preview keeping a
        // document's proportions). Log when the result differs from what was asked.
        if let result = frame(of: window),
           abs(result.minX - target.minX) > 2 || abs(result.minY - target.minY) > 2 ||
           abs(result.width - target.width) > 2 || abs(result.height - target.height) > 2 {
            log.notice("\(appName, privacy: .public) constrained the window: asked for \(String(describing: target), privacy: .public), got \(String(describing: result), privacy: .public)")
        }
    }

    private static func targetApp() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            return front
        }
        return lastExternalApp
    }

    /// The window to move: the focused window, else the main window, else the first window.
    ///
    /// Electron and Chromium apps (Figma, Todoist, Slack…) only build their
    /// accessibility tree once asked via `AXManualAccessibility`, so if nothing is
    /// found, ask and retry briefly. The flag sticks, so this only costs time once.
    private static func focusedWindow(of app: AXUIElement, appName: String) -> AXUIElement? {
        if let window = findWindow(in: app) { return window }

        let manual = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        for _ in 0..<5 {
            usleep(40_000)
            if let window = findWindow(in: app) {
                log.notice("Found window for \(appName, privacy: .public) after enabling AXManualAccessibility")
                return window
            }
        }

        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        log.error("No window found for \(appName, privacy: .public) (focused window error \(error.rawValue, privacy: .public), AXManualAccessibility \(manual.rawValue, privacy: .public))")
        return nil
    }

    private static func findWindow(in app: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
           let first = (windows as? [AXUIElement])?.first {
            return first
        }
        return nil
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
