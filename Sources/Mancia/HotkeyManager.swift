import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global "Edit Selection" hotkey, default ⌥⌘A.
    @MainActor
    static let editSelection = Self(
        "editSelection",
        default: .init(.a, modifiers: [.option, .command])
    )
}

/// Registers the global hotkey and forwards presses to a handler.
@MainActor
final class HotkeyManager {
    init(onTrigger: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .editSelection) {
            onTrigger()
        }
    }
}
