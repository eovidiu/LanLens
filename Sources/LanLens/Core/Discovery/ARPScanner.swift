import Foundation

/// Discovers devices using ARP table and scanning
public actor ARPScanner {
    public static let shared = ARPScanner()

    private let shell = ShellExecutor.shared

    private init() {}

    public struct ARPEntry: Sendable {
        public let ip: String
        public let mac: String
        public let interface: String?
    }

    /// Get current ARP table entries
    public func getARPTable() async throws -> [ARPEntry] {
        let result = try await shell.execute(path: "/usr/sbin/arp", arguments: ["-a"])

        guard result.succeeded else {
            throw ARPScannerError.commandFailed(result.stderr)
        }

        return parseARPOutput(result.stdout)
    }

    /// Ping sweep a subnet to populate ARP table, then read it
    public func scanSubnet(_ subnet: String) async throws -> [ARPEntry] {
        // Parse subnet (e.g., "192.168.1.0/24")
        guard let (baseIP, prefixLength) = parseSubnet(subnet) else {
            throw ARPScannerError.invalidSubnet(subnet)
        }

        // For /24, we ping .1 through .254
        guard prefixLength >= 24 else {
            throw ARPScannerError.subnetTooLarge(subnet)
        }

        let ipBase = baseIP.components(separatedBy: ".").prefix(3).joined(separator: ".")

        // Ping sweep using concurrent tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 1...254 {
                let ip = "\(ipBase).\(i)"
                group.addTask {
                    // Quick ping, ignore result - just populating ARP table
                    _ = try? await self.shell.execute(
                        path: "/sbin/ping",
                        arguments: ["-c", "1", "-W", "100", ip],
                        timeout: 2
                    )
                }
            }
        }

        // Small delay for ARP table to settle
        try await Task.sleep(for: .milliseconds(500))

        // Now read the populated ARP table
        return try await getARPTable()
    }

    /// Parse arp -a output
    /// Format: hostname (ip) at mac on interface [ifscope ...]
    /// Example: ? (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]
    private func parseARPOutput(_ output: String) -> [ARPEntry] {
        var entries: [ARPEntry] = []

        let lines = output.components(separatedBy: "\n")
        let pattern = #"\(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\) at ([0-9a-fA-F:]+) on (\w+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return entries
        }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)

            if let match = regex.firstMatch(in: line, range: range) {
                if let ipRange = Range(match.range(at: 1), in: line),
                   let macRange = Range(match.range(at: 2), in: line),
                   let ifaceRange = Range(match.range(at: 3), in: line) {

                    let ip = String(line[ipRange])
                    let mac = String(line[macRange])
                    let iface = String(line[ifaceRange])

                    // Skip incomplete entries (mac shows as "(incomplete)")
                    guard mac.contains(":") else { continue }

                    entries.append(ARPEntry(ip: ip, mac: mac.uppercased(), interface: iface))
                }
            }
        }

        return entries
    }

    /// Parse subnet notation
    private func parseSubnet(_ subnet: String) -> (baseIP: String, prefixLength: Int)? {
        let parts = subnet.components(separatedBy: "/")
        guard parts.count == 2,
              let prefixLength = Int(parts[1]),
              prefixLength >= 0 && prefixLength <= 32 else {
            return nil
        }

        return (parts[0], prefixLength)
    }
}

// MARK: - Errors

public enum ARPScannerError: Error, LocalizedError {
    case commandFailed(String)
    case invalidSubnet(String)
    case subnetTooLarge(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let stderr):
            return "ARP command failed: \(stderr)"
        case .invalidSubnet(let subnet):
            return "Invalid subnet format: \(subnet)"
        case .subnetTooLarge(let subnet):
            return "Subnet too large (max /24): \(subnet)"
        }
    }
}
