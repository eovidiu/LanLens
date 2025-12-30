# LanLens - UI Design Concept

## Menu Bar App Design

### Menu Bar Icon
- **Icon**: A stylized lens/magnifying glass with network nodes inside
- **States**:
  - Idle: Gray icon
  - Scanning: Animated pulse effect (blue glow)
  - New device found: Brief green highlight
  - API server running: Small green dot indicator

### Dropdown Panel

```
┌──────────────────────────────────────────────┐
│  🔍 LanLens                           ⚙️    │
├──────────────────────────────────────────────┤
│                                              │
│  SMART DEVICES (5)                           │
│  ─────────────────────────────────────────   │
│                                              │
│  📺 Living Room TV          ●●●●○           │
│     192.168.1.45 • Samsung       Score: 85   │
│                                              │
│  🔊 Sonos One                ●●●●●           │
│     192.168.1.52 • Sonos         Score: 95   │
│                                              │
│  📷 Front Door Camera        ●●●○○           │
│     192.168.1.61 • Espressif     Score: 65   │
│                                              │
│  🌡️ Ecobee Thermostat        ●●●●○           │
│     192.168.1.33 • Ecobee        Score: 80   │
│                                              │
│  💡 Hue Bridge               ●●●●●           │
│     192.168.1.40 • Philips       Score: 100  │
│                                              │
│  OTHER DEVICES (12)                      ▼   │
│  ─────────────────────────────────────────   │
│                                              │
│  🖥️ Mac Mini                                 │
│     192.168.1.10 • Apple                     │
│                                              │
│  📱 iPhone                                   │
│     192.168.1.25 • Apple                     │
│                                              │
│  🌐 UDM Router                               │
│     192.168.1.1 • Ubiquiti                   │
│                                              │
├──────────────────────────────────────────────┤
│  🔄 Scan Now    │  🟢 API: Running  │  ···   │
└──────────────────────────────────────────────┘
```

### Color Palette (Dark Mode)

| Element | Color | Hex |
|---------|-------|-----|
| Background | Dark Gray | #1E1E1E |
| Secondary BG | Charcoal | #2D2D2D |
| Primary Text | White | #FFFFFF |
| Secondary Text | Light Gray | #8E8E93 |
| Accent (Smart) | Electric Blue | #007AFF |
| Success | Green | #30D158 |
| Warning | Orange | #FF9F0A |
| Danger | Red | #FF453A |

### Color Palette (Light Mode)

| Element | Color | Hex |
|---------|-------|-----|
| Background | White | #FFFFFF |
| Secondary BG | Light Gray | #F2F2F7 |
| Primary Text | Black | #000000 |
| Secondary Text | Gray | #8E8E93 |
| Accent (Smart) | Blue | #007AFF |
| Success | Green | #34C759 |
| Warning | Orange | #FF9500 |
| Danger | Red | #FF3B30 |

### Smart Score Visualization

The score indicator uses 5 dots:
- **●●●●●** (5/5) = Score 80-100 (Definitely Smart)
- **●●●●○** (4/5) = Score 60-79 (Likely Smart)
- **●●●○○** (3/5) = Score 40-59 (Possibly Smart)
- **●●○○○** (2/5) = Score 20-39 (Some Signals)
- **●○○○○** (1/5) = Score 1-19 (Minimal Signals)
- **○○○○○** (0/5) = Score 0 (No Smart Signals)

### Device Type Icons (SF Symbols)

| Type | Symbol | SF Symbol Name |
|------|--------|----------------|
| Router | 🌐 | `wifi.router.fill` |
| Smart TV | 📺 | `tv.fill` |
| Speaker | 🔊 | `hifispeaker.fill` |
| Camera | 📷 | `video.fill` |
| Thermostat | 🌡️ | `thermometer.medium` |
| Light | 💡 | `lightbulb.fill` |
| Computer | 🖥️ | `desktopcomputer` |
| Phone | 📱 | `iphone` |
| Hub | 🏠 | `homekit` |
| Printer | 🖨️ | `printer.fill` |
| Unknown | ❓ | `questionmark.circle` |

---

## Settings Panel

```
┌──────────────────────────────────────────────┐
│  ← Settings                                  │
├──────────────────────────────────────────────┤
│                                              │
│  GENERAL                                     │
│  ─────────────────────────────────────────   │
│  Launch at Login              [  Toggle  ]   │
│  Show in Menu Bar             [  Toggle  ]   │
│                                              │
│  API SERVER                                  │
│  ─────────────────────────────────────────   │
│  Enable API Server            [  Toggle  ]   │
│  Port                         [ 8080    ]   │
│  Host                         [ 0.0.0.0 ]   │
│  Authentication               [  Toggle  ]   │
│  Token                        [ ******** ]   │
│                                              │
│  SCANNING                                    │
│  ─────────────────────────────────────────   │
│  Auto-scan Interval           [ 5 min ▼ ]   │
│  Passive Discovery            [  Toggle  ]   │
│  Port Scanning (nmap)         [  Toggle  ]   │
│                                              │
│  SUBNETS                                     │
│  ─────────────────────────────────────────   │
│  192.168.1.0/24               [  Active  ]   │
│  192.168.2.0/24               [ Inactive ]   │
│  + Add Subnet                                │
│                                              │
│  NOTIFICATIONS                               │
│  ─────────────────────────────────────────   │
│  New Device Detected          [  Toggle  ]   │
│  Device Went Offline          [  Toggle  ]   │
│                                              │
└──────────────────────────────────────────────┘
```

---

## Device Detail View

When clicking on a device:

```
┌──────────────────────────────────────────────┐
│  ← Living Room TV                    📺      │
├──────────────────────────────────────────────┤
│                                              │
│  Smart Score                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  85/100  │
│  [████████████████████████░░░░░░░]           │
│                                              │
│  NETWORK                                     │
│  ─────────────────────────────────────────   │
│  IP Address        192.168.1.45              │
│  MAC Address       78:BD:BC:12:34:56         │
│  Vendor            Samsung                   │
│  Hostname          SamsungTV.local           │
│                                              │
│  SMART SIGNALS                               │
│  ─────────────────────────────────────────   │
│  ● mDNS: _googlecast._tcp         +25        │
│  ● mDNS: _airplay._tcp            +20        │
│  ● Port 8008: googlecast          +20        │
│  ● Port 8009: googlecast          +20        │
│                                              │
│  OPEN PORTS                                  │
│  ─────────────────────────────────────────   │
│  80/tcp    http                              │
│  443/tcp   https                             │
│  8008/tcp  googlecast                        │
│  8009/tcp  googlecast                        │
│  8443/tcp  https-alt                         │
│                                              │
│  SERVICES                                    │
│  ─────────────────────────────────────────   │
│  Google Cast    _googlecast._tcp             │
│  AirPlay        _airplay._tcp                │
│                                              │
│  HISTORY                                     │
│  ─────────────────────────────────────────   │
│  First Seen     Dec 15, 2024 3:42 PM         │
│  Last Seen      Dec 29, 2024 11:23 PM        │
│  Online         98.5% (last 7 days)          │
│                                              │
├──────────────────────────────────────────────┤
│  [  🔄 Rescan  ]  [  🏷️ Label  ]  [  🔔  ]  │
└──────────────────────────────────────────────┘
```

---

## iOS Companion App Concept

### Home Screen

```
┌─────────────────────────────────────┐
│  ●●●●●                    ⚙️        │  <- Status bar
├─────────────────────────────────────┤
│                                     │
│     🔍 LanLens                      │
│     ─────────────────────────       │
│     Connected to Mac Mini           │
│     Last scan: 2 min ago            │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  5 Smart    │  12 Other     │    │
│  │  Devices    │  Devices      │    │
│  └─────────────────────────────┘    │
│                                     │
│  SMART DEVICES                      │
│  ─────────────────────────────────  │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ 📺 Living Room TV           │    │
│  │    Samsung • 192.168.1.45   │    │
│  │    ●●●●○ Score: 85          │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ 🔊 Sonos One                │    │
│  │    Sonos • 192.168.1.52     │    │
│  │    ●●●●● Score: 95          │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ 📷 Front Door Camera        │    │
│  │    Espressif • 192.168.1.61 │    │
│  │    ●●●○○ Score: 65          │    │
│  └─────────────────────────────┘    │
│                                     │
├─────────────────────────────────────┤
│   🏠      📋      🔍      ⚙️       │
│  Home   Devices   Scan  Settings   │
└─────────────────────────────────────┘
```

---

## Typography

| Element | Font | Size | Weight |
|---------|------|------|--------|
| App Title | SF Pro Display | 16pt | Semibold |
| Section Header | SF Pro Text | 11pt | Semibold |
| Device Name | SF Pro Text | 13pt | Medium |
| Device Details | SF Pro Text | 11pt | Regular |
| Score Badge | SF Mono | 10pt | Medium |
| Button Text | SF Pro Text | 12pt | Medium |

---

## Animations

### Scan Animation
- Menu bar icon pulses with a subtle glow
- Radial wave effect emanating from center
- Duration: 300ms per pulse, continuous while scanning

### New Device Animation
- Card slides in from right
- Subtle bounce effect
- Brief highlight glow (green)
- Duration: 400ms

### Score Update Animation
- Progress bar fills smoothly
- Number counts up
- Duration: 600ms ease-out

---

## Accessibility

- VoiceOver support for all elements
- High contrast mode support
- Keyboard navigation (Tab, Arrow keys)
- Minimum touch target: 44x44pt (iOS)
- Dynamic Type support

---

## Implementation Notes

### SwiftUI Components Needed
- `MenuBarExtra` for menu bar presence
- `List` with sections for device listing
- `ProgressView` for smart score visualization
- `NavigationStack` for drill-down views
- `Toggle` for settings switches
- `TextField` for input fields

### State Management
- `@Observable` for device list
- `@AppStorage` for user preferences
- `@Environment(\.openWindow)` for detail views

To generate actual mockup images, set your `GEMINI_API_KEY` environment variable and run:

```bash
# Generate menu bar mockup
python3 scripts/nano_banana.py ui "LanLens macOS menu bar app..." --type desktop --style dark --model pro --output mockup.png
```
