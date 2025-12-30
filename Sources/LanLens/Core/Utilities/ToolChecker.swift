import Foundation

/// Checks availability of external network tools
public actor ToolChecker {
    public static let shared = ToolChecker()

    private init() {}

    public struct ToolStatus: Sendable {
        public let name: String
        public let isAvailable: Bool
        public let path: String?
        public let version: String?
        public let isRequired: Bool
        public let installHint: String?
    }

    public struct ToolReport: Sendable {
        public let tools: [ToolStatus]
        public let allRequiredAvailable: Bool
        public let missingRequired: [String]
        public let missingOptional: [String]
    }

    /// Check all required and optional tools
    public func checkAllTools() async -> ToolReport {
        async let arpStatus = checkARP()
        async let dnsSdStatus = checkDNSSD()
        async let nmapStatus = checkNmap()
        async let arpScanStatus = checkArpScan()

        let tools = await [arpStatus, dnsSdStatus, nmapStatus, arpScanStatus]

        let missingRequired = tools.filter { $0.isRequired && !$0.isAvailable }.map(\.name)
        let missingOptional = tools.filter { !$0.isRequired && !$0.isAvailable }.map(\.name)

        return ToolReport(
            tools: tools,
            allRequiredAvailable: missingRequired.isEmpty,
            missingRequired: missingRequired,
            missingOptional: missingOptional
        )
    }

    /// Check arp command (always present on macOS)
    private func checkARP() async -> ToolStatus {
        let path = "/usr/sbin/arp"
        let exists = FileManager.default.fileExists(atPath: path)

        return ToolStatus(
            name: "arp",
            isAvailable: exists,
            path: exists ? path : nil,
            version: nil,
            isRequired: true,
            installHint: "Should be pre-installed on macOS"
        )
    }

    /// Check dns-sd command (always present on macOS)
    private func checkDNSSD() async -> ToolStatus {
        let path = "/usr/bin/dns-sd"
        let exists = FileManager.default.fileExists(atPath: path)

        return ToolStatus(
            name: "dns-sd",
            isAvailable: exists,
            path: exists ? path : nil,
            version: nil,
            isRequired: true,
            installHint: "Should be pre-installed on macOS"
        )
    }

    /// Check nmap (optional, for port scanning)
    private func checkNmap() async -> ToolStatus {
        let shell = ShellExecutor.shared

        // Check common locations
        let possiblePaths = [
            "/usr/local/bin/nmap",
            "/opt/homebrew/bin/nmap",
            "/usr/bin/nmap"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                let version = await getNmapVersion(path: path)
                return ToolStatus(
                    name: "nmap",
                    isAvailable: true,
                    path: path,
                    version: version,
                    isRequired: false,
                    installHint: "brew install nmap"
                )
            }
        }

        // Try which
        if await shell.commandExists("nmap") {
            do {
                let whichResult = try await shell.execute("which", arguments: ["nmap"])
                let path = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let version = await getNmapVersion(path: path)
                return ToolStatus(
                    name: "nmap",
                    isAvailable: true,
                    path: path,
                    version: version,
                    isRequired: false,
                    installHint: "brew install nmap"
                )
            } catch {
                // Fall through to not available
            }
        }

        return ToolStatus(
            name: "nmap",
            isAvailable: false,
            path: nil,
            version: nil,
            isRequired: false,
            installHint: "brew install nmap"
        )
    }

    /// Check arp-scan (optional, for faster ARP scanning)
    private func checkArpScan() async -> ToolStatus {
        let shell = ShellExecutor.shared

        let possiblePaths = [
            "/usr/local/bin/arp-scan",
            "/opt/homebrew/bin/arp-scan"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return ToolStatus(
                    name: "arp-scan",
                    isAvailable: true,
                    path: path,
                    version: nil,
                    isRequired: false,
                    installHint: "brew install arp-scan"
                )
            }
        }

        if await shell.commandExists("arp-scan") {
            do {
                let whichResult = try await shell.execute("which", arguments: ["arp-scan"])
                let path = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                return ToolStatus(
                    name: "arp-scan",
                    isAvailable: true,
                    path: path,
                    version: nil,
                    isRequired: false,
                    installHint: "brew install arp-scan"
                )
            } catch {
                // Fall through
            }
        }

        return ToolStatus(
            name: "arp-scan",
            isAvailable: false,
            path: nil,
            version: nil,
            isRequired: false,
            installHint: "brew install arp-scan"
        )
    }

    private func getNmapVersion(path: String) async -> String? {
        do {
            let result = try await ShellExecutor.shared.execute(path: path, arguments: ["--version"])
            if result.succeeded {
                // First line usually contains version
                let firstLine = result.stdout.components(separatedBy: "\n").first ?? ""
                // Extract version number
                if let range = firstLine.range(of: #"\d+\.\d+(\.\d+)?"#, options: .regularExpression) {
                    return String(firstLine[range])
                }
            }
        } catch {
            // Ignore
        }
        return nil
    }
}

// MARK: - Report Formatting

extension ToolChecker.ToolReport {
    public var summary: String {
        var lines: [String] = []

        lines.append("Tool Status:")
        lines.append(String(repeating: "-", count: 50))

        for tool in tools {
            let status = tool.isAvailable ? "✓" : "✗"
            let required = tool.isRequired ? "(required)" : "(optional)"
            var line = "\(status) \(tool.name) \(required)"

            if let version = tool.version {
                line += " v\(version)"
            }

            if !tool.isAvailable, let hint = tool.installHint {
                line += " - \(hint)"
            }

            lines.append(line)
        }

        lines.append(String(repeating: "-", count: 50))

        if allRequiredAvailable {
            lines.append("All required tools available.")
        } else {
            lines.append("⚠️  Missing required: \(missingRequired.joined(separator: ", "))")
        }

        if !missingOptional.isEmpty {
            lines.append("ℹ️  Missing optional: \(missingOptional.joined(separator: ", "))")
            lines.append("   (Some features will be limited)")
        }

        return lines.joined(separator: "\n")
    }
}
