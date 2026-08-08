import Foundation

/// Binds finite CoreBluetooth acquisition callbacks to readiness tokens without
/// depending on UUID-only GATT identity. Object identity keeps duplicate UUID
/// instances distinct until the separate fail-closed identity registry decides
/// whether the durable v2 schema can represent them.
struct PassiveCoreBluetoothAcquisitionOperationLedger {
    enum OperationKey: Hashable {
        case services
        case includedServices(ObjectIdentifier)
        case characteristics(ObjectIdentifier)
        case descriptors(ObjectIdentifier)
        case read(ObjectIdentifier)
        case subscription(ObjectIdentifier)
    }

    enum LedgerError: Swift.Error, Equatable {
        case operationAlreadyPending
        case operationNotPending
    }

    private(set) var readiness = PassiveCoreBluetoothAcquisitionReadiness()
    private var tokenByOperation: [OperationKey: PassiveCoreBluetoothAcquisitionReadiness.OperationToken] = [:]

    var isReady: Bool { readiness.isReady }
    var isIncomplete: Bool { readiness.isIncomplete }
    var phase: PassiveCoreBluetoothAcquisitionReadiness.Phase { readiness.phase }
    var pendingOperationCount: Int { readiness.pendingOperationCount }

    mutating func beginTargetSession() {
        tokenByOperation.removeAll()
        readiness.beginTargetSession()
    }

    mutating func beginConnectionAttempt() {
        tokenByOperation.removeAll()
        readiness.beginConnectionAttempt()
    }

    mutating func finishWithoutGattAcquisition() {
        tokenByOperation.removeAll()
        readiness.finishWithoutGattAcquisition()
    }

    /// Starts a root service-discovery operation transactionally. A rejected
    /// lifecycle transition must leave both readiness tokens and operation-key
    /// attribution unchanged; otherwise an unresolved CoreBluetooth callback
    /// would become unrepresentable merely because software attempted a restart.
    mutating func beginAcquisition() throws {
        var candidateReadiness = readiness
        try candidateReadiness.startAcquisition()
        let rootToken = try candidateReadiness.beginOperation()

        readiness = candidateReadiness
        tokenByOperation.removeAll(keepingCapacity: true)
        tokenByOperation[.services] = rootToken
    }

    /// Atomically completes one callback operation and registers every finite
    /// child callback that must drain before the acquisition can become ready.
    /// Child keys are validated before readiness changes so duplicate scheduling
    /// cannot leave the ledger half-mutated.
    mutating func complete(
        _ operation: OperationKey,
        starting children: [OperationKey] = []
    ) throws {
        guard let token = tokenByOperation[operation] else {
            throw LedgerError.operationNotPending
        }
        guard Set(children).count == children.count,
              children.allSatisfy({ tokenByOperation[$0] == nil || $0 == operation }) else {
            throw LedgerError.operationAlreadyPending
        }

        guard let childTokens = try readiness.completeOperation(
            token,
            startingChildOperations: children.count
        ) else {
            throw LedgerError.operationNotPending
        }

        tokenByOperation.removeValue(forKey: operation)
        for (child, childToken) in zip(children, childTokens) {
            tokenByOperation[child] = childToken
        }
    }

    func isPending(_ operation: OperationKey) -> Bool {
        tokenByOperation[operation] != nil
    }
}
