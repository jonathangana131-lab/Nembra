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

    enum TerminalDisposition: Equatable, Sendable {
        case active(Attempt)
        case retired
        case ignored
    }

    enum StateError: Swift.Error, Equatable, Sendable {
        case targetNotSelected(UUID)
        case peripheralAwaitingTerminalCallback(UUID)
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
        if let activeAttempt {
            retiredPeripheralIdentifiers.insert(activeAttempt.peripheralIdentifier)
        }
        selectedTargetIdentifier = identifier
        activeAttempt = nil
        resetAcquisitionProvenance()
    }

    func validateCanBeginAttempt(for identifier: UUID) throws {
        guard !retiredPeripheralIdentifiers.contains(identifier) else {
            throw StateError.peripheralAwaitingTerminalCallback(identifier)
        }
        guard nextGeneration != UInt64.max else {
            throw StateError.generationExhausted
        }
    }

    /// Read-only retry quarantine truth for presentation/integration layers.
    /// A retired peripheral remains unavailable until CoreBluetooth delivers a
    /// terminal callback. Central availability changes alone are not treated as
    /// proof that an older same-identifier callback can no longer arrive.
    func isAwaitingTerminalCallback(for identifier: UUID) -> Bool {
        retiredPeripheralIdentifiers.contains(identifier)
    }

    mutating func beginAttempt(for identifier: UUID) throws -> Attempt {
        guard selectedTargetIdentifier == identifier else {
            throw StateError.targetNotSelected(identifier)
        }
        try validateCanBeginAttempt(for: identifier)

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
    /// emits either terminal callback (`didFailToConnect` or disconnect). This
    /// prevents a new attempt to the same object from being confused with
    /// callbacks still draining from the cancelled attempt.
    @discardableResult
    mutating func retireActiveAttempt() -> Attempt? {
        guard let activeAttempt else { return nil }
        retiredPeripheralIdentifiers.insert(activeAttempt.peripheralIdentifier)
        self.activeAttempt = nil
        resetAcquisitionProvenance()
        return activeAttempt
    }

    mutating func completeFailedConnection(from identifier: UUID) -> TerminalDisposition {
        completeTerminalCallback(from: identifier)
    }

    mutating func completeDisconnect(from identifier: UUID) -> TerminalDisposition {
        completeTerminalCallback(from: identifier)
    }

    /// CoreBluetooth becoming unavailable terminates the controller's usable
    /// transport, but this UUID-only reducer cannot prove that every terminal
    /// callback from the old attempt has already drained. Preserve fail-closed
    /// same-peripheral quarantine instead of allowing a fresh attempt to inherit
    /// an old callback. A terminal callback releases the quarantine normally.
    ///
    /// A future controller/object-epoch attribution layer may safely relax this
    /// for central states that *documentedly* invalidate old CBPeripheral objects;
    /// until then, requiring the real terminal boundary is the conservative rule.
    mutating func resetForCentralInvalidation() {
        if let activeAttempt {
            retiredPeripheralIdentifiers.insert(activeAttempt.peripheralIdentifier)
            self.activeAttempt = nil
        }
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

    private mutating func completeTerminalCallback(from identifier: UUID) -> TerminalDisposition {
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
}