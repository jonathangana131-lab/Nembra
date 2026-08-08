@preconcurrency import CoreBluetooth
import Foundation

/// Foreground-only producer for the bounded candidate catalogs consumed by
/// `PassiveBluetoothPowerCycleTargetCorrelation`.
///
/// Each successful observation window owns a newly-created `CBCentralManager`
/// and delegate lifetime. A later window never restarts scanning on the prior
/// manager. This gives delayed callbacks from a retired window a different
/// object authority than the next window instead of pretending `stopScan()` is
/// a documented callback-flush barrier.
///
/// The producer remains software research tooling:
/// - it performs broad discovery only;
/// - it never connects, reads, subscribes, or writes characteristic values;
/// - it never interprets names, RSSI, services, payloads, or Tuya semantics;
/// - it does not authenticate a scooter or make CoreBluetooth UUIDs permanent;
/// - a failed/cancelled window permanently invalidates this series so callers
///   must construct a fresh producer and restart the physical correlation flow.
@MainActor
public final class ForegroundCoreBluetoothCandidateObservationProducer {
    public struct WindowPolicy: Equatable, Sendable {
        /// Maximum time to wait for this newly-created central to report a usable
        /// powered-on state. This is caller-owned experiment policy; Nembra does
        /// not invent a physical ES80 default.
        public let radioReadinessTimeoutNanoseconds: UInt64

        /// Duration of the actual broad-scan observation window after the fresh
        /// central reports `.poweredOn`. This is experiment policy, not evidence
        /// of scooter advertisement cadence or latency.
        public let observationDurationNanoseconds: UInt64

        public init(
            radioReadinessTimeoutNanoseconds: UInt64,
            observationDurationNanoseconds: UInt64
        ) {
            self.radioReadinessTimeoutNanoseconds = radioReadinessTimeoutNanoseconds
            self.observationDurationNanoseconds = observationDurationNanoseconds
        }
    }

    public enum ProducerError: Error, Equatable, Sendable, LocalizedError {
        case invalidRadioReadinessTimeout
        case invalidObservationDuration
        case windowAlreadyActive
        case seriesInvalidated
        case windowSequenceExhausted
        case bluetoothPoweredOff
        case bluetoothUnauthorized
        case bluetoothUnsupported
        case radioReadinessTimedOut
        case bluetoothBecameUnavailable
        case cancelled
        case snapshotConstructionFailed

        public var errorDescription: String? {
            switch self {
            case .invalidRadioReadinessTimeout:
                "The candidate observation readiness timeout must be greater than zero."
            case .invalidObservationDuration:
                "The candidate observation duration must be greater than zero."
            case .windowAlreadyActive:
                "A candidate observation window is already active."
            case .seriesInvalidated:
                "This candidate observation series is no longer authoritative. Start a new series."
            case .windowSequenceExhausted:
                "The candidate observation sequence is exhausted. Start a new series."
            case .bluetoothPoweredOff:
                "Bluetooth is powered off. Start a new correlation series after Bluetooth is ready."
            case .bluetoothUnauthorized:
                "Bluetooth permission is unavailable."
            case .bluetoothUnsupported:
                "This device does not support the required Bluetooth central role."
            case .radioReadinessTimedOut:
                "Bluetooth did not become ready inside the bounded observation preflight."
            case .bluetoothBecameUnavailable:
                "Bluetooth became unavailable during the candidate observation window."
            case .cancelled:
                "The candidate observation window was cancelled. Start a new correlation series."
            case .snapshotConstructionFailed:
                "Nembra could not seal the candidate observation snapshot."
            }
        }
    }

    private var seriesState = PassiveCoreBluetoothCandidateObservationSeriesState()
    private var activeWindow: PassiveCoreBluetoothCandidateObservationWindowRun?

    public init() {}

    /// Opaque software provenance shared by successful windows from this exact
    /// producer lifetime. It is inspectable for diagnostics but cannot be minted
    /// by app/UI callers.
    public var observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity {
        seriesState.identity
    }

    public var isInvalidated: Bool {
        seriesState.isInvalidated
    }

    public var isObservingWindow: Bool {
        activeWindow != nil
    }

    /// Capture one bounded candidate catalog using a fresh central-manager
    /// authority. Successful calls from one producer receive strictly increasing
    /// local sequence values under one opaque series identity.
    ///
    /// Any error invalidates the whole series. The caller must discard prior
    /// windows and begin the OFF₁ -> ON₁ -> OFF₂ -> ON₂ experiment again with a
    /// newly-created producer rather than patching around a gap.
    public func observeWindow(
        policy: WindowPolicy
    ) async throws -> PassiveBluetoothCandidateObservationSnapshot {
        guard policy.radioReadinessTimeoutNanoseconds > 0 else {
            throw ProducerError.invalidRadioReadinessTimeout
        }
        guard policy.observationDurationNanoseconds > 0 else {
            throw ProducerError.invalidObservationDuration
        }
        guard activeWindow == nil else {
            throw ProducerError.windowAlreadyActive
        }

        let issued: PassiveCoreBluetoothCandidateObservationSeriesState.IssuedWindow
        do {
            issued = try seriesState.issueWindow()
        } catch let error as PassiveCoreBluetoothCandidateObservationSeriesState.StateError {
            switch error {
            case .invalidated:
                throw ProducerError.seriesInvalidated
            case .sequenceExhausted:
                seriesState.invalidate()
                throw ProducerError.windowSequenceExhausted
            }
        }

        let run = PassiveCoreBluetoothCandidateObservationWindowRun(
            observationSeriesIdentity: issued.identity,
            windowSequence: issued.sequence,
            policy: policy
        )
        activeWindow = run
        defer { activeWindow = nil }

        do {
            return try await run.execute()
        } catch let error as ProducerError {
            seriesState.invalidate()
            throw error
        } catch {
            seriesState.invalidate()
            throw ProducerError.snapshotConstructionFailed
        }
    }

    /// Explicit cancellation is fail-closed. The currently active window stops
    /// accepting evidence immediately, and this producer can never be reused for
    /// later windows in the same correlation series.
    public func cancelActiveWindow() {
        guard let activeWindow else { return }
        seriesState.invalidate()
        activeWindow.cancel()
    }
}

/// Package-local chronology state used by the live producer. The identity is one
/// software-series scope spanning multiple deliberately isolated window-manager
/// lifetimes; each physical window still gets a fresh `CBCentralManager` below.
struct PassiveCoreBluetoothCandidateObservationSeriesState: Sendable {
    enum StateError: Error, Equatable, Sendable {
        case invalidated
        case sequenceExhausted
    }

    struct IssuedWindow: Equatable, Sendable {
        let identity: PassiveBluetoothCandidateObservationSeriesIdentity
        let sequence: PassiveBluetoothCandidateObservationWindowSequence
    }

    let identity: PassiveBluetoothCandidateObservationSeriesIdentity
    private(set) var nextSequenceRawValue: UInt64
    private(set) var isInvalidated: Bool

    init(
        identity: PassiveBluetoothCandidateObservationSeriesIdentity = .init(),
        nextSequenceRawValue: UInt64 = 1,
        isInvalidated: Bool = false
    ) {
        self.identity = identity
        self.nextSequenceRawValue = nextSequenceRawValue
        self.isInvalidated = isInvalidated
    }

    mutating func issueWindow() throws -> IssuedWindow {
        guard !isInvalidated else {
            throw StateError.invalidated
        }

        let current = nextSequenceRawValue
        let increment = current.addingReportingOverflow(1)
        guard !increment.overflow else {
            throw StateError.sequenceExhausted
        }

        nextSequenceRawValue = increment.partialValue
        return .init(
            identity: identity,
            sequence: .init(rawValue: current)
        )
    }

    mutating func invalidate() {
        isInvalidated = true
    }
}

/// Conservative merge for repeated discovery callbacks inside one window.
/// Explicit `false` dominates because the correlation policy must never upgrade
/// a candidate to selectable after CoreBluetooth has reported it non-connectable.
/// Explicit `true` dominates only missing metadata; missing metadata never becomes
/// a fabricated positive connectability measurement.
struct PassiveCoreBluetoothCandidateObservationCatalog: Equatable, Sendable {
    private enum ConnectabilityEvidence: Equatable, Sendable {
        case unknown
        case connectable
        case nonConnectable

        init(_ value: Bool?) {
            switch value {
            case .some(true): self = .connectable
            case .some(false): self = .nonConnectable
            case .none: self = .unknown
            }
        }

        func merged(with newer: Self) -> Self {
            if self == .nonConnectable || newer == .nonConnectable {
                return .nonConnectable
            }
            if self == .connectable || newer == .connectable {
                return .connectable
            }
            return .unknown
        }

        var optionalBool: Bool? {
            switch self {
            case .unknown: nil
            case .connectable: true
            case .nonConnectable: false
            }
        }
    }

    private var evidenceByIdentifier: [UUID: ConnectabilityEvidence] = [:]

    mutating func observe(identifier: UUID, isConnectable: Bool?) {
        let newer = ConnectabilityEvidence(isConnectable)
        if let existing = evidenceByIdentifier[identifier] {
            evidenceByIdentifier[identifier] = existing.merged(with: newer)
        } else {
            evidenceByIdentifier[identifier] = newer
        }
    }

    var candidates: [PassiveBluetoothCandidateObservationSnapshot.Candidate] {
        evidenceByIdentifier
            .map { identifier, evidence in
                .init(id: identifier, isConnectable: evidence.optionalBool)
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

@MainActor
private final class PassiveCoreBluetoothCandidateObservationWindowRun: NSObject {
    private enum Phase: Equatable {
        case waitingForRadio
        case scanning
        case finished
    }

    private let observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity
    private let windowSequence: PassiveBluetoothCandidateObservationWindowSequence
    private let policy: ForegroundCoreBluetoothCandidateObservationProducer.WindowPolicy

    private var phase: Phase = .waitingForRadio
    private var catalog = PassiveCoreBluetoothCandidateObservationCatalog()
    private var continuation: CheckedContinuation<PassiveBluetoothCandidateObservationSnapshot, Error>?
    private var readinessTimeoutTask: Task<Void, Never>?
    private var observationTimeoutTask: Task<Void, Never>?

    /// Lazy creation ensures `self` is fully initialized before CoreBluetooth can
    /// retain the delegate relationship and schedule state callbacks.
    private lazy var centralManager: CBCentralManager = {
        CBCentralManager(delegate: self, queue: nil)
    }()

    init(
        observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity,
        windowSequence: PassiveBluetoothCandidateObservationWindowSequence,
        policy: ForegroundCoreBluetoothCandidateObservationProducer.WindowPolicy
    ) {
        self.observationSeriesIdentity = observationSeriesIdentity
        self.windowSequence = windowSequence
        self.policy = policy
        super.init()
    }

    func execute() async throws -> PassiveBluetoothCandidateObservationSnapshot {
        let manager = centralManager

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation

                if Task.isCancelled {
                    finish(.failure(ForegroundCoreBluetoothCandidateObservationProducer.ProducerError.cancelled))
                    return
                }

                armReadinessTimeout()
                handleCentralState(manager.state, from: manager)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancel()
            }
        }
    }

    func cancel() {
        finish(.failure(ForegroundCoreBluetoothCandidateObservationProducer.ProducerError.cancelled))
    }

    private func handleCentralState(_ state: CBManagerState, from manager: CBCentralManager) {
        guard manager === centralManager, phase != .finished else { return }

        if phase == .scanning {
            guard state == .poweredOn else {
                finish(.failure(
                    ForegroundCoreBluetoothCandidateObservationProducer.ProducerError
                        .bluetoothBecameUnavailable
                ))
                return
            }
            return
        }

        switch state {
        case .poweredOn:
            beginScan(using: manager)
        case .poweredOff:
            finish(.failure(
                ForegroundCoreBluetoothCandidateObservationProducer.ProducerError.bluetoothPoweredOff
            ))
        case .unauthorized:
            finish(.failure(
                ForegroundCoreBluetoothCandidateObservationProducer.ProducerError.bluetoothUnauthorized
            ))
        case .unsupported:
            finish(.failure(
                ForegroundCoreBluetoothCandidateObservationProducer.ProducerError.bluetoothUnsupported
            ))
        case .unknown, .resetting:
            break
        @unknown default:
            finish(.failure(
                ForegroundCoreBluetoothCandidateObservationProducer.ProducerError
                    .bluetoothBecameUnavailable
            ))
        }
    }

    private func beginScan(using manager: CBCentralManager) {
        guard phase == .waitingForRadio,
              manager === centralManager,
              manager.state == .poweredOn else { return }

        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = nil
        phase = .scanning
        manager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        armObservationTimeout()
    }

    private func armReadinessTimeout() {
        readinessTimeoutTask?.cancel()
        let timeout = policy.radioReadinessTimeoutNanoseconds
        readinessTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.finish(.failure(
                ForegroundCoreBluetoothCandidateObservationProducer.ProducerError
                    .radioReadinessTimedOut
            ))
        }
    }

    private func armObservationTimeout() {
        observationTimeoutTask?.cancel()
        let duration = policy.observationDurationNanoseconds
        observationTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.sealSuccessfulWindow()
        }
    }

    private func sealSuccessfulWindow() {
        guard phase == .scanning else { return }

        do {
            let snapshot = try PassiveBluetoothCandidateObservationSnapshot(
                observationSeriesIdentity: observationSeriesIdentity,
                windowSequence: windowSequence,
                candidates: catalog.candidates
            )
            finish(.success(snapshot))
        } catch {
            finish(.failure(
                ForegroundCoreBluetoothCandidateObservationProducer.ProducerError
                    .snapshotConstructionFailed
            ))
        }
    }

    private func finish(
        _ result: Result<PassiveBluetoothCandidateObservationSnapshot, Error>
    ) {
        guard phase != .finished else { return }

        phase = .finished
        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = nil
        observationTimeoutTask?.cancel()
        observationTimeoutTask = nil

        let manager = centralManager
        if manager.isScanning {
            manager.stopScan()
        }
        manager.delegate = nil

        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    private static func connectability(
        from advertisementData: [String: Any]
    ) -> Bool? {
        if let number = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber {
            return number.boolValue
        }
        if let value = advertisementData[CBAdvertisementDataIsConnectable] as? Bool {
            return value
        }
        return nil
    }
}

extension PassiveCoreBluetoothCandidateObservationWindowRun: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handleCentralState(central.state, from: central)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard phase == .scanning,
              central === centralManager,
              central.state == .poweredOn,
              central.isScanning else { return }

        catalog.observe(
            identifier: peripheral.identifier,
            isConnectable: Self.connectability(from: advertisementData)
        )
    }
}
