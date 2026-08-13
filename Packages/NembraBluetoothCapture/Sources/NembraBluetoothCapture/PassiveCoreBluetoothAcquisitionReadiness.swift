/// Pure one-shot readiness state for a selected target's CoreBluetooth
/// acquisition pass. Ongoing notifications are intentionally not operations:
/// readiness means the finite service/topology/read/subscription setup drained
/// successfully for the current connection/topology generation.
struct PassiveCoreBluetoothAcquisitionReadiness: Sendable {
    struct OperationToken: Hashable, Sendable {
        let generation: UInt64
        let identifier: UInt64
    }

    enum Phase: Equatable, Sendable {
        case noTarget
        case awaitingConnection
        case acquiring
        case ready
        /// A connection attempt reached a terminal transport outcome before any
        /// complete GATT acquisition existed. The connection evidence is useful,
        /// but missing topology must never be interpreted as authoritative absence.
        case terminalWithoutGattAcquisition
    }

    enum StateError: Swift.Error, Equatable, Sendable {
        case generationExhausted
        case operationIdentifierExhausted
        case acquisitionNotActive
        case acquisitionAlreadyActive
        case acquisitionNotPermitted(Phase)
        case invalidChildOperationCount
    }

    private(set) var phase: Phase = .noTarget
    private(set) var generation: UInt64 = 0
    private var nextOperationIdentifier: UInt64 = 1
    private var pendingOperations: Set<OperationToken> = []

    var isReady: Bool {
        phase == .ready
    }

    var isIncomplete: Bool {
        switch phase {
        case .noTarget, .awaitingConnection, .acquiring, .terminalWithoutGattAcquisition:
            true
        case .ready:
            false
        }
    }

    var pendingOperationCount: Int {
        pendingOperations.count
    }

    mutating func beginTargetSession() {
        pendingOperations.removeAll()
        phase = .awaitingConnection
    }

    /// Every explicit connection/reconnection attempt blocks artifact acceptance
    /// until that attempt reaches a fully drained acquisition pass.
    mutating func beginConnectionAttempt() {
        pendingOperations.removeAll()
        phase = .awaitingConnection
    }

    /// Marks a terminal connection outcome that produced no complete GATT pass.
    /// Raw connection evidence may still exist in the recorder, but callers must
    /// keep analysis/export qualified or unavailable because topology is unknown.
    mutating func finishWithoutGattAcquisition() {
        pendingOperations.removeAll()
        phase = .terminalWithoutGattAcquisition
    }

    /// Starts a fresh finite acquisition only from a lifecycle state where
    /// CoreBluetooth callbacks can be attributed without pretending software has
    /// a request-generation identity the platform does not provide.
    ///
    /// Allowed:
    /// - `.awaitingConnection` after the selected attempt actually connects;
    /// - `.ready` for a quiescent topology invalidation/reacquisition.
    ///
    /// Rejected:
    /// - `.acquiring`, because unresolved callbacks remain in flight;
    /// - `.noTarget`, because there is no selected target session;
    /// - `.terminalWithoutGattAcquisition`, which requires a new explicit
    ///   connection attempt before another acquisition can begin.
    mutating func startAcquisition() throws {
        switch phase {
        case .awaitingConnection, .ready:
            break
        case .acquiring:
            throw StateError.acquisitionAlreadyActive
        case .noTarget, .terminalWithoutGattAcquisition:
            throw StateError.acquisitionNotPermitted(phase)
        }
        guard pendingOperations.isEmpty else {
            throw StateError.acquisitionAlreadyActive
        }
        guard generation != UInt64.max else {
            throw StateError.generationExhausted
        }
        generation += 1
        phase = .acquiring
    }

    mutating func beginOperation() throws -> OperationToken {
        guard phase == .acquiring else {
            throw StateError.acquisitionNotActive
        }
        guard nextOperationIdentifier != UInt64.max else {
            throw StateError.operationIdentifierExhausted
        }

        let token = OperationToken(
            generation: generation,
            identifier: nextOperationIdentifier
        )
        nextOperationIdentifier += 1
        pendingOperations.insert(token)
        return token
    }

    /// Returns false for a stale/unknown operation rather than allowing it to
    /// complete the current acquisition generation accidentally.
    @discardableResult
    mutating func completeOperation(_ token: OperationToken) -> Bool {
        guard token.generation == generation,
              pendingOperations.remove(token) != nil else { return false }

        if pendingOperations.isEmpty {
            phase = .ready
        }
        return true
    }

    /// Atomically replaces one in-flight parent operation with zero or more
    /// child operations in the same generation. This prevents recursive GATT
    /// discovery from momentarily entering `.ready` between completing a parent
    /// callback and registering the child async work it spawned.
    ///
    /// Returns nil for a stale/unknown parent without mutating current readiness.
    mutating func completeOperation(
        _ token: OperationToken,
        startingChildOperations childOperationCount: Int
    ) throws -> [OperationToken]? {
        guard childOperationCount >= 0 else {
            throw StateError.invalidChildOperationCount
        }
        guard phase == .acquiring,
              token.generation == generation,
              pendingOperations.contains(token) else { return nil }

        if childOperationCount > 0 {
            let count = UInt64(childOperationCount)
            guard nextOperationIdentifier <= UInt64.max - count else {
                throw StateError.operationIdentifierExhausted
            }
        }

        pendingOperations.remove(token)
        var children: [OperationToken] = []
        children.reserveCapacity(childOperationCount)

        for _ in 0..<childOperationCount {
            let child = OperationToken(
                generation: generation,
                identifier: nextOperationIdentifier
            )
            nextOperationIdentifier += 1
            pendingOperations.insert(child)
            children.append(child)
        }

        if pendingOperations.isEmpty {
            phase = .ready
        }
        return children
    }
}
