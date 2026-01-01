# LanLens UX Specification

**Version:** 1.0
**Date:** January 2, 2026
**Status:** Implemented

---

## 1. Design Philosophy

### 1.1 Core Principles

| Principle | Implementation |
|-----------|----------------|
| **Native First** | SwiftUI with system controls, no custom chrome |
| **Precision Input** | Keyboard shortcuts, hover states, right-click menus |
| **Information Hierarchy** | Progressive disclosure, smart defaults |
| **Dark Mode First** | Designed for dark mode, light mode supported |
| **HIG Compliance** | Follows Apple Human Interface Guidelines |

### 1.2 Design Goals

1. **Instant Comprehension**: Network status visible at a glance
2. **Progressive Detail**: Drill down for more information
3. **Non-Intrusive**: Menu bar app, minimal CPU/battery impact
4. **Professional**: Clean typography, no frivolous decoration

---

## 2. Component Inventory

### 2.1 View Components

| Component | File | Purpose |
|-----------|------|---------|
| `LanLensMenuBarApp` | `LanLensMenuBarApp.swift` | App entry point, MenuBarExtra |
| `MenuBarView` | `Views/MenuBarView.swift` | Main popover content |
| `DeviceListView` | `Views/DeviceListView.swift` | Device list with sections |
| `DeviceRowView` | `Views/DeviceRowView.swift` | Individual device row |
| `DeviceDetailView` | `Views/DeviceDetailView.swift` | Full device information |
| `SettingsView` | `Views/SettingsView.swift` | Preferences panel |

### 2.2 Reusable Components

| Component | File | Purpose |
|-----------|------|---------|
| `DeviceIcon` | `Components/DeviceIcon.swift` | SF Symbol for device type |
| `StatusIndicator` | `Components/StatusIndicator.swift` | Online/offline indicator |
| `ScoreIndicator` | `Components/ScoreIndicator.swift` | Smart score visualization |
| `SecurityBadge` | `Components/SecurityBadge.swift` | Risk level badge |
| `SecurityPostureCard` | `Components/SecurityPostureCard.swift` | Security assessment card |
| `BehaviorBadge` | `Components/BehaviorBadge.swift` | Behavior classification |
| `BehaviorProfileCard` | `Components/BehaviorProfileCard.swift` | Behavior details |
| `MACAnalysisCard` | `Components/MACAnalysisCard.swift` | Vendor analysis |
| `TooltipModifier` | `Components/TooltipModifier.swift` | Hover tooltips |

---

## 3. Visual Design System

### 3.1 Color Palette

#### Dark Mode (Primary)

| Token | Hex | Usage |
|-------|-----|-------|
| `lanLensBackground` | #1E1E1E | Panel background |
| `lanLensCard` | #2D2D2D | Card background |
| `lanLensAccent` | #007AFF | Interactive elements |
| `lanLensSuccess` | #30D158 | Online status, success |
| `lanLensWarning` | #FF9F0A | Medium risk |
| `lanLensDanger` | #FF453A | High/critical risk |
| `lanLensSecondaryText` | #8E8E93 | Labels, metadata |
| `lanLensRandomized` | #9B59B6 | Randomized MAC indicator |
| `lanLensGoogleBlue` | #4285F4 | Google Cast devices |

### 3.2 Typography

| Element | Font | Size | Weight |
|---------|------|------|--------|
| App Title | SF Pro Display | 16pt | Semibold |
| Section Header | SF Pro Text | 11pt | Semibold (caps) |
| Device Name | SF Pro Text | 13pt | Medium |
| Device Details | SF Pro Text | 11pt | Regular |
| Score Badge | SF Mono | 10pt | Medium |
| Button Text | SF Pro Text | 12pt | Medium |

### 3.3 Spacing

| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4pt | Inline spacing |
| `sm` | 8pt | Component padding |
| `md` | 12pt | Section spacing |
| `lg` | 16pt | Group spacing |
| `xl` | 24pt | Major sections |

### 3.4 Corner Radii

| Token | Value | Usage |
|-------|-------|-------|
| `small` | 4pt | Badges, chips |
| `medium` | 8pt | Cards, rows |
| `large` | 12pt | Panels |

### 3.5 Iconography

All icons use SF Symbols for consistency with macOS.

| Device Type | SF Symbol |
|-------------|-----------|
| Smart TV | `tv.fill` |
| Speaker | `hifispeaker.fill` |
| Camera | `video.fill` |
| Thermostat | `thermometer.medium` |
| Light | `lightbulb.fill` |
| Plug | `powerplug.fill` |
| Hub | `homekit` |
| Printer | `printer.fill` |
| NAS | `internaldrive.fill` |
| Computer | `desktopcomputer` |
| Phone | `iphone` |
| Tablet | `ipad` |
| Router | `wifi.router.fill` |
| Access Point | `antenna.radiowaves.left.and.right` |
| Unknown | `questionmark.circle` |

**Menu Bar Icons:**
- `magnifyingglass` - Idle state
- `magnifyingglass.circle` - API running
- `magnifyingglass.circle.fill` - Scanning active

---

## 4. Interaction Patterns

### 4.1 Device Card Interactions

| Action | Trigger | Response |
|--------|---------|----------|
| View Details | Click row | Navigate to DeviceDetailView |
| Hover | Mouse enter | Background highlight, chevron appears |
| Tooltip | Hover on badge | Show detailed info |
| Context Menu | Right-click | Copy IP, Copy MAC, Deep Scan, Forget |

**Hover Animation:**
```swift
.animation(.easeInOut(duration: 0.15), value: isHovered)
```

**Risk Indicator Border:**
- 3pt left border with rounded corners
- Critical: Full red
- High: 75% red opacity
- Medium: Full warning (orange)
- Low/Unknown: Hidden

### 4.2 Collapsible Sections

**"Other Devices" Section:**
- Header is interactive button
- Chevron rotates (up/down) on toggle
- Content animates with `.easeInOut(duration: 0.2)`
- Header brightens on hover

### 4.3 Scan Behavior

| State | Label | Icon | Color |
|-------|-------|------|-------|
| Idle | "Scan Now" | `arrow.clockwise` | `lanLensAccent` |
| Scanning | "Stop" | `stop.fill` | `lanLensDanger` |

**Status Indicator:**
- Pulsing animation (0.6s ease-in-out, repeat forever)
- Scale effect: 0.8 to 1.2
- Opacity: 0.6 to 1.0
- Respects `accessibilityReduceMotion`

### 4.4 Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Settings | Cmd+, |
| Scan/Stop | Cmd+R |
| Back/Cancel | Escape |
| Quit | Cmd+Q |

### 4.5 Tooltip Behavior

- Show delay: 500ms
- Hide delay: 200ms
- Animation: 150ms ease-in-out
- Positioning: Above element, centered

---

## 5. Information Hierarchy

### 5.1 Network Summary

Displayed at top of main view:
1. **Total Devices** - White, large number
2. **Smart Devices** - Accent color, filtered count
3. **Issues** - Warning color if > 0, success if 0

### 5.2 Device Classification

**Smart Score Threshold:** 20 points
- Devices with `smartScore >= 20` appear in "Smart Devices" section
- Devices with `smartScore < 20` appear in "Other Devices" section

**Smart Score Display (5-dot indicator):**
- 0: 0 dots
- 1-19: 1 dot
- 20-39: 2 dots
- 40-59: 3 dots
- 60-79: 4 dots
- 80+: 5 dots

### 5.3 Security Risk Communication

| Level | Color | Visual Weight |
|-------|-------|---------------|
| Critical | `lanLensDanger` full | Pulsing shield, red background tint, left border |
| High | `lanLensDanger` 75-85% | Shield icon, left border |
| Medium | `lanLensWarning` | Shield icon, left border |
| Low | `lanLensSuccess` | No badge (hidden to reduce noise) |
| Unknown | `lanLensSecondaryText` | No badge |

### 5.4 Device Identity Hierarchy

Display name resolution order:
1. User label (if set)
2. Hostname (cleaned of `.local`)
3. UPnP friendly name
4. Fingerbank device name (if not generic)
5. UPnP manufacturer + model
6. Vendor + MAC suffix
7. Fingerbank name (even if generic)
8. Device type capitalized
9. "Device (XX:XX)" as fallback

---

## 6. Platform Integration

### 6.1 Menu Bar Behavior

```swift
@main
struct LanLensMenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("LanLens", systemImage: menuBarIcon) {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

**Icon States:**
```swift
if isScanning { "magnifyingglass.circle.fill" }
else if isAPIRunning { "magnifyingglass.circle" }
else { "magnifyingglass" }
```

**Right-click Support:** Custom `NSEvent` monitor for quit menu

### 6.2 Window Dimensions

```swift
.frame(width: 360)
.frame(minHeight: 400, maxHeight: 700)
```

### 6.3 Appearance

```swift
.preferredColorScheme(.dark)
```
Forced dark mode regardless of system preference.

### 6.4 System Notifications

Uses `UserNotifications` framework:
- New device detected
- Device went offline
- Notifications show even when app is in foreground

### 6.5 Launch at Login

Uses `SMAppService` via `LaunchAtLoginService`:
- States: enabled, disabled, requiresApproval, notFound
- Links to System Settings when approval needed

---

## 7. Accessibility

### 7.1 VoiceOver Support

```swift
.accessibilityLabel("MAC address: \(macAddress)")
.accessibilityLabel("\(displayName), \(device.ip)")
.accessibilityHint("Double-tap to view details")
```

### 7.2 Reduce Motion

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

if posture.riskLevel == .critical && !reduceMotion {
    isPulsing = true
}
```

### 7.3 Text Selection

Technical values (IP, MAC, hostnames) support text selection:
```swift
.textSelection(.enabled)
```

---

## 8. State Documentation

### 8.1 Interactive States

| Element | Default | Hover | Pressed | Disabled |
|---------|---------|-------|---------|----------|
| Device Row | Card bg | +white 8%, border, chevron | Navigation | N/A |
| Button (Primary) | Accent bg | Opacity change | Pressed color | Muted |
| Section Header | Secondary text | White 90% text, bg tint | Toggle | N/A |

### 8.2 Content States

| State | Treatment |
|-------|-----------|
| Empty (No devices) | Centered message text |
| Loading/Scanning | Pulsing status indicator, "Scanning..." text |
| Error | Error message stored in `appState.scanError` |

---

## 9. Animation Specifications

### 9.1 Timing Curves

| Animation | Duration | Easing |
|-----------|----------|--------|
| Hover transitions | 0.15s | easeInOut |
| Expand/collapse | 0.2s | easeInOut |
| Device updates | 0.2s | easeInOut |
| Tooltip appear/disappear | 0.15s | easeInOut |
| Scanning pulse | 0.6s | easeInOut (repeat) |
| Critical badge pulse | 0.8s | easeInOut (repeat) |

### 9.2 Animation Values

**Scanning Pulse:**
```swift
.scaleEffect(isPulsing ? 1.2 : 0.8)
.opacity(isPulsing ? 1 : 0.6)
```

**Critical Badge Pulse:**
```swift
.scaleEffect(isPulsing ? 1.1 : 1.0)
.opacity(isPulsing ? 0.8 : 1.0)
```

---

## 10. Known Gotchas

### 10.1 Menu Label Color Override

**Issue:** SwiftUI's `Menu` component with `.menuStyle(.borderlessButton)` silently overrides `foregroundColor`.

**Solution:** Use `Button` + `popover` pattern:
```swift
Button { showMenu = true } label: {
    Text("•••")
        .foregroundColor(.white)
}
.popover(isPresented: $showMenu) { ... }
```

### 10.2 NavigationStack in MenuBarExtra

- `.navigationBarBackButtonHidden(true)` required for custom back buttons
- Environment objects must be re-injected at navigation destinations

---

## 11. HIG Compliance Summary

| Guideline Area | Status | Notes |
|----------------|--------|-------|
| Menu Bar Integration | Compliant | Uses MenuBarExtra with window style |
| Navigation | Compliant | NavigationStack with back navigation |
| Keyboard Shortcuts | Compliant | Standard Mac shortcuts |
| Right-click Support | Compliant | Context menu for quit |
| Dark Mode | N/A | Dark-only design |
| Accessibility | Compliant | VoiceOver labels, reduce motion |
| System Controls | Compliant | Native Toggle, Picker, Button |
| Hover States | Compliant | All interactive elements have hover feedback |
| SF Symbols | Compliant | Exclusive use of SF Symbols |
| Notifications | Compliant | Uses UserNotifications framework |

---

## Appendix A: View Hierarchy

```
LanLensMenuBarApp
└── MenuBarExtra (style: .window)
    └── MenuBarView
        ├── Header (logo + settings)
        ├── NetworkSummary
        ├── DeviceListView
        │   ├── Section: Smart Devices
        │   │   └── DeviceRowView (foreach)
        │   │       ├── DeviceIcon
        │   │       ├── Device Info
        │   │       ├── SecurityBadge
        │   │       ├── BehaviorBadge
        │   │       └── ScoreIndicator
        │   └── Section: Other Devices
        │       └── DeviceRowView (foreach)
        └── Footer (scan button + status)

DeviceDetailView (navigation destination)
├── Header (icon + name)
├── NetworkInfoCard
├── SecurityPostureCard
├── BehaviorProfileCard
├── MACAnalysisCard
├── OpenPortsSection
├── ServicesSection
└── ActionButtons

SettingsView (sheet)
├── GeneralSection
├── APIServerSection
├── ScanningSection
└── AboutSection
```

---

## Appendix B: File Reference

### Views
- `LanLensApp/LanLensApp/LanLensMenuBarApp.swift`
- `LanLensApp/LanLensApp/Views/MenuBarView.swift`
- `LanLensApp/LanLensApp/Views/DeviceListView.swift`
- `LanLensApp/LanLensApp/Views/DeviceRowView.swift`
- `LanLensApp/LanLensApp/Views/DeviceDetailView.swift`
- `LanLensApp/LanLensApp/Views/SettingsView.swift`

### Components
- `LanLensApp/LanLensApp/Views/Components/DeviceIcon.swift`
- `LanLensApp/LanLensApp/Views/Components/StatusIndicator.swift`
- `LanLensApp/LanLensApp/Views/Components/SecurityBadge.swift`
- `LanLensApp/LanLensApp/Views/Components/ScoreIndicator.swift`
- `LanLensApp/LanLensApp/Views/Components/BehaviorBadge.swift`
- `LanLensApp/LanLensApp/Views/Components/TooltipModifier.swift`
- `LanLensApp/LanLensApp/Views/Components/SecurityPostureCard.swift`
- `LanLensApp/LanLensApp/Views/Components/BehaviorProfileCard.swift`
- `LanLensApp/LanLensApp/Views/Components/MACAnalysisCard.swift`

### Design System
- `LanLensApp/LanLensApp/Design/Colors.swift`

### State Management
- `LanLensApp/LanLensApp/State/AppState.swift`
- `LanLensApp/LanLensApp/State/UserPreferences.swift`
