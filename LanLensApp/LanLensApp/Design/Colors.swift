import SwiftUI

// MARK: - LanLens Color Palette

/// Centralized color definitions for the LanLens app.
/// All colors are optimized for dark mode UI.
extension Color {
    // MARK: - Background Colors

    /// Primary background color (#1E1E1E)
    static let lanLensBackground = Color(red: 0x1E/255, green: 0x1E/255, blue: 0x1E/255)

    /// Card/surface background color (#2D2D2D)
    static let lanLensCard = Color(red: 0x2D/255, green: 0x2D/255, blue: 0x2D/255)

    // MARK: - Semantic Colors

    /// Primary accent color - Blue (#007AFF)
    static let lanLensAccent = Color(red: 0x00/255, green: 0x7A/255, blue: 0xFF/255)

    /// Success indicator - Green (#30D158)
    static let lanLensSuccess = Color(red: 0x30/255, green: 0xD1/255, blue: 0x58/255)

    /// Warning indicator - Orange (#FF9F0A)
    static let lanLensWarning = Color(red: 0xFF/255, green: 0x9F/255, blue: 0x0A/255)

    /// Danger/error indicator - Red (#FF453A)
    static let lanLensDanger = Color(red: 0xFF/255, green: 0x45/255, blue: 0x3A/255)

    /// Randomized MAC address indicator - Purple (#9B59B6)
    static let lanLensRandomized = Color(red: 0x9B/255, green: 0x59/255, blue: 0xB6/255)

    // MARK: - Brand Colors

    /// Google brand blue for GoogleCast devices (#4285F4)
    static let lanLensGoogleBlue = Color(red: 0x42/255, green: 0x85/255, blue: 0xF4/255)

    // MARK: - Text Colors

    /// Secondary text color - Gray (#8E8E93)
    static let lanLensSecondaryText = Color(red: 0x8E/255, green: 0x8E/255, blue: 0x93/255)
}
