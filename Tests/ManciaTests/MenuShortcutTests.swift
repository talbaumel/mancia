import AppKit
import Testing

@testable import Mancia

@MainActor
@Suite("Menu shortcuts")
struct MenuShortcutTests {
    @Test("Command numbers route the opening menu and all nine snippets")
    func commandNumbersRouteVisibleMenu() {
        let model = PanelModel()
        model.reset(hasSelection: true, charCount: 12)
        model.snippets = (1...9).map { TextSnippet(title: "Entry \($0)", value: "Value \($0)") }
        var corrections = 0
        var edits = 0
        var pasted: [TextSnippet] = []
        model.onOops = { corrections += 1 }
        model.onPerform = { _, _ in edits += 1 }
        model.onSnippet = { pasted.append($0) }

        func press(_ digit: Int) {
            let command = PanelKeyCommand.resolve(characters: String(digit), modifiers: .command)
            #expect(command == .activateAction(digit - 1))
            if case .activateAction(let index) = command {
                model.activateNumberedButton(at: index)
            }
        }

        press(1)
        #expect(corrections == 1)
        press(2)
        #expect(model.screen == .snippets)
        for digit in 1...9 { press(digit) }
        #expect(pasted == model.snippets)
        model.showMenu()
        press(3)
        #expect(model.screen == .smartEdit)
        #expect(edits == 0)
        press(1)
        #expect(edits == 1)
    }

    @Test("Bare numbers remain available and unrelated modifier combinations stay inert")
    func numberModifiers() {
        for digit in 1...5 {
            #expect(PanelKeyCommand.resolve(characters: String(digit), modifiers: [])
                == .activateAction(digit - 1))
        }
        for modifiers: NSEvent.ModifierFlags in [.option, .control, [.command, .shift]] {
            #expect(PanelKeyCommand.resolve(characters: "1", modifiers: modifiers) == nil)
        }
        #expect(PanelKeyCommand.resolve(characters: "0", modifiers: .command) == nil)
    }
}