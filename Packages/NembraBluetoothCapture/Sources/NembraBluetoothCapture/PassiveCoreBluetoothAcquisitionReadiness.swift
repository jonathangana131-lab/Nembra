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
    }

    enum StateError: Swift.Error, Equatable, Sendable {
        case generationExhausted
        case operationIdentifierExhausted
        case acquisitionNotActive
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
        case .noTarget, .awaitingConnection, .acquiring:
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

    /// Starts a fresh finite acquisition generation, for example after connect
    /// or a GATT service invalidation. Callers should immediately register the
    /// root service-discovery operation before invoking CoreBluetooth.
    mutating func startAcquisition() throws {
        guard generation != UInt64.max else {
            throw StateError.generationExhausted
        }
        generation += 1
        pendingOperations.removeAll()
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
}
