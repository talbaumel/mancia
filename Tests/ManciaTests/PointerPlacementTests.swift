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

    @Test("Dragged placement retains its top-left corner while content changes")
    func draggedPlacementResizesFromUserPosition() {
        let corner = CGPoint(x: 300, y: 700)
        for size in [CGSize(width: 360, height: 48), CGSize(width: 780, height: 220)] {
            let frame = RibbonPlacement.draggedFrame(
                size: size, topLeft: corner, visibleFrame: visible)
            #expect(frame.minX == corner.x)
            #expect(frame.maxY == corner.y)
            #expect(frame.size == size)
        }
    }

    @Test("Dragged placement stays reachable at every display edge")
    func draggedPlacementClampsToDisplay() {
        for corner in [
            CGPoint(x: -100, y: 1000), CGPoint(x: 1400, y: 80),
            CGPoint(x: 5000, y: -500),
        ] {
            let frame = RibbonPlacement.draggedFrame(
                size: CGSize(width: 780, height: 220), topLeft: corner, visibleFrame: visible)
            #expect(visible.contains(frame))
        }
    }

    @Test("Dragged placement supports negative display coordinates and removed displays")
    func draggedPlacementAcrossDisplays() {
        let secondary = visible.offsetBy(dx: -1440, dy: -900)
        let corner = CGPoint(x: -1200, y: -200)
        let size = CGSize(width: 600, height: 200)
        let frame = RibbonPlacement.draggedFrame(
            size: size, topLeft: corner, visibleFrame: secondary)
        #expect(frame.minX == corner.x)
        #expect(frame.maxY == corner.y)
        #expect(secondary.contains(frame))

        let recovered = RibbonPlacement.draggedFrame(
            size: size, topLeft: corner, visibleFrame: visible)
        #expect(visible.contains(recovered))
    }

    @Test("Oversized dragged content keeps its handle on screen")
    func oversizedDraggedPlacement() {
        let frame = RibbonPlacement.draggedFrame(
            size: CGSize(width: 1800, height: 1200),
            topLeft: CGPoint(x: 500, y: 700), visibleFrame: visible)
        #expect(frame.width == visible.width)
        #expect(frame.minX == visible.minX)
        #expect(frame.maxY == visible.maxY)
    }
}