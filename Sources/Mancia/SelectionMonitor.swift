import AppKit

/// Input events are hints; only a readable AX selection can open the ribbon.
@MainActor
final class SelectionMonitor {
    private struct SelectionID: Equatable {
        let pid: pid_t
        let window: UInt64?
        let element: UInt64
        let range: EditSession.TextRange
        let text: String

        init?(_ selection: SelectionCaptureResult, ownPid: pid_t) {
            guard case .selected(let text) = selection.outcome, !text.isEmpty,
                  let target = selection.target, target.pid != ownPid,
                  target.scope == .selection, target.capturedBaseline == text,
                  let element = target.elementIdentifier,
                  let range = target.selectedRange,
                  range.location >= 0, range.length > 0 else { return nil }
            self.pid = target.pid
            self.window = target.window.map { UInt64(CFHash($0)) }
            self.element = element
            self.range = .init(location: range.location, length: range.length)
            self.text = text
        }
    }

    private let isEnabled: @MainActor () -> Bool
    private let canOpen: @MainActor () -> Bool
    private let prepareAccessibility: @MainActor () -> Bool
    private let readSelection: @MainActor () -> SelectionCaptureResult?
    private let onSelection: @MainActor (SelectionCaptureResult) -> Void
    private let ownPid: pid_t
    private var eventMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var preparationTask: Task<Void, Never>?
    private var pendingCheck: Task<Void, Never>?
    private var selectionKey: UInt16?
    private var mouseIsDown = false
    private var lastSelection: SelectionID?

    init(
        isEnabled: @escaping @MainActor () -> Bool,
        canOpen: @escaping @MainActor () -> Bool,
        prepareAccessibility: @escaping @MainActor () -> Bool = { true },
        readSelection: @escaping @MainActor () -> SelectionCaptureResult? = {
            SelectionCapture.accessibilitySelection()
        },
        ownPid: pid_t = ProcessInfo.processInfo.processIdentifier,
        onSelection: @escaping @MainActor (SelectionCaptureResult) -> Void
    ) {
        self.isEnabled = isEnabled
        self.canOpen = canOpen
        self.prepareAccessibility = prepareAccessibility
        self.readSelection = readSelection
        self.ownPid = ownPid
        self.onSelection = onSelection
    }

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .keyDown, .keyUp]
        ) { [weak self] event in
            let type = event.type
            let keyCode = type == .keyDown || type == .keyUp ? event.keyCode : 0
            let modifiers = event.modifierFlags
            Task { @MainActor in
                self?.handleInput(type: type, keyCode: keyCode, modifiers: modifiers)
            }
        }
        if eventMonitor == nil {
            NSLog("Mancia: automatic selection monitoring could not start.")
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.beginPreparation() }
        }
        beginPreparation()
    }

    func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        preparationTask?.cancel()
        preparationTask = nil
        pendingCheck?.cancel()
        pendingCheck = nil
        selectionKey = nil
        mouseIsDown = false
        lastSelection = nil
    }

    static func canFinishSelection(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers.contains(.shift),
           [123, 124, 125, 126, 115, 119, 116, 121].contains(keyCode) {
            return true
        }
        return keyCode == 0 && modifiers.contains(.command)
            && modifiers.intersection([.shift, .option, .control]).isEmpty
    }

    func handleInput(
        type: NSEvent.EventType,
        keyCode: UInt16 = 0,
        modifiers: NSEvent.ModifierFlags = []
    ) {
        pendingCheck?.cancel()
        pendingCheck = nil
        guard isEnabled() else {
            preparationTask?.cancel()
            preparationTask = nil
            selectionKey = nil
            lastSelection = nil
            return
        }
        switch type {
        case .leftMouseDown:
            mouseIsDown = true
            selectionKey = nil
            beginPreparation()
        case .keyDown:
            beginPreparation()
            selectionKey = Self.canFinishSelection(keyCode: keyCode, modifiers: modifiers)
                ? keyCode : nil
        case .leftMouseUp:
            mouseIsDown = false
            scheduleCheck(shouldOpen: true)
        case .keyUp:
            let shouldOpen = selectionKey == keyCode
                || Self.canFinishSelection(keyCode: keyCode, modifiers: modifiers)
            selectionKey = nil
            scheduleCheck(shouldOpen: shouldOpen)
        default:
            break
        }
    }

    @discardableResult
    func checkSelection(shouldOpen: Bool) -> Bool {
        guard isEnabled() else {
            lastSelection = nil
            return true
        }
        let selection = readSelection()
        let identity = selection.flatMap { SelectionID($0, ownPid: ownPid) }
        let changed = identity != lastSelection
        lastSelection = identity
        guard shouldOpen, changed, identity != nil, canOpen(), let selection else {
            return identity != nil || !canOpen()
        }
        onSelection(selection)
        return true
    }

    private func beginPreparation() {
        preparationTask?.cancel()
        preparationTask = nil
        guard isEnabled(), canOpen(), !prepareAccessibility() else { return }
        preparationTask = Task { [weak self] in
            do {
                for _ in 0..<12 {
                    try await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self, isEnabled(), canOpen() else { return }
                    if prepareAccessibility() { return }
                }
            } catch is CancellationError {
                return
            } catch {
                NSLog("Mancia: assistive access preparation failed: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleCheck(shouldOpen: Bool) {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(180))
        pendingCheck = Task { [weak self] in
            do {
                try await Task.sleep(until: deadline, clock: .continuous)
                for attempt in 0..<12 {
                    guard !Task.isCancelled, let self, !mouseIsDown else { return }
                    if checkSelection(shouldOpen: shouldOpen) || !shouldOpen { return }
                    guard attempt < 11 else { return }
                    try await Task.sleep(for: .milliseconds(250))
                }
            } catch is CancellationError {
                return
            } catch {
                NSLog("Mancia: selection check failed: \(error.localizedDescription)")
                return
            }
        }
    }
}
