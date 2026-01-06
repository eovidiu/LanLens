# Device Fingerprinting in LanLens

## Overview

Device fingerprinting is a technique for identifying and classifying network devices based on their observable characteristics. LanLens uses fingerprinting to determine what type of device is connected to your network, who manufactured it, and what operating system or firmware it runs.

### Why Fingerprinting Matters

When scanning a home network, you might find 20+ devices. Knowing only the MAC address and IP tells you very little. Fingerprinting answers questions like:

- Is this device a smart TV, a security camera, or a thermostat?
- What manufacturer made it?
- What OS/firmware version is it running?
- Is it a device I recognize, or something unexpected?

### Multi-Level Approach

LanLens implements device fingerprinting using multiple complementary techniques:

| Level | Method | External Dependency | Data Quality |
|-------|--------|---------------------|--------------|
| 1 | UPnP Device Description | None | Good |
| 2 | Bundled OUI Database | None | Good |
| 3 | DHCP Fingerprint Database | None | Very Good |
| 4 | TLS/JA3S Fingerprinting | None | Very Good |
| 5 | Fingerbank API | API key required | Excellent |

**Levels 1-4** run automatically without any external dependencies. **Level 5** provides enhanced identification but requires a free Fingerbank API key.

---

## Level 1: UPnP Device Description (Default)

### How It Works

When LanLens discovers a device via SSDP (Simple Service Discovery Protocol), the device announces itself with a `LOCATION` header pointing to an XML description file. LanLens fetches and parses this XML to extract device information.

```
Discovery Flow:

  +-----------+    M-SEARCH     +-----------+
  |  LanLens  | --------------> |  Device   |
  +-----------+                 +-----------+
       ^                              |
       |        SSDP Response         |
       |   (includes LOCATION URL)    |
       +------------------------------+
       |
       |        HTTP GET
       +----------------------------> http://device:port/description.xml
       ^
       |        XML Response
       +------------------------------+
```

### What Data It Provides

The UPnP device description XML typically contains:

| Field | Description | Example |
|-------|-------------|---------|
| `friendlyName` | Human-readable device name | "Living Room Roku" |
| `manufacturer` | Company that made the device | "Roku, Inc." |
| `manufacturerURL` | Manufacturer website | "https://www.roku.com/" |
| `modelDescription` | Description of device model | "Roku Streaming Player" |
| `modelName` | Model identifier | "Roku Ultra" |
| `modelNumber` | Specific model number | "4800X" |
| `serialNumber` | Device serial (sometimes) | "YH009P123456" |
| `deviceType` | UPnP device type URN | "urn:roku-com:device:player:1-0" |
| `serviceList` | Available UPnP services | DIAL, media control, etc. |

### Example XML Response

```xml
<?xml version="1.0" encoding="UTF-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:roku-com:device:player:1-0</deviceType>
    <friendlyName>Living Room Roku</friendlyName>
    <manufacturer>Roku, Inc.</manufacturer>
    <manufacturerURL>https://www.roku.com/</manufacturerURL>
    <modelDescription>Roku Streaming Player</modelDescription>
    <modelName>Roku Ultra</modelName>
    <modelNumber>4800X</modelNumber>
    <serialNumber>YH009P123456</serialNumber>
    <serviceList>
      <service>
        <serviceType>urn:dial-multiscreen-org:service:dial:1</serviceType>
        <serviceId>urn:dial-multiscreen-org:serviceId:dial</serviceId>
      </service>
    </serviceList>
  </device>
</root>
```

### Advantages

- **No external dependencies**: Works entirely on your local network
- **No API keys required**: Ready to use out of the box
- **Fast**: Direct HTTP request to the device
- **Accurate for UPnP devices**: Information comes directly from the device itself

### Limitations

- **Only works for UPnP devices**: Many IoT devices don't support UPnP
- **Device must respond**: Some devices have UPnP disabled or firewalled
- **Incomplete data**: Not all devices populate all XML fields
- **No OS/version detection**: UPnP doesn't typically expose this information
- **No confidence scoring**: You either get data or you don't

---

## Level 2: Bundled OUI Database

### How It Works

Every network device has a MAC address, and the first three bytes (OUI - Organizationally Unique Identifier) identify the manufacturer. LanLens includes a bundled database that maps OUI prefixes to device manufacturers and common device types.

```
MAC Address: AA:BB:CC:DD:EE:FF
             └──┬──┘
               OUI → Lookup → "Apple Inc." → Likely iPhone/iPad/Mac
```

### What Data It Provides

| Field | Description | Example |
|-------|-------------|---------|
| `vendor` | Manufacturer name | "Apple Inc." |
| `deviceTypes` | Common device types for this vendor | ["phone", "tablet", "laptop"] |
| `confidence` | Match confidence | 0.6 |

### Advantages

- **No network requests**: Entirely local lookup
- **Fast**: Sub-millisecond lookups
- **Universal coverage**: Works for any device with a MAC address
- **Offline capable**: No internet required

### Limitations

- **Vendor-level only**: Identifies manufacturer, not specific device model
- **MAC randomization**: Modern devices may use random MACs (reduces effectiveness)
- **Generic results**: Many vendors make multiple device types

---

## Level 3: DHCP Fingerprint Database

### How It Works

When devices request an IP address via DHCP, they include Option 55 - a Parameter Request List that specifies which DHCP options they want. This list is characteristic of different operating systems and device types.

LanLens includes a bundled database of known DHCP fingerprints mapped to device types.

```
DHCP Option 55: 1,3,6,15,31,33,43,44,46,47,119,121,249,252
                ↓
           SHA256 Hash → Lookup → "Apple iOS device"
```

### What Data It Provides

| Field | Description | Example |
|-------|-------------|---------|
| `deviceName` | Matched device type | "Apple iPhone" |
| `operatingSystem` | Operating system | "iOS" |
| `confidence` | Match confidence | 0.85 |

### Advantages

- **High accuracy**: DHCP fingerprints are very distinctive
- **Works across vendors**: OS fingerprint, not just manufacturer
- **Offline capable**: Uses bundled database

### Limitations

- **Requires DHCP data**: Only works if DHCP fingerprint is known
- **Static database**: Updated with app releases only

---

## Level 4: TLS/JA3S Fingerprinting

### How It Works

When LanLens performs a deep scan and finds open HTTPS ports (443, 8443, etc.), it connects and captures the TLS Server Hello response. The server's TLS configuration creates a unique fingerprint called JA3S.

```
TLS Connection to Device:443
        ↓
   Server Hello
        ↓
   Extract: TLS Version + Cipher + Extensions
        ↓
   JA3S Hash → Lookup → "nginx/1.18", "Apache", "Synology DSM"
```

### What Data It Provides

| Field | Description | Example |
|-------|-------------|---------|
| `ja3sHash` | Server fingerprint hash | "eb1d94daa7e0344597e756a1fb6e7054" |
| `serverSoftware` | Matched server software | "nginx" |
| `tlsVersion` | Negotiated TLS version | "TLS 1.3" |
| `cipherSuite` | Negotiated cipher | "TLS_AES_256_GCM_SHA384" |

### Advantages

- **Identifies server software**: Can identify web servers, NAS devices, etc.
- **No special permissions**: Uses standard TLS connections
- **App Store compatible**: Works within sandbox restrictions

### Limitations

- **Requires HTTPS port**: Only works on devices with TLS services
- **Active probing**: Requires connecting to the device
- **Server-side only**: Identifies what software the device runs, not the device itself

---

## Level 5: Fingerbank Integration (Enhanced)

### What Is Fingerbank?

[Fingerbank](https://fingerbank.org) is a community-driven database of device fingerprints. It identifies devices based on their DHCP fingerprints, MAC address prefixes, and other network signals. Fingerbank powers device identification in enterprise network access control (NAC) solutions like PacketFence.

### How to Get an API Key

1. Visit [https://fingerbank.org](https://fingerbank.org)
2. Click "Sign Up" to create a free account
3. After email verification, log in to your dashboard
4. Navigate to "API Keys" section
5. Generate a new API key
6. Copy the key and add it to LanLens Settings

### What Additional Data It Provides

Fingerbank returns rich device metadata:

| Field | Description | Example |
|-------|-------------|---------|
| `device.name` | Specific device model | "Apple iPhone 15 Pro" |
| `device.parent` | Device category hierarchy | "Apple iPhone" |
| `device.parents` | Full hierarchy path | ["Apple", "Apple iPhone", "Apple iPhone 15"] |
| `device.mobile` | Is it a mobile device? | true |
| `device.tablet` | Is it a tablet? | false |
| `score` | Confidence score (0-100) | 87 |
| `version` | OS/firmware version | "iOS 17.2" |

### Fingerprint Sources

LanLens sends the following signals to Fingerbank for identification:

1. **MAC Address**: The device's MAC address (provides OUI/vendor info)
2. **DHCP Fingerprint**: Option 55 parameter request list (if captured)
3. **User Agent**: From HTTP probes (if available)
4. **Open Ports**: Port combination patterns

### API Request Example

```
GET https://api.fingerbank.org/api/v2/combinations/interrogate
Authorization: Bearer YOUR_API_KEY

{
  "mac": "AA:BB:CC:DD:EE:FF",
  "dhcp_fingerprint": "1,3,6,15,31,33,43,44,46,47,119,121,249,252",
  "user_agents": ["Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X)"]
}
```

### API Response Example

```json
{
  "device": {
    "id": 12345,
    "name": "Apple iPhone 15 Pro",
    "parent_id": 789,
    "parents": [
      {"id": 100, "name": "Apple"},
      {"id": 789, "name": "Apple iPhone"},
      {"id": 12300, "name": "Apple iPhone 15 series"}
    ],
    "mobile": true,
    "tablet": false
  },
  "score": 87,
  "version": "iOS 17.2"
}
```

### Rate Limits

Fingerbank free tier limits:

| Limit | Value |
|-------|-------|
| Requests per hour | 300 |
| Requests per day | 2,000 |
| Requests per month | 30,000 |

LanLens tracks API usage and will:
- Cache responses to minimize API calls
- Back off automatically when approaching limits
- Fall back to Level 1 if quota is exhausted

### Privacy Considerations

When using Fingerbank:

- **MAC addresses are sent**: Your device MAC addresses are transmitted to Fingerbank servers
- **No IP addresses sent**: LanLens only sends MAC, not your internal IPs
- **Data retention**: See Fingerbank's privacy policy for their data retention practices
- **Optional feature**: Fingerbank integration is opt-in; it never runs without an API key

If privacy is a concern, you can:
1. Use only Level 1 (UPnP) fingerprinting
2. Review Fingerbank's [privacy policy](https://fingerbank.org/privacy)
3. Self-host Fingerbank (requires enterprise license)

---

## Caching

### Cache Location

Fingerprint cache is stored at:

```
~/Library/Application Support/LanLens/FingerprintCache/
```

The cache directory contains:

```
FingerprintCache/
  fingerbank/           # Level 2 Fingerbank responses
    <mac-hash>.json     # One file per device
  upnp/                 # Level 1 UPnP descriptions
    <mac-hash>.xml      # One file per device
  metadata.json         # Cache statistics and timestamps
```

### Cache Time-To-Live (TTL)

| Cache Type | TTL | Rationale |
|------------|-----|-----------|
| Fingerbank | 7 days | Device identity rarely changes |
| UPnP | 24 hours | Friendly names might be updated |

### Cache Invalidation

The cache is automatically invalidated when:

1. **TTL expires**: Entry is older than the configured TTL
2. **Device signals change**:
   - Different DHCP fingerprint observed
   - New user agent detected
   - Port scan reveals different open ports
3. **Manual clear**: User clears cache from Settings

### Clearing the Cache

**From the app:**
1. Open LanLens
2. Go to Settings
3. Scroll to "Advanced" section
4. Click "Clear Fingerprint Cache"

**From Terminal:**
```bash
rm -rf ~/Library/Application\ Support/LanLens/FingerprintCache/
```

**Clear only Fingerbank cache:**
```bash
rm -rf ~/Library/Application\ Support/LanLens/FingerprintCache/fingerbank/
```

### Cache Statistics

LanLens tracks cache performance in `metadata.json`:

```json
{
  "created": "2024-12-30T10:00:00Z",
  "fingerbank": {
    "entries": 15,
    "hits": 142,
    "misses": 18,
    "hitRate": 0.89
  },
  "upnp": {
    "entries": 8,
    "hits": 95,
    "misses": 12,
    "hitRate": 0.89
  }
}
```

---

## Configuration

### Adding Fingerbank API Key

1. Open LanLens from the menu bar
2. Click the Settings gear icon
3. Scroll to "Device Fingerprinting" section
4. Enter your Fingerbank API key
5. Click "Verify" to test the key
6. Toggle "Enable Fingerbank" to activate

### Settings Reference

| Setting | Default | Description |
|---------|---------|-------------|
| Enable UPnP Fingerprinting | On | Fetch device descriptions from UPnP LOCATION URLs |
| Enable Fingerbank | Off | Use Fingerbank API for enhanced identification |
| Fingerbank API Key | (empty) | Your Fingerbank API key |
| Cache TTL (Fingerbank) | 7 days | How long to cache Fingerbank results |
| Cache TTL (UPnP) | 24 hours | How long to cache UPnP descriptions |

### Fallback Behavior

When Fingerbank is enabled but unavailable:

1. **No API key configured**: Level 1 only
2. **API key invalid**: Warning shown, Level 1 only
3. **Rate limit exceeded**: Falls back to Level 1, retries after cooldown
4. **Network error**: Uses cached data if available, else Level 1
5. **Fingerbank returns no match**: Falls back to Level 1 data

---

## Technical Details

### Data Flow Diagram

```
                     +-------------------+
                     |   Device Found    |
                     | (SSDP Discovery)  |
                     +--------+----------+
                              |
                              v
                     +-------------------+
                     |  Has LOCATION?    |
                     +--------+----------+
                              |
              +---------------+---------------+
              | Yes                           | No
              v                               v
     +-------------------+           +-------------------+
     | Level 1: Fetch    |           | Skip UPnP         |
     | UPnP Description  |           +-------------------+
     +--------+----------+
              |
              v
     +-------------------+
     | Parse XML         |
     | Extract fields    |
     +--------+----------+
              |
              v
     +-------------------+
     | Fingerbank        |
     | Enabled?          |
     +--------+----------+
              |
     +--------+----------+
     | Yes               | No
     v                   v
+-------------------+   +-------------------+
| Check Cache       |   | Use Level 1 Data  |
+--------+----------+   +-------------------+
         |
+--------+----------+
| Cache Hit?        |
+--------+----------+
         |
+--------+----------+
| Yes               | No
v                   v
+---------------+   +-------------------+
| Return Cached |   | Level 2: Call     |
+---------------+   | Fingerbank API    |
                    +--------+----------+
                             |
                             v
                    +-------------------+
                    | Store in Cache    |
                    +--------+----------+
                             |
                             v
                    +-------------------+
                    | Merge Results     |
                    | (L1 + L2)         |
                    +-------------------+
```

### Integration with Scan Flow

Fingerprinting integrates into the discovery workflow:

1. **SSDP Discovery**: `SSDPListener` detects device, captures LOCATION URL
2. **Device Creation**: `DiscoveryManager` creates/updates `Device` record
3. **Fingerprint Request**: Async fingerprint lookup triggered
4. **Data Merge**: Fingerprint data merged into `Device.fingerprint` field
5. **UI Update**: Device list refreshes with new information

### DeviceFingerprint Fields Reference

```swift
public struct DeviceFingerprint: Codable, Sendable {
    // Level 1: UPnP Data
    public let friendlyName: String?
    public let manufacturer: String?
    public let manufacturerURL: String?
    public let modelDescription: String?
    public let modelName: String?
    public let modelNumber: String?
    public let serialNumber: String?
    public let deviceType: String?          // UPnP device type URN
    public let services: [UPnPService]?

    // Level 2: Fingerbank Data
    public let fingerbankDeviceName: String?
    public let fingerbankDeviceId: Int?
    public let fingerbankParents: [String]?
    public let fingerbankScore: Int?        // 0-100 confidence
    public let operatingSystem: String?
    public let osVersion: String?
    public let isMobile: Bool?
    public let isTablet: Bool?

    // Metadata
    public let source: FingerprintSource    // .upnp, .fingerbank, .both
    public let timestamp: Date
    public let cacheHit: Bool
}

public struct UPnPService: Codable, Sendable {
    public let serviceType: String
    public let serviceId: String
    public let controlURL: String?
    public let eventSubURL: String?
    public let SCPDURL: String?
}

public enum FingerprintSource: String, Codable, Sendable {
    case upnp            // Level 1: UPnP device description
    case fingerbank      // Level 5: Fingerbank API
    case both            // Multiple sources contributed data
    case none            // No fingerprint data available
    case dhcpFingerprint // Level 3: DHCP fingerprint database
    case tlsFingerprint  // Level 4: TLS/JA3S fingerprinting
}
```

### Error Handling

| Error | Behavior | User Notification |
|-------|----------|-------------------|
| UPnP fetch timeout (5s) | Skip Level 1 | None |
| UPnP parse error | Skip Level 1 | None |
| Fingerbank 401 | Disable Fingerbank | "Invalid API key" |
| Fingerbank 429 | Cooldown 1 hour | "Rate limit reached" |
| Fingerbank 5xx | Retry 3x, then skip | None |
| Network unreachable | Use cache or skip | None |

---

## Troubleshooting

### Device Not Being Fingerprinted

1. **Check if device supports UPnP**
   - Not all devices advertise via SSDP
   - Some devices have UPnP disabled in settings

2. **Verify SSDP is working**
   - Run a manual scan
   - Check if device appears in "Services" tab

3. **Check firewall settings**
   - Port 1900/UDP must be open for SSDP
   - Device's HTTP port must be accessible

### Fingerbank Not Working

1. **Verify API key**
   - Check key in Settings
   - Click "Verify" button
   - Look for error messages

2. **Check rate limits**
   - View API usage in Settings
   - Wait for quota reset if exceeded

3. **Check network connectivity**
   - LanLens needs internet access for Fingerbank
   - Verify `api.fingerbank.org` is reachable

### Stale Fingerprint Data

1. **Clear cache for specific device**
   - Device detail view > Clear Fingerprint

2. **Clear all fingerprint cache**
   - Settings > Advanced > Clear Fingerprint Cache

3. **Force re-scan**
   - Trigger new network scan
   - Fingerprints will be refreshed on next discovery

---

## API Reference

### REST Endpoints

**Get device fingerprint:**
```
GET /api/devices/{mac}/fingerprint

Response:
{
  "fingerprint": { ... DeviceFingerprint fields ... },
  "source": "both",
  "cached": true,
  "cacheAge": 3600
}
```

**Refresh fingerprint (bypass cache):**
```
POST /api/devices/{mac}/fingerprint/refresh

Response:
{
  "fingerprint": { ... },
  "source": "both",
  "cached": false
}
```

**Get fingerprint statistics:**
```
GET /api/fingerprint/stats

Response:
{
  "upnp": {
    "enabled": true,
    "devicesFingerprinted": 8,
    "cacheHitRate": 0.89
  },
  "fingerbank": {
    "enabled": true,
    "apiKey": "****abcd",
    "requestsThisHour": 12,
    "requestsRemaining": 288,
    "devicesFingerprinted": 15,
    "averageScore": 74,
    "cacheHitRate": 0.92
  }
}
```
