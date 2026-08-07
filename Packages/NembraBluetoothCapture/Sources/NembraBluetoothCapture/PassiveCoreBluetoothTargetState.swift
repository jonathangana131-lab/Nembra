import Foundation

/// Pure attribution state for the foreground passive CoreBluetooth adapter.
///
/// This type deliberately knows nothing about CoreBluetooth object identity or
/// scooter protocol semantics. It answers only whether an asynchronous callback
/// belongs to the currently selected research target/connection attempt and
/// tracks provenance for read/subscription callbacks that CoreBluetooth itself
/// does not label strongly enough.
struct PassiveCoreBluetoothTargetState: Sendable {
    struct Attempt: Equatable, Sendable {
        let peripheralIdentifier: UUID
        let generation: UInt64
    }

    struct AttributeKey: Hashable, Sendable {
        let peripheralIdentifier: UUID
        let serviceUUID: String
        let characteristicUUID: String
    }

    enum DisconnectDisposition: Equatable, Sendable {
        case active(Attempt)
        case retired
        case ignored
    }

    enum StateError: Swift.Error, Equatable, Sendable {
        case targetNotSelected(UUID)
        case peripheralAwaitingDisconnect(UUID)
        case generationExhausted
    }

    private(set) var selectedTargetIdentifier: UUID?
    private(set) var activeAttempt: Attempt?

    private var nextGeneration: UInt64 = 1
    private var retiredPeripheralIdentifiers: Set<UUID> = []
    private var pendingReads: Set<AttributeKey> = []
    private var pendingSubscriptionRequests: [AttributeKey: Bool] = [:]

    mutating func selectTarget(_ identifier: UUID) {
        guard selectedTargetIdentifier != identifier else { return }
        selectedTargetIdentifier = identifier
        activeAttempt = nil
        resetAcquisitionProvenance()
    }

    mutating func beginAttempt(for identifier: UUID) throws -> Attempt {
        guard selectedTargetIdentifier == identifier else {
            throw StateError.targetNotSelected(identifier)
        }
        guard !retiredPeripheralIdentifiers.contains(identifier) else {
            throw StateError.peripheralAwaitingDisconnect(identifier)
        }
        guard nextGeneration != UInt64.max else {
            throw StateError.generationExhausted
        }

        let attempt = Attempt(
            peripheralIdentifier: identifier,
            generation: nextGeneration
        )
        nextGeneration += 1
        activeAttempt = attempt
        resetAcquisitionProvenance()
        return attempt
    }

    func acceptsActiveCallback(from identifier: UUID) -> Bool {
        activeAttempt?.peripheralIdentifier == identifier
    }

    /// Explicit cancellation/timeout retires the attempt until CoreBluetooth
    /// confirms a disconnect. This prevents a new attempt to the same object from
    /// being confused with callbacks still draining from the cancelled attempt.
    @discardableResult
    mutating func retireActiveAttempt() -> Attempt? {
        guard let activeAttempt else { return nil }
        retiredPeripheralIdentifiers.insert(activeAttempt.peripheralIdentifier)
        self.activeAttempt = nil
        resetAcquisitionProvenance()
        return activeAttempt
    }

    @discardableResult
    mutating func completeFailedConnection(from identifier: UUID) -> Attempt? {
        guard let activeAttempt,
              activeAttempt.peripheralIdentifier == identifier else { return nil }
        self.activeAttempt = nil
        resetAcquisitionProvenance()
        return activeAttempt
    }

    mutating func completeDisconnect(from identifier: UUID) -> DisconnectDisposition {
        if let activeAttempt,
           activeAttempt.peripheralIdentifier == identifier {
            self.activeAttempt = nil
            resetAcquisitionProvenance()
            return .active(activeAttempt)
        }

        if retiredPeripheralIdentifiers.remove(identifier) != nil {
            return .retired
        }

        return .ignored
    }

    /// A central-manager reset/power transition invalidates all CoreBluetooth
    /// connection objects, so no cancelled-attempt quarantine survives it.
    mutating func resetForCentralInvalidation() {
        activeAttempt = nil
        retiredPeripheralIdentifiers.removeAll()
        resetAcquisitionProvenance()
    }

    mutating func markReadRequested(_ key: AttributeKey) {
        pendingReads.insert(key)
    }

    mutating func consumeReadRequest(_ key: AttributeKey) -> Bool {
        pendingReads.remove(key) != nil
    }

    mutating func markSubscriptionRequested(_ key: AttributeKey, enabled: Bool) {
        pendingSubscriptionRequests[key] = enabled
    }

    mutating func consumeSubscriptionRequest(_ key: AttributeKey) -> Bool? {
        pendingSubscriptionRequests.removeValue(forKey: key)
    }

    mutating func resetAcquisitionProvenance() {
        pendingReads.removeAll()
        pendingSubscriptionRequests.removeAll()
    }
}
