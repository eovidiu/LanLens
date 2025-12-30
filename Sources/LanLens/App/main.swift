import Foundation
import LanLensCore

@main
struct LanLensApp {
    static func main() async {
        let args = CommandLine.arguments

        // Check for --serve or -s flag
        if args.contains("--serve") || args.contains("-s") {
            await runServer()
            return
        }

        // Check for --help or -h flag
        if args.contains("--help") || args.contains("-h") {
            printUsage()
            return
        }

        // Default: run discovery scan
        await runDiscoveryScan()
    }

    static func printUsage() {
        print("""
        LanLens - Network Scanner & Smart Device Detector

        USAGE:
            lanlens [OPTIONS]

        OPTIONS:
            --serve, -s       Start the REST API server
            --port <PORT>     API server port (default: 8080)
            --host <HOST>     API server host (default: 127.0.0.1)
            --token <TOKEN>   Authentication token for API
            --help, -h        Show this help message

        EXAMPLES:
            lanlens                     # Run discovery scan
            lanlens --serve             # Start API server on localhost:8080
            lanlens -s --port 3000      # Start API server on port 3000
            lanlens -s --token secret   # Start with auth token

        API ENDPOINTS:
            GET  /health                    Health check
            GET  /api/devices               List all devices
            GET  /api/devices/smart         List smart devices
            GET  /api/devices/:mac          Get device by MAC
            GET  /api/discover/arp          Get ARP table
            POST /api/discover/passive      Run passive discovery
            POST /api/discover/dnssd        Run dns-sd discovery
            POST /api/scan/ports/:mac       Scan ports for device
            POST /api/scan/quick            Quick scan all devices
            POST /api/scan/full             Full scan all devices
            GET  /api/scan/nmap-status      Check nmap availability
            GET  /api/tools                 Check tool status
        """)
    }

    static func runServer() async {
        print("""
        ╔═══════════════════════════════════════╗
        ║     LanLens - REST API Server         ║
        ╚═══════════════════════════════════════╝
        """)

        let args = CommandLine.arguments

        // Parse arguments
        var port = 8080
        var host = "127.0.0.1"
        var token: String? = nil

        for i in 0..<args.count {
            if args[i] == "--port" && i + 1 < args.count {
                port = Int(args[i + 1]) ?? 8080
            }
            if args[i] == "--host" && i + 1 < args.count {
                host = args[i + 1]
            }
            if args[i] == "--token" && i + 1 < args.count {
                token = args[i + 1]
            }
        }

        // Check tools first
        print("\n📋 Checking available tools...")
        let toolReport = await ToolChecker.shared.checkAllTools()
        print(toolReport.summary)

        guard toolReport.allRequiredAvailable else {
            print("\n❌ Missing required tools. Exiting.")
            return
        }

        // Start API server
        let config = APIServer.Config(host: host, port: port, authToken: token)
        let server = APIServer(config: config)

        do {
            try await server.run()
        } catch {
            print("❌ Server failed: \(error)")
        }
    }

    static func runDiscoveryScan() async {
        print("""
        ╔═══════════════════════════════════════╗
        ║         LanLens - Network Scanner     ║
        ╚═══════════════════════════════════════╝
        """)

        // Check tools
        print("\n📋 Checking available tools...")
        let toolReport = await ToolChecker.shared.checkAllTools()
        print(toolReport.summary)

        guard toolReport.allRequiredAvailable else {
            print("\n❌ Missing required tools. Exiting.")
            return
        }

        // Get current ARP table
        print("\n🔍 Reading ARP table...")
        do {
            let entries = try await ARPScanner.shared.getARPTable()
            print("Found \(entries.count) devices in ARP table")

            for entry in entries {
                let vendor = MACVendorLookup.shared.lookup(mac: entry.mac) ?? "Unknown"
                print("  • \(entry.ip.padding(toLength: 15, withPad: " ", startingAt: 0)) \(entry.mac) (\(vendor))")
            }
        } catch {
            print("❌ ARP scan failed: \(error)")
        }

        // Start passive discovery (NWBrowser + SSDP)
        print("\n📡 Starting passive discovery (mDNS + SSDP)...")
        print("   Listening for 5 seconds...\n")

        await DiscoveryManager.shared.startPassiveDiscovery { device, updateType in
            let emoji = device.deviceType.emoji
            let score = device.smartScore > 0 ? " [Smart: \(device.smartScore)]" : ""
            print("   \(updateType == .discovered ? "🆕" : "🔄") \(emoji) \(device.displayName) - \(device.ip)\(score)")

            if !device.services.isEmpty {
                for service in device.services {
                    print("      └─ \(service.type): \(service.name)")
                }
            }
        }

        // Run for 5 seconds
        try? await Task.sleep(for: .seconds(5))

        await DiscoveryManager.shared.stopPassiveDiscovery()

        // Now run dns-sd based discovery (more reliable)
        print("\n🔬 Running dns-sd discovery (command-line based)...")
        print("   This may take a few seconds...\n")

        await DiscoveryManager.shared.runDNSSDDiscovery(duration: 5.0) { device, updateType in
            let emoji = device.deviceType.emoji
            let score = device.smartScore > 0 ? " [Smart: \(device.smartScore)]" : ""
            print("   \(updateType == .discovered ? "🆕" : "🔄") \(emoji) \(device.displayName) - \(device.ip)\(score)")

            if let hostname = device.hostname {
                print("      └─ hostname: \(hostname)")
            }
            for service in device.services {
                print("      └─ \(service.type): \(service.name)")
            }
        }

        // Summary
        let allDevices = await DiscoveryManager.shared.getAllDevices()
        let smartDevices = await DiscoveryManager.shared.getSmartDevices()

        print("\n" + String(repeating: "─", count: 50))
        print("📊 Summary:")
        print("   Total devices seen: \(allDevices.count)")
        print("   Smart devices: \(smartDevices.count)")

        if !smartDevices.isEmpty {
            print("\n🧠 Smart devices detected:")
            for device in smartDevices {
                print("   \(device.deviceType.emoji) \(device.displayName)")
                print("      IP: \(device.ip)")
                print("      Score: \(device.smartScore)/100")
                for signal in device.smartSignals {
                    print("      • \(signal.description)")
                }
            }
        }

        print("\n✅ Done.")
    }
}
