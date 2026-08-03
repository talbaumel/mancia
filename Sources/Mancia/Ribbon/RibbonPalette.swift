import SwiftUI

/// The ribbon's appearance-adaptive glass register.
///
/// The surfaces remain translucent while their tint, ink, borders, and accent
/// follow the system appearance. The lane uses native Liquid Glass where
/// available and an ultra-thin material on older macOS releases.
enum RibbonPalette {
    static let laneEdge = Palette.dynamic(
        light: 0x1A1611, dark: 0xFFFFFF, lightAlpha: 0.14, darkAlpha: 0.16)
    /// The lifted surface inside the glass lane: menus and Direction field.
    static let control = Palette.dynamic(
        light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.52, darkAlpha: 0.09)
    static let text = Palette.text
    static let caption = Palette.textSecondary
    /// Keyboard-layout correction is a utility action, distinct from the warm
    /// primary-action accent used by Run.
    static let oops = Palette.dynamic(light: 0x236B75, dark: 0x69C5C8)
    static let onOops = Palette.dynamic(light: 0xFFFFFF, dark: 0x102426)
    static let action = Palette.accent
    /// Run's fill while the lane is inert — a request running, or a
    /// confirmation waiting. `action` at 80% over the lane, precomputed.
    ///
    /// Run used to go inert by dimming whole, fill and label together. Dark
    /// ink on a bright fill does not survive that: both ends walk toward the
    /// lane and the label's contrast collapses from 6.34:1 to 2.52:1, which is
    /// how the one word on the lane's one accent control became the least
    /// readable thing on it. Softening the fill alone and leaving the label at
    /// full strength keeps 4.54:1, and the comet riding the border is what
    /// says the button is busy.
    static let actionInert = Palette.dynamic(light: 0xA94A37, dark: 0xD35A42)
    static let onAction = Palette.onAccent
    static let applied = Palette.applied
    static let error = Palette.error
}

extension View {
    /// Use the system's Liquid Glass on macOS 26 and preserve the same
    /// translucent hierarchy with native material on supported older systems.
    @ViewBuilder
    func ribbonGlassBackground<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(shape.fill(.ultraThinMaterial))
        }
    }
}
