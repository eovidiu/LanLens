import Foundation

// MARK: - Export Service Protocol

/// Protocol for device export operations
public protocol ExportServiceProtocol: Sendable {
    /// Export devices to the specified format
    func exportDevices(_ devices: [Device], format: ExportFormat) async throws -> Data
    
    /// Export devices to a file at the specified directory
    func exportToFile(_ devices: [Device], format: ExportFormat, directory: URL) async throws -> URL
}

// MARK: - Export Format

/// Supported export formats
public enum ExportFormat: String, Sendable, CaseIterable {
    case json = "json"
    case csv = "csv"
    
    /// File extension for this format
    public var fileExtension: String {
        rawValue
    }
    
    /// MIME type for this format
    public var mimeType: String {
        switch self {
        case .json: return "application/json"
        case .csv: return "text/csv"
        }
    }
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .json: return "JSON"
        case .csv: return "CSV"
        }
    }
}

// MARK: - Export Error

/// Errors that can occur during export
public enum ExportError: Error, Sendable {
    case encodingFailed(String)
    case fileWriteFailed(String)
    case invalidDirectory
    case noDevices
}

extension ExportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let reason):
            return "Failed to encode data: \(reason)"
        case .fileWriteFailed(let reason):
            return "Failed to write file: \(reason)"
        case .invalidDirectory:
            return "Invalid export directory"
        case .noDevices:
            return "No devices to export"
        }
    }
}

// MARK: - Export Service

/// Actor-based service for exporting device inventory data
public actor ExportService: ExportServiceProtocol {
    
    /// Shared instance
    public static let shared = ExportService()
    
    /// JSON encoder configured for export
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    
    /// Date formatter for CSV timestamps
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    public init() {}
    
    // MARK: - Public Methods
    
    /// Export devices to the specified format as Data
    /// - Parameters:
    ///   - devices: Array of devices to export
    ///   - format: Export format (JSON or CSV)
    /// - Returns: Encoded data in the specified format
    public func exportDevices(_ devices: [Device], format: ExportFormat) async throws -> Data {
        Log.info("Exporting \(devices.count) devices as \(format.displayName)", category: .export)
        
        let data: Data
        switch format {
        case .json:
            data = try exportAsJSON(devices)
        case .csv:
            data = try exportAsCSV(devices)
        }
        
        Log.info("Export complete: \(data.count) bytes", category: .export)
        return data
    }
    
    /// Export devices to a file in the specified directory
    /// - Parameters:
    ///   - devices: Array of devices to export
    ///   - format: Export format (JSON or CSV)
    ///   - directory: Directory to save the file
    /// - Returns: URL of the created file
    public func exportToFile(_ devices: [Device], format: ExportFormat, directory: URL) async throws -> URL {
        guard !devices.isEmpty else {
            throw ExportError.noDevices
        }
        
        let data = try await exportDevices(devices, format: format)
        
        // Generate filename with timestamp
        let timestamp = dateFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "")
        let filename = "lanlens-export-\(timestamp).\(format.fileExtension)"
        let fileURL = directory.appendingPathComponent(filename)
        
        Log.debug("Writing export to: \(fileURL.path)", category: .export)
        
        do {
            try data.write(to: fileURL, options: .atomic)
            Log.info("Successfully wrote export file: \(fileURL.lastPathComponent)", category: .export)
            return fileURL
        } catch {
            Log.error("Failed to write export file: \(error.localizedDescription)", category: .export)
            throw ExportError.fileWriteFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Methods
    
    /// Export devices as JSON
    private func exportAsJSON(_ devices: [Device]) throws -> Data {
        let wrapper = ExportWrapper(
            exportDate: Date(),
            deviceCount: devices.count,
            devices: devices
        )
        
        do {
            return try jsonEncoder.encode(wrapper)
        } catch {
            Log.error("JSON encoding failed: \(error.localizedDescription)", category: .export)
            throw ExportError.encodingFailed(error.localizedDescription)
        }
    }
    
    /// Export devices as CSV
    private func exportAsCSV(_ devices: [Device]) throws -> Data {
        var csvLines: [String] = []
        
        // Header row
        let headers = [
            "MAC",
            "IP",
            "Hostname",
            "Vendor",
            "Type",
            "Label",
            "SmartScore",
            "FirstSeen",
            "LastSeen",
            "Online"
        ]
        csvLines.append(headers.joined(separator: ","))
        
        // Data rows
        for device in devices {
            let row = [
                escapeCSV(device.mac),
                escapeCSV(device.ip),
                escapeCSV(device.hostname ?? ""),
                escapeCSV(device.vendor ?? ""),
                escapeCSV(device.deviceType.rawValue),
                escapeCSV(device.userLabel ?? ""),
                String(device.smartScore),
                dateFormatter.string(from: device.firstSeen),
                dateFormatter.string(from: device.lastSeen),
                device.isOnline ? "true" : "false"
            ]
            csvLines.append(row.joined(separator: ","))
        }
        
        let csvString = csvLines.joined(separator: "\n")
        
        guard let data = csvString.data(using: .utf8) else {
            throw ExportError.encodingFailed("Failed to encode CSV as UTF-8")
        }
        
        return data
    }
    
    /// Escape a value for CSV (handles commas, quotes, and newlines)
    private func escapeCSV(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        
        if needsQuoting {
            // Double any existing quotes and wrap in quotes
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        
        return value
    }
}

// MARK: - Export Wrapper

/// Wrapper for JSON export with metadata
private struct ExportWrapper: Codable, Sendable {
    let exportDate: Date
    let deviceCount: Int
    let devices: [Device]
}
