import AppKit
import ApplicationServices
import os

private let dimLog = Logger(subsystem: "com.benwellby.gridsnap", category: "dim")

/// Private but long-stable API (used by most window managers) mapping an
/// Accessibility window to its window-server id.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Dims everything behind the focused window by keeping a click-through black
/// overlay on each screen, ordered directly below that window.
final class Dimmer {
    static let shared = Dimmer()

    private struct Overlay {
        let window: NSWindow
        let displayID: CGDirectDisplayID
        /// The display's bounds in window-server (top-left origin) coordinates.
        var displayBounds: CGRect { CGDisplayBounds(displayID) }
    }

    private struct Target {
        let number: Int
        let bounds: CGRect
        let fullScreen: Bool
    }

    private var enabled = false
    private var opacity: CGFloat = 0.5
    private var overlays: [Overlay] = []
    private var visible = false
    private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var axObserver: AXObserver?
    private var fallbackTimer: Timer?
    private var lastTarget: Int?
    private var pendingHide: DispatchWorkItem?

    func update(enabled: Bool, opacity: Double) {
        self.opacity = CGFloat(opacity)
        if enabled != self.enabled {
            self.enabled = enabled
            enabled ? start() : stop()
        } else if visible {
            overlays.forEach { if $0.window.isVisible { $0.window.alphaValue = self.opacity } }
        }
    }

    // MARK: - Lifecycle

    private func start() {
        buildOverlays()

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.observeFocus(of: app)
            }
            self?.scheduleRefresh()
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.spaceDidChange() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            self?.buildOverlays()
            self?.scheduleRefresh()
        }

        if let front = NSWorkspace.shared.frontmostApplication { observeFocus(of: front) }

        // Catches anything the notifications miss (e.g. Mission Control reordering).
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }

        refresh()
    }

    private func stop() {
        notificationTokens.forEach { $0.0.removeObserver($0.1) }
        notificationTokens.removeAll()
        removeAXObserver()
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        cancelPendingHide()
        hide()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping (Notification) -> Void) {
        notificationTokens.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: block)))
    }

    // MARK: - Overlays

    private func buildOverlays() {
        overlays.forEach { $0.window.orderOut(nil) }
        overlays = NSScreen.screens.compactMap { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return nil }
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = .black
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.level = .normal
            // Deliberately not on all Spaces: each overlay lives on the Space it was
            // ordered in, so it slides away with that Space instead of covering the
            // incoming one. It's re-ordered onto the new Space after each switch.
            window.collectionBehavior = [.moveToActiveSpace, .ignoresCycle, .fullScreenAuxiliary]
            window.alphaValue = visible ? opacity : 0
            window.setFrame(screen.frame, display: false)
            return Overlay(window: window, displayID: displayID)
        }
    }

    private var overlayNumbers: Set<Int> { Set(overlays.map(\.window.windowNumber)) }

    private func show(_ target: Target) {
        visible = true
        for overlay in overlays {
            let window = overlay.window
            // macOS won't keep an overlay behind a full-screen window, and there's
            // nothing else on that display to dim, so leave that display alone.
            if target.fullScreen && overlay.displayBounds.intersects(target.bounds) {
                window.alphaValue = 0
                window.orderOut(nil)
                continue
            }
            window.order(.below, relativeTo: target.number)
            if window.alphaValue != opacity {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    window.animator().alphaValue = opacity
                }
            }
        }
    }

    private func hide() {
        guard visible else { return }
        visible = false
        let current = overlays.map(\.window)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            current.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            if !self.visible { current.forEach { $0.orderOut(nil) } }
        })
    }

    /// Re-stack the overlays after a Space switch. Ordering an overlay below the
    /// focused window also moves it onto the active Space (`moveToActiveSpace`), so
    /// there's no need to take overlays down first. Doing that made displays whose
    /// Space didn't change flash off and on.
    private func spaceDidChange() {
        dimLog.notice("Space changed; frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "-", privacy: .public)")
        scheduleRefresh()
    }

    // MARK: - Tracking the focused window

    /// Window ordering settles a moment after activation, so refresh again shortly after.
    private func scheduleRefresh() {
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.refresh() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.refresh() }
    }

    private func refresh() {
        guard enabled else { return }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
        if let (target, source) = frontWindow() {
            if target.number != lastTarget {
                dimLog.notice("Dim below window \(target.number, privacy: .public) of \(app, privacy: .public) (\(source, privacy: .public)\(target.fullScreen ? ", full screen" : "", privacy: .public))")
                lastTarget = target.number
            }
            cancelPendingHide()
            show(target)
        } else {
            if lastTarget != nil { dimLog.notice("No focused window for \(app, privacy: .public); hiding soon") }
            lastTarget = nil
            scheduleHide()
        }
    }

    /// Hides after a short grace period. During a Space switch macOS briefly reports
    /// the previous app as active while its window is already off screen; hiding
    /// straight away would make the other display's dimming flash off and on.
    private func scheduleHide() {
        guard pendingHide == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            // Re-check in case focus settled while we waited.
            if self.enabled, self.frontWindow() == nil { self.hide() }
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func cancelPendingHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }

    /// The active app's focused window, if it's visible on screen.
    ///
    /// Stacking order alone isn't enough: with multiple displays (each with its own
    /// Spaces), an app's window on another display can sit above the one that just
    /// gained focus on a newly switched-to Space. So ask Accessibility which window
    /// is focused, and only fall back to stacking order if that fails.
    private func frontWindow() -> (Target, String)? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let ours = overlayNumbers

        // The app's visible normal windows, front to back.
        let candidates: [(number: Int, bounds: CGRect)] = list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? Int,
                  !ours.contains(number),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 40, bounds.height > 40 else { return nil }
            return (number, bounds)
        }

        let focused = focusedWindow(pid: pid)
        if let focused, let match = candidates.first(where: { $0.number == focused.number }) {
            return (Target(number: match.number, bounds: match.bounds,
                           fullScreen: focused.fullScreen || fillsDisplay(match.bounds)), "focused")
        }
        guard let first = candidates.first else { return nil }
        return (Target(number: first.number, bounds: first.bounds, fullScreen: fillsDisplay(first.bounds)), "stacking order")
    }

    private func focusedWindow(pid: pid_t) -> (number: Int, fullScreen: Bool)? {
        guard AXIsProcessTrusted() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &id) == .success, id != 0 else { return nil }

        var fullScreenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreenRef)
        return (Int(id), (fullScreenRef as? Bool) == true)
    }

    /// Fallback full-screen check: the window exactly covers a display.
    private func fillsDisplay(_ bounds: CGRect) -> Bool {
        overlays.contains { $0.displayBounds == bounds }
    }

    /// Watches for focus moving between windows of the same app.
    private func observeFocus(of app: NSRunningApplication) {
        removeAXObserver()
        guard AXIsProcessTrusted() else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, _ in Dimmer.shared.scheduleRefresh() }
        guard AXObserverCreate(app.processIdentifier, callback, &observer) == .success, let observer else { return }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                     kAXWindowCreatedNotification, kAXWindowMiniaturizedNotification] {
            AXObserverAddNotification(observer, element, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
    }

    private func removeAXObserver() {
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
        }
        axObserver = nil
    }
}
