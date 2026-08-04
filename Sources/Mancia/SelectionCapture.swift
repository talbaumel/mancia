import AppKit
import ApplicationServices

/// A snapshot of the general pasteboard, so we can restore the user's clipboard
/// after borrowing it for copy/paste.
struct PasteboardSnapshot: Codable {
    private struct StoredItem: Codable {
        let type: String
        let data: Data
    }

    private let items: [StoredItem]

    /// Request one interoperable representation per item. Apps frequently
    /// advertise private lazy types whose provider may stop responding; asking
    /// for every advertised type can then block AppKit's main thread forever.
    static let restorableTypes: [NSPasteboard.PasteboardType] = [
        .string, .rtf, .html, .png, .tiff, .fileURL,
    ]

    static func preferredType(in types: [NSPasteboard.PasteboardType])
        -> NSPasteboard.PasteboardType?
    {
        restorableTypes.first(where: types.contains)
    }

    /// Materialize the clipboard outside the app process. Pasteboard values
    /// can be promises owned by another app; a helper keeps an unresponsive
    /// owner from trapping Mancia's main actor in synchronous AppKit IPC.
    @MainActor
    static func capture() async -> PasteboardSnapshot {
        guard let executableURL = Bundle.main.executableURL else {
            return PasteboardSnapshot(items: [])
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["--pasteboard-export"]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return PasteboardSnapshot(items: [])
        }

        let deadline = ContinuousClock.now + .milliseconds(750)
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard !process.isRunning else {
            process.terminate()
            return PasteboardSnapshot(items: [])
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let snapshot = try? JSONDecoder().decode(PasteboardSnapshot.self, from: data)
        else { return PasteboardSnapshot(items: []) }
        return snapshot
    }

    @MainActor
    static func exportCurrent() -> Data? {
        try? JSONEncoder().encode(captureLocally())
    }

    @MainActor
    private static func captureLocally() -> PasteboardSnapshot {
        var stored: [StoredItem] = []
        for item in NSPasteboard.general.pasteboardItems ?? [] {
            guard let type = preferredType(in: item.types),
                  let data = item.data(forType: type) else { continue }
            stored.append(StoredItem(type: type.rawValue, data: data))
        }
        return PasteboardSnapshot(items: stored)
    }

    func restore() {
        let pb = NSPasteboard.general
        pb.clearContents()
        let objects = items.map { stored -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setData(
                stored.data,
                forType: NSPasteboard.PasteboardType(stored.type))
            return item
        }
        if !objects.isEmpty { pb.writeObjects(objects) }
    }
}

/// The outcome of a selection capture.
struct SelectionCaptureResult {
    var text: String?
    var targetApp: NSRunningApplication?
    var snapshot: PasteboardSnapshot
}

enum TargetEditCommand: Equatable, Sendable {
    case selectAll, copy, paste, cut, undo, redo
}

struct TargetKeyStroke: Equatable, Sendable {
    let keyCode: CGKeyCode
    let eventFlagsRawValue: UInt64

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = CGKeyCode(keyCode)
        eventFlagsRawValue = UInt64(modifiers.rawValue)
    }

    var eventFlags: CGEventFlags {
        CGEventFlags(rawValue: eventFlagsRawValue)
    }
}

/// Pasteboard-based selection capture and replacement, driven by synthetic
/// ⌘C / ⌘A / ⌘V / ⌘Z keystrokes. Requires Accessibility permission.
///
/// Keystrokes are posted directly to the target app's process with
/// `CGEvent.postToPid(_:)`, so they are delivered to that app regardless of
/// which window is key — the floating panel can stay visible throughout.
@MainActor
enum SelectionCapture {
    private enum KeyCode {
        static let a: CGKeyCode = 0
        static let x: CGKeyCode = 7
        static let c: CGKeyCode = 8
        static let v: CGKeyCode = 9
        static let z: CGKeyCode = 6
    }

    /// Capture the current selection from the frontmost app via ⌘C.
    static func captureSelection() async -> SelectionCaptureResult {
        let targetApp = NSWorkspace.shared.frontmostApplication
        let snapshot = await PasteboardSnapshot.capture()
        defer { snapshot.restore() }
        let text = await copyCurrentSelection(pid: targetApp?.processIdentifier)
        return SelectionCaptureResult(text: text, targetApp: targetApp, snapshot: snapshot)
    }

    /// Select all in the target app, then capture the whole document via ⌘C.
    static func captureEntireDocument(from result: SelectionCaptureResult) async -> String? {
        guard isTargetAlive(result) else { return nil }
        result.targetApp?.activate()
        try? await Task.sleep(for: .milliseconds(120))
        postCommandKey(KeyCode.a, to: result)
        try? await Task.sleep(for: .milliseconds(60))
        defer { result.snapshot.restore() }
        return await copyCurrentSelection(pid: result.targetApp?.processIdentifier)
    }

    /// Replace the target's selection (or whole document) with `text`, then
    /// restore the user's original pasteboard. Refuses to act on empty text so
    /// an entire-document ⌘A + ⌘V can never blank the user's document.
    static func apply(text: String, to result: SelectionCaptureResult, entireDocument: Bool) async {
        guard !text.isEmpty, isTargetAlive(result) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        result.targetApp?.activate()
        try? await Task.sleep(for: .milliseconds(150))
        if entireDocument {
            postCommandKey(KeyCode.a, to: result)
            try? await Task.sleep(for: .milliseconds(40))
        }
        postCommandKey(KeyCode.v, to: result)
        try? await Task.sleep(for: .seconds(1))
        result.snapshot.restore()
    }

    /// Probe the target app for a live selection mid-session via ⌘C, without
    /// disturbing the session's pasteboard snapshot. Returns nil when nothing
    /// is selected (the pasteboard doesn't change on an empty ⌘C).
    static func captureFreshSelection(from result: SelectionCaptureResult) async -> String? {
        guard isTargetAlive(result) else { return nil }
        result.targetApp?.activate()
        try? await Task.sleep(for: .milliseconds(120))
        let snapshot = await PasteboardSnapshot.capture()
        defer { snapshot.restore() }
        return await copyCurrentSelection(pid: result.targetApp?.processIdentifier)
    }

    /// Undo the last applied edit in the target app via a synthetic ⌘Z.
    /// In NSTextView-based apps this also restores the replaced selection.
    static func undo(in result: SelectionCaptureResult) async {
        guard isTargetAlive(result) else { return }
        result.targetApp?.activate()
        try? await Task.sleep(for: .milliseconds(150))
        postCommandKey(KeyCode.z, to: result)
        try? await Task.sleep(for: .milliseconds(150))
    }

    /// Perform a standard editing command in the target app while the ribbon
    /// remains key. Copy and Cut intentionally update the user's pasteboard.
    static func perform(_ command: TargetEditCommand, in result: SelectionCaptureResult) {
        guard isTargetAlive(result) else { return }
        switch command {
        case .selectAll: postCommandKey(KeyCode.a, to: result)
        case .copy: postCommandKey(KeyCode.c, to: result)
        case .paste: postCommandKey(KeyCode.v, to: result)
        case .cut: postCommandKey(KeyCode.x, to: result)
        case .undo: postCommandKey(KeyCode.z, to: result)
        case .redo: postCommandKey(KeyCode.z, to: result, flags: [.maskCommand, .maskShift])
        }
    }

    static func perform(_ keystroke: TargetKeyStroke, in result: SelectionCaptureResult) {
        guard isTargetAlive(result) else { return }
        postCommandKey(keystroke.keyCode, to: result, flags: keystroke.eventFlags)
    }

    /// The target app is gone (quit/crashed) — posting keystrokes to a dead or
    /// recycled pid could hit the wrong app, so callers should abort.
    private static func isTargetAlive(_ result: SelectionCaptureResult) -> Bool {
        guard let app = result.targetApp else { return true }
        return !app.isTerminated
    }

    /// Screen rectangle (AppKit bottom-left-origin coordinates) of the focused
    /// element's selected text range / caret, via the Accessibility API.
    /// Returns nil when any step fails (caller falls back to the mouse).
    static func selectionScreenRect() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success, let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        let element = focusedValue as! AXUIElement

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        ) == .success, let rangeValue else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsValue
        ) == .success, let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }

        var axRect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &axRect),
              axRect.origin.x.isFinite, axRect.origin.y.isFinite,
              axRect != .zero else { return nil }

        // AX coordinates have a top-left origin on the primary screen; AppKit
        // uses a bottom-left origin.
        return appKitRect(fromAX: axRect)
    }

    /// Whether the focused Accessibility element has selected characters, as
    /// opposed to the zero-length range reported for an insertion caret.
    static func hasTextSelection() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue
        ) == .success, let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return false }

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedValue as! AXUIElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success, let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return false }

        var range = CFRange()
        return AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) && range.length > 0
    }

    /// Convert an Accessibility rectangle — top-left origin, measured down from
    /// the top of the primary screen — into AppKit screen coordinates, which
    /// have a bottom-left origin.
    ///
    /// Factored out so the flip has exactly one definition: `HostWindowProbe`
    /// reads window frames through the same API and needs the same convention.
    static func appKitRect(fromAX axRect: CGRect) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        return CGRect(
            x: axRect.origin.x,
            y: primary.frame.maxY - axRect.origin.y - axRect.height,
            width: axRect.width,
            height: axRect.height
        )
    }

    // MARK: - Internals

    /// Post ⌘C and poll the pasteboard for a change (up to 600 ms).
    private static func copyCurrentSelection(pid: pid_t?) async -> String? {
        let pb = NSPasteboard.general
        let startCount = pb.changeCount
        postCommandKey(KeyCode.c, toPid: pid)
        var elapsed = 0
        while elapsed < 600 {
            try? await Task.sleep(for: .milliseconds(30))
            elapsed += 30
            if pb.changeCount != startCount { break }
        }
        guard pb.changeCount != startCount else { return nil }
        let string = pb.string(forType: .string)
        return (string?.isEmpty == false) ? string : nil
    }

    private static func postCommandKey(
        _ keyCode: CGKeyCode,
        to result: SelectionCaptureResult,
        flags: CGEventFlags = .maskCommand
    ) {
        postCommandKey(keyCode, toPid: result.targetApp?.processIdentifier, flags: flags)
    }

    /// Post a ⌘-keystroke directly to the target process's event queue
    /// (`postToPid`), so delivery does not depend on which window is key and
    /// the floating panel never swallows it. Falls back to the HID event tap
    /// when no target pid is known.
    private static func postCommandKey(_ keyCode: CGKeyCode, toPid pid: pid_t?, flags: CGEventFlags = .maskCommand) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        if let pid {
            down?.postToPid(pid)
            up?.postToPid(pid)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
