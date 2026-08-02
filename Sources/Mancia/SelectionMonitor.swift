import AppKit

/// Watches global input for gestures that can finish a text selection, then
/// asks Accessibility whether the focused element really has a nonempty range.
/// The input events are only hints: the AX check prevents ordinary clicks and
/// Shift-modified typing from opening the ribbon.
@MainActor
final class SelectionMonitor {
    private let isEnabled: @MainActor () -> Bool
    private let onSelection: @MainActor () -> Void
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var pendingCheck: Task<Void, Never>?

    init(
        isEnabled: @escaping @MainActor () -> Bool,
        onSelection: @escaping @MainActor () -> Void
    ) {
        self.isEnabled = isEnabled
        self.onSelection = onSelection
    }

    func start() {
        guard mouseMonitor == nil, keyMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in self?.scheduleCheck() }
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            Task { @MainActor in
                guard Self.canFinishSelection(keyCode: keyCode, modifiers: modifiers) else { return }
                self?.scheduleCheck()
            }
        }
    }

    /// Shift can extend a selection with arrows or navigation keys; checking
    /// other Shift-modified keys is harmless because AX remains authoritative.
    /// Command-A is the other common keyboard-only selection gesture.
    static func canFinishSelection(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        modifiers.contains(.shift)
            || keyCode == 56
            || keyCode == 60
            || (keyCode == 0 && modifiers.contains(.command))
    }

    private func scheduleCheck() {
        guard isEnabled() else { return }
        pendingCheck?.cancel()
        pendingCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            guard isEnabled(),
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    != Bundle.main.bundleIdentifier,
                  SelectionCapture.hasTextSelection() else { return }
            onSelection()
        }
    }
}