# LanLens Project Guidelines

## Project Overview
LanLens is a macOS menu bar application for network device scanning and discovery. It uses SwiftUI with MenuBarExtra (.window style) and follows Apple Human Interface Guidelines for a native Mac experience.

## Build Commands
```bash
# Build
xcodebuild -scheme LanLensApp -configuration Debug build

# Run
open /Users/oeftimie/Library/Developer/Xcode/DerivedData/LanLensApp-fblrluhkibusqheukntifezsynmk/Build/Products/Debug/LanLensApp.app

# Kill running instance
pkill -f "LanLensApp"
```

## Architecture
- **LanLensCore**: Swift Package with scanning logic (ARP, mDNS, SSDP, port scanning)
- **LanLensApp**: SwiftUI macOS app with MenuBarExtra
- **State Management**: `@Observable` macro with `AppState` and `UserPreferences`

## Key Files
- `Views/MenuBarView.swift` - Main menu bar popover
- `Views/DeviceDetailView.swift` - Device detail with capability tags
- `Views/DeviceRowView.swift` - Device list rows with hover states
- `Views/SettingsView.swift` - App preferences

---

## SwiftUI Gotchas & Lessons Learned

### Menu Label Foreground Color Override (CRITICAL)

**Problem**: SwiftUI's `Menu` component with `.menuStyle(.borderlessButton)` **silently overrides** the `foregroundColor` of its label content, ignoring any explicit color you set.

```swift
// THIS DOES NOT WORK - color will be overridden to system gray
Menu {
    // menu items
} label: {
    Image(systemName: "ellipsis")
        .foregroundColor(.white)  // IGNORED by Menu
}
.menuStyle(.borderlessButton)
```

**Solution**: Use `Button` + `popover` instead for custom-styled menu triggers:

```swift
// THIS WORKS - full control over styling
@State private var showMenu = false

Button {
    showMenu = true
} label: {
    Text("•••")
        .foregroundColor(.white)  // RESPECTED
}
.buttonStyle(.plain)
.popover(isPresented: $showMenu) {
    // custom menu content
}
```

**When this matters**: Dark UI themes where you need white/light icons on dark backgrounds.

---

## UX Standards (macOS Native)

### Hover States Required
All interactive elements must have hover feedback:
- Device rows: background highlight + chevron indicator
- Buttons: opacity/color change
- Collapsible headers: text brightens + background highlight

### Accessibility
- All interactive elements need `.accessibilityLabel()`
- Respect `accessibilityReduceMotion` for animations
- Combine related elements with `.accessibilityElement(children: .combine)`

### Menu Bar App Conventions
- Fixed width: 360pt
- Max height: 400-700pt (adaptive)
- Keyboard shortcuts: Cmd+, (settings), Cmd+R (scan), Cmd+Q (quit), Escape (back/cancel)
