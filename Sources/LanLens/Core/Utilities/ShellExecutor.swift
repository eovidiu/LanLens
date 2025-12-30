import Foundation

/// Executes shell commands and captures output
public actor ShellExecutor {
    public static let shared = ShellExecutor()

    private init() {}

    public struct CommandResult: Sendable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String

        public var succeeded: Bool { exitCode == 0 }
    }

    /// Execute a command and return the result
    public func execute(_ command: String, arguments: [String] = [], timeout: TimeInterval = 30) async throws -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()

                // Set up timeout
                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(timeout))
                    if process.isRunning {
                        process.terminate()
                    }
                }

                process.waitUntilExit()
                timeoutTask.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let result = CommandResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? ""
                )

                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Execute a command at a specific path
    public func execute(path: String, arguments: [String] = [], timeout: TimeInterval = 30) async throws -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()

                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(timeout))
                    if process.isRunning {
                        process.terminate()
                    }
                }

                process.waitUntilExit()
                timeoutTask.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let result = CommandResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? ""
                )

                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Check if a command exists in PATH
    public func commandExists(_ command: String) async -> Bool {
        do {
            let result = try await execute("which", arguments: [command])
            return result.succeeded && !result.stdout.isEmpty
        } catch {
            return false
        }
    }
}
