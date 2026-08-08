@preconcurrency import CoreBluetooth
import Dispatch
import Foundation

/// One operator-declared phase of the repeated physical power-response experiment.
///
/// The phase name records intended procedure only. Nembra does not infer or attest the
/// scooter's real power state from this value.
public enum PassiveBluetoothPowerCycleObservationPhase: Int, CaseIterable, Equatable, Sendable {
    case firstPoweredOff
    case firstPoweredOn
    case secondPoweredOff
    case secondPoweredOn

    public var operatorExpectedPowerOn: Bool {
        switch self {
        case .firstPoweredOff, .secondPoweredOff:
            false
        case .firstPoweredOn, .secondPoweredOn:
            true
        }
    }
}

public enum PassiveBluetoothPowerCycleObservationSessionError: Error, Equatable, Sendable {
    case invalidMinimumWindowDuration
    case seriesComplete
    case seriesInvalidated
    case windowAlreadyActive
    case windowNotActive
    case bluetoothBecameUnavailable
    case minimumWindowDurationNotReached
    case nonMonotonicWindowClock
    case windowSequenceExhausted
}

/// Public progress intentionally exposes procedure state, never mutable evidence authority.
public struct PassiveBluetoothPowerCycleObservationProgress: Equatable, Sendable {
    public let phase: PassiveBluetoothPowerCycleObservationPhase
    public let isAwaitingBluetoothPower: Bool
    public let isScanning: Bool
    public let isSeriesInvalidated: Bool
    public let currentObservedCandidateCount: Int
    public let completedWindowCount: Int
}

/// Receipt-bounded metadata for one completed observation window.
///
/// This says only that Nembra accepted candidate callbacks between these two local uptime
/// receipts while the operator was expected to hold the named physical state. It is not
/// radio-time evidence and does not attest the scooter's physical power state.
public struct PassiveBluetoothPowerCycleObservationWindowReceipt: Equatable, Sendable {
    public let phase: PassiveBluetoothPowerCycleObservationPhase
    public let windowSequence: PassiveBluetoothCandidateObservationWindowSequence
    public let startedAtUptimeNanoseconds: UInt64
    public let endedAtUptimeNanoseconds: UInt64
    public let observedCandidateCount: Int
}

/// Final software result of one four-window observation series.
///
/// The correlation report remains physical-response correlation evidence only. A unique UUID
/// may be offered for explicit operator selection; it is not permanent scooter authentication.
public struct PassiveBluetoothPowerCycleObservationResult: Equatable, Sendable {
    public let windows: [PassiveBluetoothPowerCycleObservationWindowReceipt]
    public let correlation: PassiveBluetoothPowerCycleTargetCorrelationReport
}

/// Pure state machine that seals snapshots under one higher-level observation-series authority.
///
/// The CoreBluetooth transport for each window is deliberately outside this value. The live
/// session below replaces that transport for every window while retaining this one producer
/// authority, preventing callbacks from an old manager from being relabeled as a later window.
/// Any known window/transport failure invalidates this authority permanently so successful
/// earlier windows can never be patched into a later restarted experiment.
struct PassiveBluetoothPowerCycleObservationLedger: Sendable {
    private let minimumWindowDurationNanoseconds: UInt64
    private let observationSeriesIdentity = PassiveBluetoothCandidateObservationSeriesIdentity()
    private(set) var completedSnapshots: [PassiveBluetoothCandidateObservationSnapshot] = []
    private(set) var completedReceipts: [PassiveBluetoothPowerCycleObservationWindowReceipt] = []
    private(set) var isInvalidated = false
    private var nextWindowSequenceRawValue: UInt64 = 1

    init(minimumWindowDurationNanoseconds: UInt64) {
        precondition(minimumWindowDurationNanoseconds > 0)
        self.minimumWindowDurationNanoseconds = minimumWindowDurationNanoseconds
    }

    var nextPhase: PassiveBluetoothPowerCycleObservationPhase? {
        PassiveBluetoothPowerCycleObservationPhase(rawValue: completedSnapshots.count)
    }

    mutating func invalidate() {
        isInvalidated = true
    }

    mutating func completeWindow(
        phase: PassiveBluetoothPowerCycleObservationPhase,
        startedAtUptimeNanoseconds: UInt64,
        endedAtUptimeNanoseconds: UInt64,
        candidates: [PassiveBluetoothCandidateObservationSnapshot.Candidate]
    ) throws -> PassiveBluetoothPowerCycleObservationResult? {
        guard !isInvalidated else {
            throw PassiveBluetoothPowerCycleObservationSessionError.seriesInvalidated
        }
        guard let expectedPhase = nextPhase else {
            throw PassiveBluetoothPowerCycleObservationSessionError.seriesComplete
        }
        precondition(phase == expectedPhase, "Live producer may complete only its current phase")
        guard endedAtUptimeNanoseconds >= startedAtUptimeNanoseconds else {
            throw PassiveBluetoothPowerCycleObservationSessionError.nonMonotonicWindowClock
        }
        guard endedAtUptimeNanoseconds - startedAtUptimeNanoseconds >= minimumWindowDurationNanoseconds else {
            throw PassiveBluetoothPowerCycleObservationSessionError.minimumWindowDurationNotReached
        }
        guard nextWindowSequenceRawValue != UInt64.max else {
            isInvalidated = true
            throw PassiveBluetoothPowerCycleObservationSessionError.windowSequenceExhausted
        }

        let sequence = PassiveBluetoothCandidateObservationWindowSequence(
            rawValue: nextWindowSequenceRawValue
        )
        let snapshot = try PassiveBluetoothCandidateObservationSnapshot(
            observationSeriesIdentity: observationSeriesIdentity,
            windowSequence: sequence,
            candidates: candidates
        )
        let receipt = PassiveBluetoothPowerCycleObservationWindowReceipt(
            phase: phase,
            windowSequence: sequence,
            startedAtUptimeNanoseconds: startedAtUptimeNanoseconds,
            endedAtUptimeNanoseconds: endedAtUptimeNanoseconds,
            observedCandidateCount: snapshot.candidates.count
        )

        completedSnapshots.append(snapshot)
        completedReceipts.append(receipt)
        nextWindowSequenceRawValue += 1

        guard completedSnapshots.count == PassiveBluetoothPowerCycleObservationPhase.allCases.count else {
            return nil
        }

        let correlation = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: completedSnapshots[0],
            firstOn: completedSnapshots[1],
            secondOff: completedSnapshots[2],
            secondOn: completedSnapshots[3]
        )
        return PassiveBluetoothPowerCycleObservationResult(
            windows: completedReceipts,
            correlation: correlation
        )
    }
}

/// Foreground-only, read-only candidate-window producer for the repeated ES80 power-cycle
/// correlation experiment.
///
/// A single session is the software observation-series authority. Each bounded window owns a
/// **fresh `CBCentralManager` instance**. `didDiscover` identifies the manager that delivered
/// the callback, so callbacks from a retired window fail the exact-manager guard once a new
/// transport is active instead of being stamped with a fabricated local scan generation.
///
/// Any Bluetooth-authority failure or explicit operator abandonment permanently invalidates the
/// whole four-window series. The caller must construct a fresh session and restart at OFF₁;
/// already-completed windows are never reused across a known gap.
///
/// Safety / truth boundary:
/// - broad discovery only; no connection and no characteristic-value writes;
/// - local names, RSSI, services, short UUIDs, and product signatures never affect correlation;
/// - window phases are operator-declared expected power state, not physical attestation;
/// - a completed catalog contains callbacks accepted before the synchronous receipt cutoff;
/// - a unique repeated UUID is correlation evidence only, never permanent ES80 identity.
@MainActor
public final class PassiveBluetoothPowerCycleObservationSession: NSObject, CBCentralManagerDelegate {
    private struct CandidateState {
        let id: UUID
        var isConnectable: Bool?

        mutating func merge(isConnectable incoming: Bool?) {
            // Explicit non-connectable evidence dominates. Otherwise preserve explicit true over unknown.
            if isConnectable == false || incoming == false {
                isConnectable = false
            } else if isConnectable == true || incoming == true {
                isConnectable = true
            } else {
                isConnectable = nil
            }
        }
    }

    private var ledger: PassiveBluetoothPowerCycleObservationLedger
    private let minimumWindowDurationNanoseconds: UInt64
    private var activeManager: CBCentralManager?
    private var awaitingPoweredOn = false
    private var windowStartedAtUptimeNanoseconds: UInt64?
    private var candidatesByIdentifier: [UUID: CandidateState] = [:]
    private var finalResult: PassiveBluetoothPowerCycleObservationResult?
    private var lastWindowInvalidatedByBluetooth = false

    public init(minimumWindowDuration: TimeInterval) throws {
        guard minimumWindowDuration.isFinite,
              minimumWindowDuration > 0,
              minimumWindowDuration < Double(UInt64.max) / 1_000_000_000 else {
            throw PassiveBluetoothPowerCycleObservationSessionError.invalidMinimumWindowDuration
        }
        let nanosecondsDouble = (minimumWindowDuration * 1_000_000_000).rounded(.up)
        guard nanosecondsDouble.isFinite,
              nanosecondsDouble >= 1,
              nanosecondsDouble < Double(UInt64.max) else {
            throw PassiveBluetoothPowerCycleObservationSessionError.invalidMinimumWindowDuration
        }
        let nanoseconds = UInt64(nanosecondsDouble)

        minimumWindowDurationNanoseconds = nanoseconds
        ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: nanoseconds
        )
        super.init()
    }

    public var progress: PassiveBluetoothPowerCycleObservationProgress? {
        guard let phase = ledger.nextPhase else { return nil }
        return PassiveBluetoothPowerCycleObservationProgress(
            phase: phase,
            isAwaitingBluetoothPower: awaitingPoweredOn,
            isScanning: windowStartedAtUptimeNanoseconds != nil,
            isSeriesInvalidated: ledger.isInvalidated,
            currentObservedCandidateCount: candidatesByIdentifier.count,
            completedWindowCount: ledger.completedReceipts.count
        )
    }

    public var result: PassiveBluetoothPowerCycleObservationResult? {
        finalResult
    }

    /// Starts the next operator-declared window using a brand-new CoreBluetooth manager epoch.
    /// If the manager has not reported powered-on state yet, scanning begins only after that
    /// manager's own state callback says it is powered on. Terminal non-powered states invalidate
    /// the entire series without producing a snapshot.
    public func startCurrentWindow() throws {
        guard !ledger.isInvalidated else {
            throw PassiveBluetoothPowerCycleObservationSessionError.seriesInvalidated
        }
        guard ledger.nextPhase != nil, finalResult == nil else {
            throw PassiveBluetoothPowerCycleObservationSessionError.seriesComplete
        }
        guard activeManager == nil else {
            throw PassiveBluetoothPowerCycleObservationSessionError.windowAlreadyActive
        }

        candidatesByIdentifier.removeAll(keepingCapacity: true)
        windowStartedAtUptimeNanoseconds = nil
        lastWindowInvalidatedByBluetooth = false
        awaitingPoweredOn = true

        let manager = CBCentralManager(delegate: self, queue: .main, options: nil)
        activeManager = manager
        switch manager.state {
        case .poweredOn:
            beginScanIfAwaiting(on: manager)
        case .poweredOff, .unauthorized, .unsupported:
            invalidateCurrentTransportForBluetoothState(manager)
            throw PassiveBluetoothPowerCycleObservationSessionError.bluetoothBecameUnavailable
        case .unknown, .resetting:
            break
        @unknown default:
            invalidateCurrentTransportForBluetoothState(manager)
            throw PassiveBluetoothPowerCycleObservationSessionError.bluetoothBecameUnavailable
        }
    }

    /// Freezes the current receipt-bounded catalog. Calling this early fails without advancing
    /// phase or reusing the manager; the same window genuinely keeps scanning on the same manager
    /// until the minimum duration is satisfied.
    ///
    /// On success, the manager is retired synchronously before evidence is sealed. Any callback
    /// already queued from that manager reaches the delegate with a non-active manager identity
    /// and is rejected rather than leaking into the next window.
    @discardableResult
    public func finishCurrentWindow() throws -> PassiveBluetoothPowerCycleObservationResult? {
        guard !ledger.isInvalidated else {
            if lastWindowInvalidatedByBluetooth {
                throw PassiveBluetoothPowerCycleObservationSessionError.bluetoothBecameUnavailable
            }
            throw PassiveBluetoothPowerCycleObservationSessionError.seriesInvalidated
        }
        guard let manager = activeManager,
              manager.state == .poweredOn,
              let startedAt = windowStartedAtUptimeNanoseconds,
              let phase = ledger.nextPhase else {
            throw PassiveBluetoothPowerCycleObservationSessionError.windowNotActive
        }

        let endedAt = DispatchTime.now().uptimeNanoseconds
        guard endedAt >= startedAt else {
            retireCurrentTransport(manager, bluetoothFailure: false)
            throw PassiveBluetoothPowerCycleObservationSessionError.nonMonotonicWindowClock
        }
        guard endedAt - startedAt >= minimumWindowDurationNanoseconds else {
            throw PassiveBluetoothPowerCycleObservationSessionError.minimumWindowDurationNotReached
        }

        manager.stopScan()
        activeManager = nil
        awaitingPoweredOn = false
        windowStartedAtUptimeNanoseconds = nil

        let candidates = candidatesByIdentifier.values
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                PassiveBluetoothCandidateObservationSnapshot.Candidate(
                    id: $0.id,
                    isConnectable: $0.isConnectable
                )
            }
        candidatesByIdentifier.removeAll(keepingCapacity: true)

        do {
            let completed = try ledger.completeWindow(
                phase: phase,
                startedAtUptimeNanoseconds: startedAt,
                endedAtUptimeNanoseconds: endedAt,
                candidates: candidates
            )
            finalResult = completed
            return completed
        } catch {
            ledger.invalidate()
            throw error
        }
    }

    /// Explicit operator abandonment is a known experiment gap. It invalidates the whole series
    /// permanently; prior completed windows cannot be reused. Construct a fresh session and restart
    /// the physical OFF₁ -> ON₁ -> OFF₂ -> ON₂ procedure.
    public func abandonCurrentWindow() {
        guard activeManager != nil || awaitingPoweredOn || windowStartedAtUptimeNanoseconds != nil else {
            return
        }
        if let manager = activeManager {
            retireCurrentTransport(manager, bluetoothFailure: false)
        } else {
            ledger.invalidate()
            awaitingPoweredOn = false
            windowStartedAtUptimeNanoseconds = nil
            candidatesByIdentifier.removeAll(keepingCapacity: true)
        }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === activeManager else { return }

        switch central.state {
        case .poweredOn:
            beginScanIfAwaiting(on: central)
        case .unknown, .resetting:
            if windowStartedAtUptimeNanoseconds != nil {
                invalidateCurrentTransportForBluetoothState(central)
            }
        case .poweredOff, .unauthorized, .unsupported:
            invalidateCurrentTransportForBluetoothState(central)
        @unknown default:
            invalidateCurrentTransportForBluetoothState(central)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard !ledger.isInvalidated,
              central === activeManager,
              central.state == .poweredOn,
              windowStartedAtUptimeNanoseconds != nil else {
            return
        }

        let rawConnectable = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber
        let connectable = rawConnectable?.boolValue
        if var existing = candidatesByIdentifier[peripheral.identifier] {
            existing.merge(isConnectable: connectable)
            candidatesByIdentifier[peripheral.identifier] = existing
        } else {
            candidatesByIdentifier[peripheral.identifier] = CandidateState(
                id: peripheral.identifier,
                isConnectable: connectable
            )
        }
    }

    private func beginScanIfAwaiting(on manager: CBCentralManager) {
        guard !ledger.isInvalidated,
              manager === activeManager,
              awaitingPoweredOn,
              manager.state == .poweredOn,
              windowStartedAtUptimeNanoseconds == nil else {
            return
        }

        awaitingPoweredOn = false
        candidatesByIdentifier.removeAll(keepingCapacity: true)
        windowStartedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        manager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func invalidateCurrentTransportForBluetoothState(_ manager: CBCentralManager) {
        retireCurrentTransport(manager, bluetoothFailure: true)
    }

    private func retireCurrentTransport(
        _ manager: CBCentralManager,
        bluetoothFailure: Bool
    ) {
        guard manager === activeManager else { return }
        if windowStartedAtUptimeNanoseconds != nil {
            manager.stopScan()
        }
        ledger.invalidate()
        lastWindowInvalidatedByBluetooth = bluetoothFailure
        activeManager = nil
        awaitingPoweredOn = false
        windowStartedAtUptimeNanoseconds = nil
        candidatesByIdentifier.removeAll(keepingCapacity: true)
    }
}
