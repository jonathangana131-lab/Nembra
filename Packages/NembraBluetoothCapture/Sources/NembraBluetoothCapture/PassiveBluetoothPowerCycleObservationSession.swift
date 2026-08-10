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
    case scanReadinessPending
    case scanReadinessTimedOut
    case scanBecameInactive
    case minimumWindowDurationNotReached
    case nonMonotonicWindowClock
    case windowSequenceExhausted
}

/// Public progress intentionally exposes procedure state, never mutable evidence authority.
public struct PassiveBluetoothPowerCycleObservationProgress: Equatable, Sendable {
    public let phase: PassiveBluetoothPowerCycleObservationPhase
    public let isAwaitingBluetoothPower: Bool
    public let isAwaitingScanReadiness: Bool
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
/// `observationSnapshots` preserves the exact package-issued full-UUID/connectability catalogs
/// that earned `correlation`, so durable provenance can replay the assessor instead of trusting a
/// detached summary. Those snapshots remain software evidence only; they do not authenticate a
/// physical scooter or prove radio-time absence/completeness.
public struct PassiveBluetoothPowerCycleObservationResult: Equatable, Sendable {
    public let windows: [PassiveBluetoothPowerCycleObservationWindowReceipt]
    public let observationSnapshots: [PassiveBluetoothCandidateObservationSnapshot]
    public let correlation: PassiveBluetoothPowerCycleTargetCorrelationReport
}

/// Fail-closed callback/window liveness policy shared by the live producer and deterministic tests.
/// A started receipt window is not enough: the exact CoreBluetooth manager must also remain powered
/// and actively scanning when evidence is admitted.
enum PassiveBluetoothPowerCycleScanLiveness {
    static func isLive(
        isPoweredOn: Bool,
        isScanning: Bool,
        hasStartedReceiptWindow: Bool
    ) -> Bool {
        isPoweredOn && isScanning && hasStartedReceiptWindow
    }
}

/// CoreBluetooth publicly exposes `isScanning`, but does not document that it must become `true`
/// synchronously before `scanForPeripherals` returns. This policy therefore distinguishes a scan
/// request from confirmed scan liveness and permits a short bounded readiness interval before
/// failing closed. It is software-manager evidence only, never radio-time completeness evidence.
enum PassiveBluetoothPowerCycleScanReadinessDecision: Equatable, Sendable {
    case wait
    case ready
    case bluetoothUnavailable
    case timedOut
}

enum PassiveBluetoothPowerCycleScanReadinessPolicy {
    static func decide(
        isPoweredOn: Bool,
        isScanning: Bool,
        nowUptimeNanoseconds: UInt64,
        deadlineUptimeNanoseconds: UInt64
    ) -> PassiveBluetoothPowerCycleScanReadinessDecision {
        guard isPoweredOn else {
            return .bluetoothUnavailable
        }
        if nowUptimeNanoseconds >= deadlineUptimeNanoseconds {
            return .timedOut
        }
        if isScanning {
            return .ready
        }
        return .wait
    }
}

/// Delivery policy for the bounded physical-correlation windows.
///
/// The authoritative receipt window opens only after Nembra separately observes `isScanning`.
/// A discovery callback may arrive between the scan request and that boundary and is intentionally
/// rejected as pre-window evidence. CoreBluetooth may coalesce repeated discoveries when duplicate
/// filtering is enabled, so these short research scans must request duplicate delivery to keep a
/// later post-readiness advertisement eligible for the accepted catalog. The catalog itself still
/// deduplicates by full peripheral UUID and merges connectability monotonically.
///
/// This prevents one known app-created false-negative. It does not make callback absence proof of
/// RF completeness or physical scooter absence.
enum PassiveBluetoothPowerCycleScanDeliveryPolicy {
    static let allowsDuplicateDiscoveryCallbacks = true
}

/// Monotonic merge for repeated discovery evidence within one live window.
/// Explicit non-connectable evidence dominates; otherwise explicit connectable dominates unknown.
enum PassiveBluetoothPowerCycleConnectabilityMerge {
    static func merged(current: Bool?, incoming: Bool?) -> Bool? {
        if current == false || incoming == false {
            return false
        }
        if current == true || incoming == true {
            return true
        }
        return nil
    }
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
            observationSnapshots: completedSnapshots,
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
/// Any Bluetooth-authority failure, scan-liveness loss, readiness timeout, or explicit operator
/// abandonment permanently invalidates the whole four-window series. The caller must construct a
/// fresh session and restart at OFF₁; already-completed windows are never reused across a known gap.
///
/// Safety / truth boundary:
/// - broad discovery only; no connection and no characteristic-value writes;
/// - local names, RSSI, services, short UUIDs, and product signatures never affect correlation;
/// - window phases are operator-declared expected power state, not physical attestation;
/// - a scan request is not a window start; receipt timing begins only after the manager is observed
///   powered-on and actively scanning strictly before a bounded readiness deadline;
/// - a completed catalog contains callbacks accepted while the exact manager reported active scan
///   before the synchronous receipt cutoff; it is not radio-time completeness proof;
/// - a unique repeated UUID is correlation evidence only, never permanent ES80 identity.
@MainActor
public final class PassiveBluetoothPowerCycleObservationSession: NSObject {
    private struct CandidateState {
        let id: UUID
        var isConnectable: Bool?

        mutating func merge(isConnectable incoming: Bool?) {
            isConnectable = PassiveBluetoothPowerCycleConnectabilityMerge.merged(
                current: isConnectable,
                incoming: incoming
            )
        }
    }

    private static let scanReadinessTimeoutNanoseconds: UInt64 = 2_000_000_000
    private static let scanReadinessPollInterval: Duration = .milliseconds(20)

    private var ledger: PassiveBluetoothPowerCycleObservationLedger
    private let minimumWindowDurationNanoseconds: UInt64
    private var activeManager: CBCentralManager?
    private var awaitingPoweredOn = false
    private var awaitingScanReadiness = false
    private var scanReadinessDeadlineUptimeNanoseconds: UInt64?
    private var scanReadinessToken: UUID?
    private var scanReadinessTask: Task<Void, Never>?
    private var windowStartedAtUptimeNanoseconds: UInt64?
    private var candidatesByIdentifier: [UUID: CandidateState] = [:]
    private var finalResult: PassiveBluetoothPowerCycleObservationResult?
    private var terminalError: PassiveBluetoothPowerCycleObservationSessionError?

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
        let managerIsPoweredOn = activeManager?.state == .poweredOn
        let managerIsScanning = activeManager?.isScanning == true
        return PassiveBluetoothPowerCycleObservationProgress(
            phase: phase,
            isAwaitingBluetoothPower: awaitingPoweredOn,
            isAwaitingScanReadiness: awaitingScanReadiness,
            isScanning: PassiveBluetoothPowerCycleScanLiveness.isLive(
                isPoweredOn: managerIsPoweredOn,
                isScanning: managerIsScanning,
                hasStartedReceiptWindow: windowStartedAtUptimeNanoseconds != nil
            ),
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
    /// manager's own state callback says it is powered on. The scan request then enters a bounded
    /// readiness interval; the receipt window opens only after `isScanning` is observed true before
    /// the deadline. Terminal non-powered states or readiness expiry invalidate the entire series.
    public func startCurrentWindow() throws {
        guard !ledger.isInvalidated else {
            throw terminalError ?? PassiveBluetoothPowerCycleObservationSessionError.seriesInvalidated
        }
        guard ledger.nextPhase != nil, finalResult == nil else {
            throw PassiveBluetoothPowerCycleObservationSessionError.seriesComplete
        }
        guard activeManager == nil else {
            throw PassiveBluetoothPowerCycleObservationSessionError.windowAlreadyActive
        }

        cancelScanReadinessObservation()
        candidatesByIdentifier.removeAll(keepingCapacity: true)
        windowStartedAtUptimeNanoseconds = nil
        terminalError = nil
        awaitingPoweredOn = true
        awaitingScanReadiness = false

        let manager = CBCentralManager(delegate: self, queue: .main, options: nil)
        activeManager = manager
        switch manager.state {
        case .poweredOn:
            requestScanIfAwaiting(on: manager)
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

    /// Freezes the current receipt-bounded catalog. Calling this early after the receipt window
    /// starts fails without advancing phase or reusing the manager; the same window genuinely keeps
    /// scanning until the minimum duration is satisfied. Calling while a scan request is still
    /// awaiting confirmed liveness reports `scanReadinessPending` and does not manufacture a start.
    ///
    /// On success, the manager is stopped and retired synchronously before evidence is sealed. Any
    /// callback already queued from that manager reaches the delegate with a non-active manager
    /// identity and is rejected rather than leaking into the next window.
    @discardableResult
    public func finishCurrentWindow() throws -> PassiveBluetoothPowerCycleObservationResult? {
        guard !ledger.isInvalidated else {
            throw terminalError ?? PassiveBluetoothPowerCycleObservationSessionError.seriesInvalidated
        }
        if awaitingScanReadiness {
            throw PassiveBluetoothPowerCycleObservationSessionError.scanReadinessPending
        }
        guard let manager = activeManager,
              let startedAt = windowStartedAtUptimeNanoseconds,
              let phase = ledger.nextPhase else {
            throw PassiveBluetoothPowerCycleObservationSessionError.windowNotActive
        }
        guard manager.state == .poweredOn else {
            invalidateCurrentTransportForBluetoothState(manager)
            throw PassiveBluetoothPowerCycleObservationSessionError.bluetoothBecameUnavailable
        }
        guard manager.isScanning else {
            retireCurrentTransport(
                manager,
                terminalError: .scanBecameInactive
            )
            throw PassiveBluetoothPowerCycleObservationSessionError.scanBecameInactive
        }

        let endedAt = DispatchTime.now().uptimeNanoseconds
        guard endedAt >= startedAt else {
            retireCurrentTransport(
                manager,
                terminalError: .nonMonotonicWindowClock
            )
            throw PassiveBluetoothPowerCycleObservationSessionError.nonMonotonicWindowClock
        }
        guard endedAt - startedAt >= minimumWindowDurationNanoseconds else {
            throw PassiveBluetoothPowerCycleObservationSessionError.minimumWindowDurationNotReached
        }

        manager.stopScan()
        activeManager = nil
        awaitingPoweredOn = false
        awaitingScanReadiness = false
        cancelScanReadinessObservation()
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
            terminalError = .seriesInvalidated
            throw error
        }
    }

    /// Explicit operator abandonment is a known experiment gap. It invalidates any incomplete
    /// series even between completed windows, when no CoreBluetooth transport is currently active.
    /// Prior completed windows can therefore never be patched into a later resumed attempt.
    public func abandonCurrentWindow() {
        guard finalResult == nil, !ledger.isInvalidated else { return }

        if let manager = activeManager {
            retireCurrentTransport(
                manager,
                terminalError: .seriesInvalidated
            )
            return
        }

        ledger.invalidate()
        terminalError = .seriesInvalidated
        awaitingPoweredOn = false
        awaitingScanReadiness = false
        cancelScanReadinessObservation()
        windowStartedAtUptimeNanoseconds = nil
        candidatesByIdentifier.removeAll(keepingCapacity: true)
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === activeManager else { return }

        switch central.state {
        case .poweredOn:
            if awaitingPoweredOn {
                requestScanIfAwaiting(on: central)
            } else if !awaitingScanReadiness,
                      windowStartedAtUptimeNanoseconds != nil,
                      !central.isScanning {
                retireCurrentTransport(
                    central,
                    terminalError: .scanBecameInactive
                )
            }
        case .unknown, .resetting:
            if awaitingScanReadiness || windowStartedAtUptimeNanoseconds != nil {
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
              PassiveBluetoothPowerCycleScanLiveness.isLive(
                  isPoweredOn: central.state == .poweredOn,
                  isScanning: central.isScanning,
                  hasStartedReceiptWindow: windowStartedAtUptimeNanoseconds != nil
              ) else {
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

    /// Requests a scan only for the exact active powered-on manager, then observes readiness over a
    /// bounded main-actor interval. A request itself never opens the evidence window and an
    /// immediate `isScanning == false` is never interpreted as terminal framework failure.
    private func requestScanIfAwaiting(on manager: CBCentralManager) {
        guard !ledger.isInvalidated,
              manager === activeManager,
              awaitingPoweredOn,
              manager.state == .poweredOn,
              windowStartedAtUptimeNanoseconds == nil else {
            return
        }

        awaitingPoweredOn = false
        awaitingScanReadiness = true
        candidatesByIdentifier.removeAll(keepingCapacity: true)

        let now = DispatchTime.now().uptimeNanoseconds
        let (deadline, overflow) = now.addingReportingOverflow(Self.scanReadinessTimeoutNanoseconds)
        guard !overflow else {
            retireCurrentTransport(
                manager,
                terminalError: .scanReadinessTimedOut
            )
            return
        }

        scanReadinessDeadlineUptimeNanoseconds = deadline
        let token = UUID()
        scanReadinessToken = token
        manager.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey:
                    PassiveBluetoothPowerCycleScanDeliveryPolicy.allowsDuplicateDiscoveryCallbacks
            ]
        )
        beginScanReadinessObservation(token: token)
    }

    /// Polls only manager software state. No callback or `isScanning` read is promoted into proof
    /// that the radio observed every advertisement. Callbacks arriving before readiness is confirmed
    /// are intentionally discarded because their receipt precedes the authoritative window start.
    private func beginScanReadinessObservation(token: UUID) {
        scanReadinessTask?.cancel()
        scanReadinessTask = Task { @MainActor [weak self] in
            while let self,
                  self.scanReadinessToken == token,
                  !Task.isCancelled {
                guard let manager = self.activeManager,
                      let deadline = self.scanReadinessDeadlineUptimeNanoseconds else {
                    return
                }

                let now = DispatchTime.now().uptimeNanoseconds
                switch PassiveBluetoothPowerCycleScanReadinessPolicy.decide(
                    isPoweredOn: manager.state == .poweredOn,
                    isScanning: manager.isScanning,
                    nowUptimeNanoseconds: now,
                    deadlineUptimeNanoseconds: deadline
                ) {
                case .ready:
                    self.confirmScanReadiness(
                        on: manager,
                        token: token,
                        observedAtUptimeNanoseconds: now
                    )
                    return
                case .bluetoothUnavailable:
                    self.invalidateCurrentTransportForBluetoothState(manager)
                    return
                case .timedOut:
                    self.retireCurrentTransport(
                        manager,
                        terminalError: .scanReadinessTimedOut
                    )
                    return
                case .wait:
                    do {
                        try await Task.sleep(for: Self.scanReadinessPollInterval)
                    } catch {
                        return
                    }
                }
            }
        }
    }

    private func confirmScanReadiness(
        on manager: CBCentralManager,
        token: UUID,
        observedAtUptimeNanoseconds: UInt64
    ) {
        guard !ledger.isInvalidated,
              manager === activeManager,
              scanReadinessToken == token,
              awaitingScanReadiness,
              manager.state == .poweredOn,
              manager.isScanning,
              windowStartedAtUptimeNanoseconds == nil else {
            return
        }

        awaitingScanReadiness = false
        scanReadinessToken = nil
        scanReadinessDeadlineUptimeNanoseconds = nil
        scanReadinessTask = nil
        windowStartedAtUptimeNanoseconds = observedAtUptimeNanoseconds
    }

    private func cancelScanReadinessObservation() {
        scanReadinessTask?.cancel()
        scanReadinessTask = nil
        scanReadinessToken = nil
        scanReadinessDeadlineUptimeNanoseconds = nil
    }

    private func invalidateCurrentTransportForBluetoothState(_ manager: CBCentralManager) {
        retireCurrentTransport(
            manager,
            terminalError: .bluetoothBecameUnavailable
        )
    }

    private func retireCurrentTransport(
        _ manager: CBCentralManager,
        terminalError: PassiveBluetoothPowerCycleObservationSessionError
    ) {
        guard manager === activeManager else { return }
        if manager.isScanning {
            manager.stopScan()
        }
        ledger.invalidate()
        self.terminalError = terminalError
        activeManager = nil
        awaitingPoweredOn = false
        awaitingScanReadiness = false
        cancelScanReadinessObservation()
        windowStartedAtUptimeNanoseconds = nil
        candidatesByIdentifier.removeAll(keepingCapacity: true)
    }
}

/// CoreBluetooth's imported delegate requirements are not actor-isolated in the SDK surface.
/// The manager is explicitly delivered on `.main`, and the class itself is `@MainActor`; using
/// the same narrow `@preconcurrency` conformance boundary as the existing foreground controller
/// avoids weakening the implementation methods to `nonisolated` or relaxing package concurrency.
extension PassiveBluetoothPowerCycleObservationSession: @preconcurrency CBCentralManagerDelegate {}
