import AppKit
import Testing

@testable import Mancia

struct PointerPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let visible = CGRect(x: 0, y: 60, width: 1440, height: 815)

    @Test("Invocation pointer takes precedence over selected text")
    func pointerOverridesSelection() {
        let pointer = CGPoint(x: 850, y: 650)
        let result = RibbonPlacement.resolve(height: 60, in: .init(
            screenFrame: screen, visibleFrame: visible,
            selectionRect: CGRect(x: 100, y: 300, width: 300, height: 20),
            pointerLocation: pointer))
        #expect(result.anchor == .belowPointer)
        #expect(result.frame.midX == pointer.x)
        #expect(result.frame.maxY == pointer.y - RibbonPlacement.pointerClearance)
    }

    @Test("Pointer near the bottom opens the ribbon above it")
    func pointerNearBottom() {
        let pointer = CGPoint(x: 700, y: 90)
        let result = RibbonPlacement.resolve(height: 60, in: .init(
            screenFrame: screen, visibleFrame: visible, pointerLocation: pointer))
        #expect(result.anchor == .abovePointer)
        #expect(result.frame.minY == pointer.y + RibbonPlacement.pointerClearance)
    }

    @Test("Resizing keeps the captured pointer edge and center")
    func pointerStaysAnchoredDuringResize() {
        var context = RibbonPlacement.Context(
            screenFrame: screen, visibleFrame: visible,
            pointerLocation: CGPoint(x: 800, y: 700),
            preferredWidth: RibbonPlacement.standardWidth)
        let initial = RibbonPlacement.resolve(height: 60, in: context)
        context.establishedAnchor = initial.anchor
        context.preferredWidth = RibbonPlacement.expandedWidth
        let expanded = RibbonPlacement.resolve(height: 220, in: context)
        #expect(expanded.anchor == initial.anchor)
        #expect(expanded.frame.midX == initial.frame.midX)
        #expect(expanded.frame.maxY == initial.frame.maxY)
    }

    @Test("Pointer placement supports an offset display and clamps to its edges")
    func pointerOnAnotherDisplay() {
        let secondary = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let secondaryVisible = CGRect(x: -1440, y: 60, width: 1440, height: 815)
        let result = RibbonPlacement.resolve(height: 60, in: .init(
            screenFrame: secondary, visibleFrame: secondaryVisible,
            pointerLocation: CGPoint(x: -1430, y: 600)))
        #expect(result.anchor == .belowPointer)
        #expect(secondary.contains(result.frame))
        #expect(result.frame.minX == secondary.minX)
    }
}