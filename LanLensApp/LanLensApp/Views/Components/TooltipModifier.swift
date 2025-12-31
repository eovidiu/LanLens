import SwiftUI

// MARK: - Tooltip View

/// A tooltip view that displays contextual help text above an element.
/// Styled with a dark semi-transparent background and white text.
struct TooltipView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .fixedSize()
    }
}

// MARK: - Tooltip Modifier

/// A view modifier that adds hover-triggered tooltip functionality to any view.
/// 
/// The tooltip appears above the element after a 500ms delay and hides
/// 200ms after the mouse leaves. Animations use 150ms ease-in-out timing.
///
/// Usage:
/// ```swift
/// Image(systemName: "shield.fill")
///     .tooltip("Security status indicator")
/// ```
struct TooltipModifier: ViewModifier {
    let text: String
    
    /// Show delay in seconds
    private let showDelay: TimeInterval = 0.5
    /// Hide delay in seconds
    private let hideDelay: TimeInterval = 0.2
    /// Animation duration in seconds
    private let animationDuration: TimeInterval = 0.15
    
    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var showDelayTask: Task<Void, Never>?
    @State private var hideDelayTask: Task<Void, Never>?
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showTooltip {
                    TooltipView(text: text)
                        .offset(y: -8)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                        .zIndex(1000)
                        .allowsHitTesting(false)
                        .anchorPreference(key: TooltipBoundsKey.self, value: .bounds) { $0 }
                }
            }
            .onHover { hovering in
                handleHoverChange(hovering)
            }
            // Provide tooltip content to VoiceOver as accessibility hint
            .accessibilityHint(text)
    }
    
    private func handleHoverChange(_ hovering: Bool) {
        isHovering = hovering
        
        if hovering {
            // Cancel any pending hide task
            hideDelayTask?.cancel()
            hideDelayTask = nil
            
            // Start show delay if not already showing
            if !showTooltip && showDelayTask == nil {
                showDelayTask = Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(showDelay * 1_000_000_000))
                        if isHovering {
                            withAnimation(.easeInOut(duration: animationDuration)) {
                                showTooltip = true
                            }
                        }
                    } catch {
                        // Task was cancelled
                    }
                    showDelayTask = nil
                }
            }
        } else {
            // Cancel any pending show task
            showDelayTask?.cancel()
            showDelayTask = nil
            
            // Start hide delay if currently showing
            if showTooltip && hideDelayTask == nil {
                hideDelayTask = Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(hideDelay * 1_000_000_000))
                        if !isHovering {
                            withAnimation(.easeInOut(duration: animationDuration)) {
                                showTooltip = false
                            }
                        }
                    } catch {
                        // Task was cancelled
                    }
                    hideDelayTask = nil
                }
            }
        }
    }
}

// MARK: - Preference Key for Tooltip Bounds

private struct TooltipBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

// MARK: - View Extension

extension View {
    /// Adds a tooltip that appears on hover.
    ///
    /// - Parameter text: The text to display in the tooltip. Supports newlines for multi-line content.
    /// - Returns: A view with tooltip functionality.
    ///
    /// The tooltip:
    /// - Appears after 500ms hover delay
    /// - Hides after 200ms when mouse leaves
    /// - Uses 150ms ease-in-out animation
    /// - Positions above the element, centered
    /// - Is automatically read by VoiceOver as an accessibility hint
    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}

// MARK: - Preview

#Preview("Tooltip Demo") {
    VStack(spacing: 40) {
        Text("Hover over the items below to see tooltips")
            .foregroundStyle(Color.lanLensSecondaryText)
        
        HStack(spacing: 30) {
            VStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.lanLensDanger)
                    .tooltip("Critical Risk (90/100)\n3 security issues found")
                Text("Critical")
                    .font(.caption)
            }
            
            VStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.lanLensWarning)
                    .tooltip("High Risk (65/100)\nReview security settings")
                Text("High")
                    .font(.caption)
            }
            
            VStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.lanLensAccent)
                    .tooltip("Infrastructure\nAlways-on device\n98% uptime")
                Text("Server")
                    .font(.caption)
            }
            
            VStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        Circle()
                            .fill(index < 4 ? Color.lanLensAccent : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .tooltip("Smart Score: 75/100\n4/5 capability level")
                Text("Score")
                    .font(.caption)
            }
        }
        .foregroundStyle(.white)
    }
    .padding(40)
    .background(Color.lanLensBackground)
}
