import Foundation

/// Represents a network scanning session with metadata and results tracking
///
/// A scan session tracks the lifecycle of a discovery operation, including
/// timing, device counts, and any errors encountered during the scan.
public struct ScanSession: Identifiable, Sendable, Codable, Equatable {
    
    // MARK: - Properties
    
    /// Unique identifier for this scan session
    public let id: UUID
    
    /// When the scan started
    public let startTime: Date
    
    /// Type of scan being performed
    public let type: ScanType
    
    /// When the scan completed (nil if still running)
    public var endTime: Date?
    
    /// Number of new devices discovered during this scan
    public var discoveredCount: Int
    
    /// Number of existing devices that were updated
    public var updatedCount: Int
    
    /// Errors encountered during the scan
    public var errors: [ScanError]
    
    // MARK: - Computed Properties
    
    /// Duration of the scan in seconds, or nil if still running
    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    
    /// Whether the scan has completed
    public var isComplete: Bool {
        endTime != nil
    }
    
    /// Whether the scan completed without errors
    public var isSuccessful: Bool {
        isComplete && errors.isEmpty
    }
    
    /// Total number of devices affected (discovered + updated)
    public var totalDevicesAffected: Int {
        discoveredCount + updatedCount
    }
    
    /// Human-readable duration string
    public var formattedDuration: String? {
        guard let duration = duration else { return nil }
        
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1f sec", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
    
    // MARK: - Initialization
    
    /// Create a new scan session
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if not provided)
    ///   - startTime: When the scan started (defaults to now)
    ///   - type: The type of scan being performed
    ///   - endTime: When the scan ended (nil if still running)
    ///   - discoveredCount: Number of new devices found
    ///   - updatedCount: Number of devices updated
    ///   - errors: Any errors encountered
    public init(
        id: UUID = UUID(),
        startTime: Date = Date(),
        type: ScanType,
        endTime: Date? = nil,
        discoveredCount: Int = 0,
        updatedCount: Int = 0,
        errors: [ScanError] = []
    ) {
        self.id = id
        self.startTime = startTime
        self.type = type
        self.endTime = endTime
        self.discoveredCount = discoveredCount
        self.updatedCount = updatedCount
        self.errors = errors
    }
    
    // MARK: - Mutation Methods
    
    /// Mark the session as complete
    /// - Parameter time: The completion time (defaults to now)
    /// - Returns: A new session with the end time set
    public func completed(at time: Date = Date()) -> ScanSession {
        var copy = self
        copy.endTime = time
        return copy
    }
    
    /// Add a discovered device to the count
    /// - Returns: A new session with incremented discovered count
    public func withDiscoveredDevice() -> ScanSession {
        var copy = self
        copy.discoveredCount += 1
        return copy
    }
    
    /// Add an updated device to the count
    /// - Returns: A new session with incremented updated count
    public func withUpdatedDevice() -> ScanSession {
        var copy = self
        copy.updatedCount += 1
        return copy
    }
    
    /// Add an error to the session
    /// - Parameter error: The error to add
    /// - Returns: A new session with the error appended
    public func withError(_ error: ScanError) -> ScanSession {
        var copy = self
        copy.errors.append(error)
        return copy
    }
}

// MARK: - Scan Type

extension ScanSession {
    
    /// The type of network scan being performed
    public enum ScanType: String, Sendable, Codable, CaseIterable {
        /// Quick scan - ARP table + common ports only
        case quick
        /// Full scan - ARP sweep + all ports + deep fingerprinting
        case full
        /// Passive scan - mDNS/SSDP listening only
        case passive
        
        /// Human-readable name for the scan type
        public var displayName: String {
            switch self {
            case .quick:
                return "Quick Scan"
            case .full:
                return "Full Scan"
            case .passive:
                return "Passive Discovery"
            }
        }
        
        /// Description of what this scan type does
        public var description: String {
            switch self {
            case .quick:
                return "Scans ARP table and common ports for fast discovery"
            case .full:
                return "Comprehensive scan with all ports and deep device fingerprinting"
            case .passive:
                return "Listens for device announcements without active probing"
            }
        }
        
        /// Estimated duration range in seconds
        public var estimatedDuration: ClosedRange<TimeInterval> {
            switch self {
            case .quick:
                return 5...15
            case .full:
                return 30...120
            case .passive:
                return 10...60
            }
        }
    }
}

// MARK: - Scan Error

extension ScanSession {
    
    /// An error that occurred during a scan
    public struct ScanError: Sendable, Codable, Equatable, Identifiable {
        
        /// Unique identifier for this error
        public var id: UUID { UUID() }
        
        /// When the error occurred
        public let timestamp: Date
        
        /// The source or component that generated the error
        public let source: String
        
        /// Human-readable error message
        public let message: String
        
        /// Error code if available
        public let code: Int?
        
        /// Whether this error is recoverable
        public let isRecoverable: Bool
        
        /// Create a scan error
        /// - Parameters:
        ///   - timestamp: When the error occurred (defaults to now)
        ///   - source: The component that generated the error
        ///   - message: Human-readable description
        ///   - code: Optional error code
        ///   - isRecoverable: Whether the scan can continue
        public init(
            timestamp: Date = Date(),
            source: String,
            message: String,
            code: Int? = nil,
            isRecoverable: Bool = true
        ) {
            self.timestamp = timestamp
            self.source = source
            self.message = message
            self.code = code
            self.isRecoverable = isRecoverable
        }
        
        /// Create from a Swift Error
        /// - Parameters:
        ///   - error: The error to wrap
        ///   - source: The component that generated the error
        ///   - isRecoverable: Whether the scan can continue
        public init(from error: Error, source: String, isRecoverable: Bool = true) {
            self.timestamp = Date()
            self.source = source
            self.message = error.localizedDescription
            self.code = (error as NSError).code
            self.isRecoverable = isRecoverable
        }
        
        // Custom Equatable (excluding id since it's computed)
        public static func == (lhs: ScanError, rhs: ScanError) -> Bool {
            lhs.timestamp == rhs.timestamp &&
            lhs.source == rhs.source &&
            lhs.message == rhs.message &&
            lhs.code == rhs.code &&
            lhs.isRecoverable == rhs.isRecoverable
        }
    }
}

// MARK: - Common Error Sources

extension ScanSession.ScanError {
    
    /// Common error source identifiers
    public enum Source {
        public static let arpScanner = "ARPScanner"
        public static let portScanner = "PortScanner"
        public static let mdnsListener = "MDNSListener"
        public static let ssdpListener = "SSDPListener"
        public static let fingerprinting = "Fingerprinting"
        public static let network = "Network"
        public static let permission = "Permission"
    }
    
    /// Create a network error
    public static func network(_ message: String, isRecoverable: Bool = true) -> ScanSession.ScanError {
        ScanSession.ScanError(source: Source.network, message: message, isRecoverable: isRecoverable)
    }
    
    /// Create a permission error
    public static func permission(_ message: String) -> ScanSession.ScanError {
        ScanSession.ScanError(source: Source.permission, message: message, isRecoverable: false)
    }
    
    /// Create a timeout error
    public static func timeout(source: String) -> ScanSession.ScanError {
        ScanSession.ScanError(source: source, message: "Operation timed out", isRecoverable: true)
    }
}
