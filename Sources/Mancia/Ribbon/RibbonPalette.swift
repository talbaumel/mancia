import SwiftUI

/// Translucent chrome over the system glass material, with an opaque fallback.
enum RibbonPalette {
    static let laneTint = Palette.dynamic(
        light: 0xF2F7FF, dark: 0xDCEAFF, lightAlpha: 0.12, darkAlpha: 0.04)
    static let laneEdge = Palette.dynamic(
        light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.65, darkAlpha: 0.20)
    /// Buttons sit on their own step above the lane so each one reads as a
    /// distinct target rather than as a label floating on the strip.
    static let controlTint = Palette.dynamic(
        light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.32, darkAlpha: 0.07)
    static let controlHoverTint = Palette.dynamic(
        light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.58, darkAlpha: 0.16)
    static let controlEdge = Palette.dynamic(
        light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.72, darkAlpha: 0.22)
    /// A denser surface keeps the instruction editor readable.
    static let directionTint = Palette.raised.opacity(0.65)
    /// Used when Reduce Transparency is on, where translucency is not an option
    /// and the lane still has to be legible over anything behind it.
    static let laneOpaque = Palette.surface
    static let text = Palette.text
    static let caption = Palette.textSecondary
    static let symbol = Palette.textSecondary
    static let action = Palette.accent
    static let customRun = Palette.secondaryAction
    static let onCustomRun = Palette.onSecondaryAction
    /// Cool light is reserved for work in progress. It separates state from
    /// action: orange still means "run this", while blue means "it is running".
    static let processing = Color(hex: 0x49B8FF)
    static let onAction = Palette.onAccent
    static let applied = Palette.applied
    static let error = Palette.error
}
