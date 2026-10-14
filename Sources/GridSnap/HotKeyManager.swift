import Carbon.HIToolbox
import Foundation

/// Registers system-wide hotkeys via the Carbon hotkey API (still the supported way
/// to get global shortcuts without input-monitoring permission).
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onTrigger: ((UUID) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: UUID] = [:]
    private var suspended = false
    private var handlerInstalled = false
    private let signature = OSType(0x4752_4944) // "GRID"

    /// Registers the hotkeys and returns the ids of any that failed.
    @discardableResult
    func register(_ bindings: [(id: UUID, hotKey: HotKey)]) -> Set<UUID> {
        unregisterAll()
        guard !suspended else { return [] }
        installHandler()

        var failed: Set<UUID> = []
        for (index, binding) in bindings.enumerated() {
            let hotKey = binding.hotKey
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                hotKey.keyCode, hotKey.carbonModifiers,
                EventHotKeyID(signature: signature, id: id),
                GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = binding.id
            } else {
                failed.insert(binding.id)
            }
        }
        return failed
    }

    /// Pauses all hotkeys, e.g. while recording a new combo so existing ones don't fire.
    func suspend() {
        suspended = true
        unregisterAll()
    }

    func resume() {
        suspended = false
        Store.shared.registerHotKeys()
    }

    private func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        if let shortcutID = actions[id] { onTrigger?(shortcutID) }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            HotKeyManager.shared.fire(hotKeyID.id)
            return noErr
        }, 1, &spec, nil, nil)
    }
}
