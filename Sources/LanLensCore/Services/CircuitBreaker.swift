import Foundation

/// Circuit breaker pattern implementation for resilient service calls
///
/// The circuit breaker protects services by tracking failures and temporarily
/// blocking requests when a failure threshold is exceeded. This prevents
/// cascading failures and allows services time to recover.
///
/// States:
/// - `closed`: Normal operation, requests pass through
/// - `open`: Service is failing, requests are blocked
/// - `halfOpen`: Testing recovery, limited requests allowed
public actor CircuitBreaker {
    
    // MARK: - Types
    
    /// The current state of the circuit breaker
    public enum State: Sendable, Equatable {
        /// Normal operation - requests pass through
        case closed
        /// Failing - requests are rejected immediately
        case open
        /// Testing recovery - limited requests allowed
        case halfOpen
    }
    
    /// Configuration for the circuit breaker
    public struct Configuration: Sendable {
        /// Number of consecutive failures before opening the circuit
        public let failureThreshold: Int
        /// Time to wait before attempting recovery (seconds)
        public let resetTimeout: TimeInterval
        /// Maximum attempts allowed in half-open state before deciding outcome
        public let halfOpenMaxAttempts: Int
        
        public init(
            failureThreshold: Int = 5,
            resetTimeout: TimeInterval = 60,
            halfOpenMaxAttempts: Int = 3
        ) {
            self.failureThreshold = failureThreshold
            self.resetTimeout = resetTimeout
            self.halfOpenMaxAttempts = halfOpenMaxAttempts
        }
        
        /// Default configuration suitable for most network services
        public static let `default` = Configuration()
        
        /// Aggressive configuration for critical services
        public static let aggressive = Configuration(
            failureThreshold: 3,
            resetTimeout: 30,
            halfOpenMaxAttempts: 2
        )
        
        /// Lenient configuration for less critical services
        public static let lenient = Configuration(
            failureThreshold: 10,
            resetTimeout: 120,
            halfOpenMaxAttempts: 5
        )
    }
    
    // MARK: - Properties
    
    /// Configuration for this circuit breaker instance
    public let configuration: Configuration
    
    /// Optional identifier for logging and debugging
    public let name: String
    
    /// Current state of the circuit
    private var state: State = .closed
    
    /// Number of consecutive failures in closed state
    private var failureCount: Int = 0
    
    /// Timestamp of the last failure (used for reset timeout)
    private var lastFailureTime: Date?
    
    /// Number of attempts made in half-open state
    private var halfOpenAttempts: Int = 0
    
    /// Number of successful attempts in half-open state
    private var halfOpenSuccesses: Int = 0
    
    // MARK: - Initialization
    
    /// Create a circuit breaker with custom configuration
    /// - Parameters:
    ///   - name: Identifier for this circuit breaker
    ///   - configuration: Configuration parameters
    public init(name: String = "default", configuration: Configuration = .default) {
        self.name = name
        self.configuration = configuration
    }
    
    // MARK: - Public Methods
    
    /// Record a successful operation
    ///
    /// In closed state: resets failure count
    /// In half-open state: tracks success, may close circuit if threshold met
    public func recordSuccess() {
        switch state {
        case .closed:
            // Reset failure count on success
            failureCount = 0
            
        case .halfOpen:
            halfOpenSuccesses += 1
            halfOpenAttempts += 1
            
            // If we've had enough successes, close the circuit
            if halfOpenSuccesses >= configuration.halfOpenMaxAttempts {
                transitionTo(.closed)
            }
            
        case .open:
            // Should not happen - open circuit rejects requests
            break
        }
    }
    
    /// Record a failed operation
    ///
    /// In closed state: increments failure count, may open circuit
    /// In half-open state: immediately opens circuit
    public func recordFailure() {
        lastFailureTime = Date()
        
        switch state {
        case .closed:
            failureCount += 1
            if failureCount >= configuration.failureThreshold {
                transitionTo(.open)
            }
            
        case .halfOpen:
            // Any failure in half-open immediately opens the circuit
            transitionTo(.open)
            
        case .open:
            // Already open, just update last failure time
            break
        }
    }
    
    /// Check if a request can be executed
    ///
    /// - Returns: `true` if the request should proceed, `false` if it should be rejected
    public func canExecute() -> Bool {
        switch state {
        case .closed:
            return true
            
        case .open:
            // Check if reset timeout has elapsed
            if let lastFailure = lastFailureTime {
                let elapsed = Date().timeIntervalSince(lastFailure)
                if elapsed >= configuration.resetTimeout {
                    transitionTo(.halfOpen)
                    return true
                }
            }
            return false
            
        case .halfOpen:
            // Allow limited attempts in half-open state
            return halfOpenAttempts < configuration.halfOpenMaxAttempts
        }
    }
    
    /// Get the current state of the circuit breaker
    public func currentState() -> State {
        // Check for automatic state transitions due to timeout
        if state == .open, let lastFailure = lastFailureTime {
            let elapsed = Date().timeIntervalSince(lastFailure)
            if elapsed >= configuration.resetTimeout {
                transitionTo(.halfOpen)
            }
        }
        return state
    }
    
    /// Manually reset the circuit breaker to closed state
    ///
    /// Use this for administrative recovery or testing
    public func reset() {
        transitionTo(.closed)
    }
    
    /// Execute an operation with circuit breaker protection
    ///
    /// - Parameter operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Throws: `CircuitBreakerError.open` if circuit is open, or rethrows operation errors
    public func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        guard canExecute() else {
            throw CircuitBreakerError.open(name: name)
        }
        
        do {
            let result = try await operation()
            recordSuccess()
            return result
        } catch {
            recordFailure()
            throw error
        }
    }
    
    /// Get statistics about the circuit breaker
    public func statistics() -> Statistics {
        Statistics(
            state: state,
            failureCount: failureCount,
            lastFailureTime: lastFailureTime,
            halfOpenAttempts: halfOpenAttempts,
            halfOpenSuccesses: halfOpenSuccesses
        )
    }
    
    // MARK: - Private Methods
    
    private func transitionTo(_ newState: State) {
        let oldState = state
        state = newState
        
        switch newState {
        case .closed:
            failureCount = 0
            halfOpenAttempts = 0
            halfOpenSuccesses = 0
            lastFailureTime = nil
            
        case .open:
            halfOpenAttempts = 0
            halfOpenSuccesses = 0
            
        case .halfOpen:
            halfOpenAttempts = 0
            halfOpenSuccesses = 0
        }
        
        // Could add logging here if needed
        _ = oldState // Silence unused warning, useful for debugging
    }
}

// MARK: - Supporting Types

extension CircuitBreaker {
    
    /// Errors thrown by the circuit breaker
    public enum CircuitBreakerError: Error, Sendable {
        /// The circuit is open and rejecting requests
        case open(name: String)
    }
    
    /// Statistics snapshot for monitoring
    public struct Statistics: Sendable {
        public let state: State
        public let failureCount: Int
        public let lastFailureTime: Date?
        public let halfOpenAttempts: Int
        public let halfOpenSuccesses: Int
        
        /// Time remaining until the circuit transitions from open to half-open
        public func timeUntilReset(timeout: TimeInterval) -> TimeInterval? {
            guard state == .open, let lastFailure = lastFailureTime else {
                return nil
            }
            let elapsed = Date().timeIntervalSince(lastFailure)
            let remaining = timeout - elapsed
            return remaining > 0 ? remaining : 0
        }
    }
}
