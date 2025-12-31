import Foundation
import os.log

// MARK: - Log Categories

/// Categories for organizing log output
public enum LogCategory: String, CaseIterable, Sendable {
    case discovery = "Discovery"
    case fingerprinting = "Fingerprinting"
    case network = "Network"
    case persistence = "Persistence"
    case state = "State"
    case ssdp = "SSDP"
    case mdns = "mDNS"
    case arp = "ARP"
    case ports = "Ports"
    case api = "API"
    case cache = "Cache"
    case general = "General"
    case mdnsTXT = "mDNS-TXT"
    case portBanner = "PortBanner"
    case macAnalysis = "MACAnalysis"
    case security = "Security"
    case behavior = "Behavior"
}

// MARK: - File Log Configuration

/// Configuration for file-based logging
public struct FileLogConfig: Sendable {
    /// Path to the log file
    public let path: String

    /// Maximum size in bytes before rotation (default: 1MB)
    public let maxSize: UInt64

    /// Number of rotated logs to keep (default: 5)
    public let maxRotatedFiles: Int

    /// Default log path that Claude Code can easily read
    public static let defaultPath = "/tmp/lanlens.log"

    public init(
        path: String = FileLogConfig.defaultPath,
        maxSize: UInt64 = 1_048_576,  // 1MB
        maxRotatedFiles: Int = 5
    ) {
        self.path = path
        self.maxSize = maxSize
        self.maxRotatedFiles = maxRotatedFiles
    }
}

// MARK: - Trace Context

/// Context for correlating log entries across operations
public struct TraceContext: Sendable {
    public let scanId: String
    public let timestamp: Date
    
    public init(scanId: String = UUID().uuidString, timestamp: Date = Date()) {
        self.scanId = scanId
        self.timestamp = timestamp
    }
    
    /// Short scan ID for logging (first 8 characters)
    public var shortId: String {
        String(scanId.prefix(8))
    }
}

// MARK: - LanLens Logger

/// Unified logging infrastructure for LanLens
/// Uses OSLog as the backend with support for categories and trace context
/// Also writes to a file at /tmp/lanlens.log for easy debugging with Claude Code
public final class LanLensLogger: @unchecked Sendable {

    /// Shared instance for global access - file logging enabled by default
    public static let shared = LanLensLogger(
        fileLoggingEnabled: true,
        fileLogConfig: FileLogConfig()
    )

    private static let subsystem = "com.lanlens.core"

    /// OSLog instances per category
    private let loggers: [LogCategory: Logger]

    /// File-based logging configuration
    private let fileLoggingEnabled: Bool
    private let fileLogConfig: FileLogConfig

    /// Serial queue for thread-safe file operations
    private let fileQueue = DispatchQueue(label: "com.lanlens.logger.file", qos: .utility)

    /// Cached date formatter for performance (ISO8601 with milliseconds)
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Current trace context (thread-local storage for async contexts)
    @TaskLocal public static var currentTrace: TraceContext?

    /// Creates a logger with optional file logging
    /// - Parameters:
    ///   - fileLoggingEnabled: Whether to write logs to a file (default: true)
    ///   - fileLogConfig: Configuration for file logging
    public init(
        fileLoggingEnabled: Bool = true,
        fileLogConfig: FileLogConfig = FileLogConfig()
    ) {
        self.fileLoggingEnabled = fileLoggingEnabled
        self.fileLogConfig = fileLogConfig

        // Create OSLog instances for each category
        var loggers: [LogCategory: Logger] = [:]
        for category in LogCategory.allCases {
            loggers[category] = Logger(subsystem: Self.subsystem, category: category.rawValue)
        }
        self.loggers = loggers

        // Initialize log file if file logging is enabled
        if fileLoggingEnabled {
            initializeLogFile()
        }
    }

    /// Legacy initializer for backwards compatibility
    @available(*, deprecated, message: "Use init(fileLoggingEnabled:fileLogConfig:) instead")
    public convenience init(fileLoggingEnabled: Bool, logFilePath: String) {
        self.init(
            fileLoggingEnabled: fileLoggingEnabled,
            fileLogConfig: FileLogConfig(path: logFilePath)
        )
    }
    
    // MARK: - Public Logging Methods
    
    /// Log a debug message
    public func debug(_ message: String, category: LogCategory, trace: TraceContext? = nil) {
        let logger = loggers[category]!
        let formattedMessage = formatMessage(message, trace: trace ?? Self.currentTrace)
        logger.debug("\(formattedMessage, privacy: .public)")
        writeToFileIfEnabled(message, category: category, level: "DEBUG", trace: trace)
    }
    
    /// Log an info message
    public func info(_ message: String, category: LogCategory, trace: TraceContext? = nil) {
        let logger = loggers[category]!
        let formattedMessage = formatMessage(message, trace: trace ?? Self.currentTrace)
        logger.info("\(formattedMessage, privacy: .public)")
        writeToFileIfEnabled(message, category: category, level: "INFO", trace: trace)
    }
    
    /// Log a warning message
    public func warning(_ message: String, category: LogCategory, trace: TraceContext? = nil) {
        let logger = loggers[category]!
        let formattedMessage = formatMessage(message, trace: trace ?? Self.currentTrace)
        logger.warning("\(formattedMessage, privacy: .public)")
        writeToFileIfEnabled(message, category: category, level: "WARN", trace: trace)
    }
    
    /// Log an error message
    public func error(_ message: String, category: LogCategory, trace: TraceContext? = nil) {
        let logger = loggers[category]!
        let formattedMessage = formatMessage(message, trace: trace ?? Self.currentTrace)
        logger.error("\(formattedMessage, privacy: .public)")
        writeToFileIfEnabled(message, category: category, level: "ERROR", trace: trace)
    }
    
    /// Log with a specific OSLogType
    public func log(_ message: String, category: LogCategory, level: OSLogType, trace: TraceContext? = nil) {
        let logger = loggers[category]!
        let formattedMessage = formatMessage(message, trace: trace ?? Self.currentTrace)
        logger.log(level: level, "\(formattedMessage, privacy: .public)")
        
        let levelString: String
        switch level {
        case .debug: levelString = "DEBUG"
        case .info: levelString = "INFO"
        case .error: levelString = "ERROR"
        case .fault: levelString = "FAULT"
        default: levelString = "LOG"
        }
        writeToFileIfEnabled(message, category: category, level: levelString, trace: trace)
    }
    
    // MARK: - Private Helpers

    private func formatMessage(_ message: String, trace: TraceContext?) -> String {
        if let trace = trace {
            return "[\(trace.shortId)] \(message)"
        }
        return message
    }

    // MARK: - File Logging Implementation

    /// Initialize the log file with a header
    private func initializeLogFile() {
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            let path = self.fileLogConfig.path

            // Check if rotation is needed before writing
            self.rotateLogIfNeeded()

            // Write startup marker
            let header = """

            ================================================================================
            LanLens Log Started: \(self.dateFormatter.string(from: Date()))
            Log Path: \(path)
            ================================================================================

            """

            if let data = header.data(using: .utf8) {
                self.appendToLogFile(data)
            }
        }
    }

    /// Write a log entry to the file
    private func writeToFileIfEnabled(_ message: String, category: LogCategory, level: String, trace: TraceContext?) {
        guard fileLoggingEnabled else { return }

        // Capture the timestamp immediately on the calling thread for accuracy
        let timestamp = dateFormatter.string(from: Date())

        fileQueue.async { [weak self] in
            guard let self = self else { return }

            // Check for rotation before writing
            self.rotateLogIfNeeded()

            let tracePrefix = trace.map { "[\($0.shortId)] " } ?? ""
            let line = "[\(timestamp)] [\(level.padding(toLength: 5, withPad: " ", startingAt: 0))] [\(category.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0))] \(tracePrefix)\(message)\n"

            guard let data = line.data(using: .utf8) else { return }
            self.appendToLogFile(data)
        }
    }

    /// Append data to the log file (must be called on fileQueue)
    private func appendToLogFile(_ data: Data) {
        let path = fileLogConfig.path
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: path) {
            // Append to existing file
            if let handle = FileHandle(forWritingAtPath: path) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    // Fallback: try to recreate the file
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            }
        } else {
            // Create new file
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Rotate the log file if it exceeds the maximum size (must be called on fileQueue)
    private func rotateLogIfNeeded() {
        let path = fileLogConfig.path
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: path) else { return }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            let fileSize = attributes[.size] as? UInt64 ?? 0

            guard fileSize >= fileLogConfig.maxSize else { return }

            // Rotate existing log files
            // Delete oldest if we're at max
            let oldestPath = "\(path).\(fileLogConfig.maxRotatedFiles)"
            if fileManager.fileExists(atPath: oldestPath) {
                try? fileManager.removeItem(atPath: oldestPath)
            }

            // Shift existing rotated files
            for i in stride(from: fileLogConfig.maxRotatedFiles - 1, through: 1, by: -1) {
                let sourcePath = "\(path).\(i)"
                let destPath = "\(path).\(i + 1)"
                if fileManager.fileExists(atPath: sourcePath) {
                    try? fileManager.moveItem(atPath: sourcePath, toPath: destPath)
                }
            }

            // Move current log to .1
            let rotatedPath = "\(path).1"
            try fileManager.moveItem(atPath: path, toPath: rotatedPath)

            // Create new empty log file with rotation marker
            let rotationHeader = """
            ================================================================================
            Log rotated from: \(rotatedPath)
            Rotation time: \(dateFormatter.string(from: Date()))
            ================================================================================

            """
            try rotationHeader.data(using: .utf8)?.write(to: URL(fileURLWithPath: path))

        } catch {
            // If rotation fails, truncate the file to prevent unbounded growth
            try? "".data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Public File Log Utilities

    /// Returns the path to the current log file
    public var logFilePath: String {
        fileLogConfig.path
    }

    /// Clears all log files (current and rotated)
    public func clearAllLogs() {
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            let path = self.fileLogConfig.path
            let fileManager = FileManager.default

            // Remove current log
            try? fileManager.removeItem(atPath: path)

            // Remove rotated logs
            for i in 1...self.fileLogConfig.maxRotatedFiles {
                try? fileManager.removeItem(atPath: "\(path).\(i)")
            }

            // Reinitialize
            self.initializeLogFile()
        }
    }

    /// Flushes any pending log writes (useful before app termination)
    public func flush() {
        fileQueue.sync { }
    }
}

// MARK: - Global Convenience Functions

/// Global logger instance
public let Log: LanLensLogger = LanLensLogger.shared

/// Call this function early in app startup to ensure file logging is initialized
/// and writes a startup marker to the log file.
///
/// Example:
/// ```swift
/// // In your App's init() or applicationDidFinishLaunching()
/// initializeLogging()
/// ```
public func initializeLogging() {
    // Force initialization of the shared logger (creates log file with header)
    _ = Log
    Log.info("LanLens application starting - file logging to \(FileLogConfig.defaultPath)", category: .general)
}

/// Convenience function for debug logging
public func logDebug(_ message: String, category: LogCategory) {
    Log.debug(message, category: category)
}

/// Convenience function for info logging
public func logInfo(_ message: String, category: LogCategory) {
    Log.info(message, category: category)
}

/// Convenience function for warning logging
public func logWarning(_ message: String, category: LogCategory) {
    Log.warning(message, category: category)
}

/// Convenience function for error logging
public func logError(_ message: String, category: LogCategory) {
    Log.error(message, category: category)
}

// MARK: - Category-Specific Logging Extensions

extension LanLensLogger {
    
    /// Log a discovery-related message
    public func discovery(_ message: String, level: OSLogType = .info, trace: TraceContext? = nil) {
        log(message, category: .discovery, level: level, trace: trace)
    }
    
    /// Log a fingerprinting-related message
    public func fingerprinting(_ message: String, level: OSLogType = .info, trace: TraceContext? = nil) {
        log(message, category: .fingerprinting, level: level, trace: trace)
    }
    
    /// Log a network-related message
    public func network(_ message: String, level: OSLogType = .info, trace: TraceContext? = nil) {
        log(message, category: .network, level: level, trace: trace)
    }
    
    /// Log a persistence-related message
    public func persistence(_ message: String, level: OSLogType = .info, trace: TraceContext? = nil) {
        log(message, category: .persistence, level: level, trace: trace)
    }
    
    /// Log a state-related message
    public func state(_ message: String, level: OSLogType = .info, trace: TraceContext? = nil) {
        log(message, category: .state, level: level, trace: trace)
    }
}
