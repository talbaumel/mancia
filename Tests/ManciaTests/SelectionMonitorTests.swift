import AppKit
import Testing
@testable import Mancia

@MainActor
@Suite("Automatic text selection")
struct SelectionMonitorTests {
    @Test("Automatic appearance defaults off and persists both toggle values")
    func settingPersists() throws {
        let suite = "mancia-auto-selection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, modelCatalog: { [] })
        #expect(!settings.showOnTextSelection)
        settings.showOnTextSelection = true
        #expect(AppSettings(defaults: defaults, modelCatalog: { [] }).showOnTextSelection)
        settings.showOnTextSelection = false
        #expect(!AppSettings(defaults: defaults, modelCatalog: { [] }).showOnTextSelection)
    }

    @Test("Only selection navigation and Command-A finish keyboard selections")
    func keyboardGestures() {
        for key: UInt16 in [123, 124, 125, 126, 115, 119, 116, 121] {
            #expect(SelectionMonitor.canFinishSelection(keyCode: key, modifiers: .shift))
            #expect(SelectionMonitor.canFinishSelection(
                keyCode: key, modifiers: [.shift, .option]))
            #expect(!SelectionMonitor.canFinishSelection(keyCode: key, modifiers: []))
        }
        #expect(SelectionMonitor.canFinishSelection(keyCode: 0, modifiers: .command))
        #expect(SelectionMonitor.canFinishSelection(keyCode: 0, modifiers: [.command, .capsLock]))
        for modifiers: NSEvent.ModifierFlags in [.shift, .control, [.command, .shift], [.command, .option]] {
            #expect(!SelectionMonitor.canFinishSelection(keyCode: 0, modifiers: modifiers))
        }
        for key: UInt16 in [6, 56, 60] {
            #expect(!SelectionMonitor.canFinishSelection(keyCode: key, modifiers: .shift))
        }
    }

    @Test("The same selection does not reopen after dismissal; new ranges do")
    func repeatedSelectionIsDeduplicated() {
        var selection: SelectionCaptureResult? = captured()
        var opened = 0
        let monitor = SelectionMonitor(
            isEnabled: { true }, canOpen: { true },
            readSelection: { selection }, ownPid: -1,
            onSelection: { _ in opened += 1 })
        monitor.checkSelection(shouldOpen: true)
        monitor.checkSelection(shouldOpen: true)
        #expect(opened == 1)
        selection = captured(location: 10)
        monitor.checkSelection(shouldOpen: true)
        #expect(opened == 2)
        selection = nil
        monitor.checkSelection(shouldOpen: true)
        selection = captured(location: 10)
        monitor.checkSelection(shouldOpen: true)
        #expect(opened == 3)
    }

    @Test("Selection identity includes field, text, and window")
    func changedEvidenceOpens() {
        let first = AXUIElementCreateApplication(501)
        let second = AXUIElementCreateApplication(502)
        var selection: SelectionCaptureResult? = captured(element: first, window: first)
        var opened = 0
        let monitor = SelectionMonitor(
            isEnabled: { true }, canOpen: { true },
            readSelection: { selection }, ownPid: -1,
            onSelection: { _ in opened += 1 })
        monitor.checkSelection(shouldOpen: true)
        selection = captured(element: second, window: first)
        monitor.checkSelection(shouldOpen: true)
        selection = captured(text: "changed", element: second, window: first)
        monitor.checkSelection(shouldOpen: true)
        selection = captured(text: "changed", element: second, window: second)
        monitor.checkSelection(shouldOpen: true)
        #expect(opened == 4)
    }

    @Test("Disabled activation and active sessions cannot open or refocus the ribbon")
    func activationGuards() {
        var enabled = false
        var canOpen = true
        var reads = 0
        var opened = 0
        let monitor = SelectionMonitor(
            isEnabled: { enabled }, canOpen: { canOpen },
            readSelection: { reads += 1; return captured() }, ownPid: -1,
            onSelection: { _ in opened += 1 })
        monitor.checkSelection(shouldOpen: true)
        #expect(reads == 0)
        #expect(opened == 0)
        enabled = true
        canOpen = false
        monitor.checkSelection(shouldOpen: true)
        #expect(opened == 0)
        canOpen = true
        monitor.checkSelection(shouldOpen: true)
        #expect(opened == 0)
        enabled = false
        monitor.checkSelection(shouldOpen: true)
        enabled = true
        monitor.checkSelection(shouldOpen: true)
        #expect(opened == 1)
    }

    @Test("Caret, missing range, failed capture, and own-app selections never open")
    func invalidOrOwnSelectionsAreIgnored() {
        var selection: SelectionCaptureResult? = captured(length: 0)
        var opened = 0
        let monitor = SelectionMonitor(
            isEnabled: { true }, canOpen: { true },
            readSelection: { selection }, ownPid: -1,
            onSelection: { _ in opened += 1 })
        for invalid in [
            captured(length: 0), captured(length: -1), captured(location: -1), captured(text: ""),
            captured(hasRange: false),
            captured(element: nil),
            SelectionCaptureResult(outcome: .uncertain(.copyTimedOut), target: nil),
            SelectionCaptureResult(outcome: .noSelection, target: captured().target),
        ] {
            selection = invalid
            monitor.checkSelection(shouldOpen: true)
        }
        #expect(opened == 0)
        let ownMonitor = SelectionMonitor(
            isEnabled: { true }, canOpen: { true },
            readSelection: { captured() },
            onSelection: { _ in opened += 1 })
        ownMonitor.checkSelection(shouldOpen: true)
        #expect(opened == 0)
    }

    @Test("Ordinary typing only updates the remembered selection")
    func nonSelectionInputDoesNotOpen() {
        var opened = 0
        let monitor = SelectionMonitor(
            isEnabled: { true }, canOpen: { true },
            readSelection: { captured() }, ownPid: -1,
            onSelection: { _ in opened += 1 })
        monitor.checkSelection(shouldOpen: false)
        monitor.checkSelection(shouldOpen: true)
        #expect(opened == 0)
    }

    @Test("Mouse selection checks debounce until the latest completed gesture")
    func mouseDebounce() async throws {
        var opened = 0
        let monitor = SelectionMonitor(
            isEnabled: { true }, canOpen: { true },
            readSelection: { captured() }, ownPid: -1,
            onSelection: { _ in opened += 1 })
        defer { monitor.stop() }
        monitor.handleInput(type: .leftMouseUp)
        try await Task.sleep(for: .milliseconds(100))
        monitor.handleInput(type: .leftMouseUp)
        try await Task.sleep(for: .milliseconds(100))
        #expect(opened == 0)
        try await Task.sleep(for: .milliseconds(150))
        #expect(opened == 1)
    }

    @Test("Releasing the selection modifier before key-up still opens", arguments: [UInt16(123), 0])
    func keyboardReleaseOrder(key: UInt16) async throws {
        var opened = 0
        let monitor = SelectionMonitor(
            isEnabled: { true }, canOpen: { true },
            readSelection: { captured() }, ownPid: -1,
            onSelection: { _ in opened += 1 })
        defer { monitor.stop() }
        monitor.handleInput(
            type: .keyDown, keyCode: key, modifiers: key == 0 ? .command : .shift)
        monitor.handleInput(type: .keyUp, keyCode: key)
        try await Task.sleep(for: .milliseconds(300))
        #expect(opened == 1)
    }

    @Test("Delayed Electron selection evidence is retried beyond its two-second debounce")
    func delayedAccessibilitySelection() async throws {
        let started = ContinuousClock.now
        var reads = 0
        var opened = 0
        let monitor = SelectionMonitor(
            isEnabled: { true }, canOpen: { true },
            readSelection: {
                reads += 1
                return started.duration(to: .now) >= .milliseconds(2300) ? captured() : nil
            }, ownPid: -1,
            onSelection: { _ in opened += 1 })
        defer { monitor.stop() }
        monitor.handleInput(type: .keyDown, keyCode: 0, modifiers: .command)
        monitor.handleInput(type: .keyUp, keyCode: 0, modifiers: .command)
        try await Task.sleep(for: .milliseconds(2100))
        #expect(opened == 0)
        try await Task.sleep(for: .milliseconds(900))
        #expect(opened == 1)
        let completedReads = reads
        try await Task.sleep(for: .milliseconds(300))
        #expect(reads == completedReads)
    }

    @Test("Unreadable selections stop retrying after a bounded wait")
    func accessibilityRetriesAreBounded() async throws {
        var reads = 0
        let monitor = SelectionMonitor(
            isEnabled: { true }, canOpen: { true },
            readSelection: { reads += 1; return nil },
            onSelection: { _ in Issue.record("An unreadable selection must not open") })
        defer { monitor.stop() }
        monitor.handleInput(type: .leftMouseUp)
        try await Task.sleep(for: .milliseconds(3300))
        #expect(reads == 12)
        try await Task.sleep(for: .milliseconds(300))
        #expect(reads == 12)
    }

    @Test("A later input gesture cancels delayed Accessibility retries")
    func delayedSelectionCanBeCancelled() async throws {
        var selection: SelectionCaptureResult?
        var reads = 0
        var opened = 0
        let monitor = SelectionMonitor(
            isEnabled: { true }, canOpen: { true },
            readSelection: { reads += 1; return selection }, ownPid: -1,
            onSelection: { _ in opened += 1 })
        defer { monitor.stop() }
        monitor.handleInput(type: .leftMouseUp)
        try await Task.sleep(for: .milliseconds(250))
        #expect(reads == 1)
        monitor.handleInput(type: .keyDown, keyCode: 8)
        selection = captured()
        try await Task.sleep(for: .milliseconds(500))
        #expect(reads == 1)
        #expect(opened == 0)
    }

    @Test("Assistive access preparation is opt-in, retried, and stopped with monitoring")
    func accessibilityPreparation() async throws {
        var enabled = false
        var attempts = 0
        let monitor = SelectionMonitor(
            isEnabled: { enabled }, canOpen: { true },
            prepareAccessibility: { attempts += 1; return attempts >= 2 },
            readSelection: { nil },
            onSelection: { _ in Issue.record("Preparation must not open a ribbon") })
        defer { monitor.stop() }
        monitor.handleInput(type: .leftMouseDown)
        #expect(attempts == 0)
        enabled = true
        monitor.handleInput(type: .leftMouseDown)
        #expect(attempts == 1)
        try await Task.sleep(for: .milliseconds(350))
        #expect(attempts == 2)
        attempts = 0
        monitor.handleInput(type: .leftMouseDown)
        monitor.stop()
        try await Task.sleep(for: .milliseconds(350))
        #expect(attempts == 1)
    }

    @Test("Disabling, beginning another gesture, or stopping cancels pending appearance")
    func pendingAppearanceCanBeCancelled() async throws {
        var enabled = true
        var opened = 0
        let monitor = SelectionMonitor(
            isEnabled: { enabled }, canOpen: { true },
            readSelection: { captured() }, ownPid: -1,
            onSelection: { _ in opened += 1 })
        defer { monitor.stop() }
        monitor.handleInput(type: .leftMouseUp)
        enabled = false
        try await Task.sleep(for: .milliseconds(250))
        #expect(opened == 0)
        enabled = true
        monitor.handleInput(type: .leftMouseUp)
        monitor.handleInput(type: .leftMouseDown)
        try await Task.sleep(for: .milliseconds(250))
        #expect(opened == 0)
        monitor.handleInput(type: .leftMouseUp)
        monitor.stop()
        try await Task.sleep(for: .milliseconds(250))
        #expect(opened == 0)
    }

    private func captured(
        text: String = "selected",
        location: Int = 2,
        length: Int = 8,
        hasRange: Bool = true,
        element: AXUIElement? = AXUIElementCreateApplication(501),
        window: AXUIElement? = nil
    ) -> SelectionCaptureResult {
        let app = NSRunningApplication.current
        return .init(
            outcome: .selected(text),
            target: SelectionTargetEvidence(
                pid: ProcessInfo.processInfo.processIdentifier, capturedBaseline: text,
                capturedFieldValue: "a selected field", scope: .selection,
                targetApp: app, window: window, focusedElement: element,
                selectedRange: hasRange ? CFRange(location: location, length: length) : nil))
    }
}
