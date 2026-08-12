@preconcurrency import CoreBluetooth
import Dispatch
import Foundation
import NembraCore

/// MainActor artifact-read gate that freezes how far the asynchronous recorder
/// may drain while one immutable capture artifact is being read.
///
/// Events after `watermark` remain queued until the read ends. This keeps the
/// recorder actor from accepting a post-cut callback before `snapshot()` or
/// `encodedJSON()` reaches that actor, without suppressing live CoreBluetooth
/// callbacks or pretending those later observations never happened.
struct PassiveCoreBluetoothArtifactReadBarrier: Equatable, Sendable {
    enum StateError: Error, Equatable, Sendable {
        case alreadyActive
    }

    private(set) var watermark: UInt64?

    var isActive: Bool {
        watermark != nil
    }

    mutating func begin(through watermark: UInt64) throws {
        guard self.watermark == nil else {
            throw StateError.alreadyActive
        }
        self.watermark = watermark
    }

    mutating func end() {
        watermark = nil
    }

    func drainUpperBound(pendingTail: UInt64) -> UInt64 {
        guard let watermark else { return pendingTail }
        return min(watermark, pendingTail)
    }

    func permittedDrainUpperBound(
        firstPending: UInt64,
        pendingTail: UInt64
    ) -> UInt64? {
        let upperBound = drainUpperBound(pendingTail: pendingTail)
        return firstPending <= upperBound ? upperBound : nil
    }
}

/// Immutable identity required for one capture artifact to remain authoritative
/// across asynchronous recorder hops. Any target-session or authority-generation
/// change invalidates the suspended read rather than relabeling newer evidence as
/// part of the old artifact.
struct PassiveCoreBluetoothArtifactAuthorityContext: Equatable, Sendable {
    let targetSessionGeneration: UInt64
    let authorityGeneration: UInt64

    func matches(
        targetSessionGeneration: UInt64,
        authorityGeneration: UInt64
    ) -> Bool {
        self.targetSessionGeneration == targetSessionGeneration
            && self.authorityGeneration == authorityGeneration
    }
}

/// Identity for one finite GATT acquisition watchdog. The watchdog may fire only
/// if the selected peripheral, durable target session, and acquisition generation
/// still match the context that armed it. This prevents an old timer from
/// terminating a later reconnect or topology reacquisition.
struct PassiveCoreBluetoothAcquisitionWatchdogContext: Equatable, Sendable {
    let peripheralIdentifier: UUID
    let targetSessionGeneration: UInt64
    let acquisitionGeneration: UInt64
}

/// Deterministic watchdog arm/rearm/cancel state. `revision` distinguishes a
/// newly rearmed deadline even when physical identity/generation is unchanged, so
/// an old cancelled Task cannot fire early after legitimate acquisition progress.
struct PassiveCoreBluetoothAcquisitionWatchdogState: Equatable, Sendable {
    struct Ticket: Equatable, Sendable {
        let context: PassiveCoreBluetoothAcquisitionWatchdogContext
        let revision: UInt64
    }

    enum StateError: Error, Equatable, Sendable {
        case revisionExhausted
    }

    private(set) var activeTicket: Ticket?
    private var nextRevision: UInt64 = 1

    var isArmed: Bool {
        activeTicket != nil
    }

    mutating func arm(
        for context: PassiveCoreBluetoothAcquisitionWatchdogContext
    ) throws -> Ticket {
        guard nextRevision != UInt64.max else {
            throw StateError.revisionExhausted
        }
        let ticket = Ticket(context: context, revision: nextRevision)
        nextRevision += 1
        activeTicket = ticket
        return ticket
    }

    mutating func cancel() {
        activeTicket = nil
    }

    func acceptsExpiry(
        _ ticket: Ticket,
        currentContext: PassiveCoreBluetoothAcquisitionWatchdogContext?
    ) -> Bool {
        activeTicket == ticket && currentContext == ticket.context
    }
}

/// A user-initiated, foreground-only CoreBluetooth acquisition controller for
/// physical protocol research.
///
/// Safety boundary:
/// - discovers, connects, reads, subscribes, and records evidence;
/// - never writes an application characteristic value;
/// - never assumes a Tuya/ZYDTECH service family or DP schema;
/// - never turns local-name matches into verified vehicle identity.
///
/// Broad scanning is only a candidate catalog. A durable target-labeled capture
/// session is created only when the operator explicitly connects to one observed
/// peripheral. This is intentionally not wired into production scooter control.
@MainActor
public final class ForegroundCoreBluetoothCaptureController: NSObject {
    public enum ConnectionPhase: Equatable, Sendable {
        case idle
        case connecting(UUID)
        case connected(UUID)
    }

    public struct DiscoveredPeripheral: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let localName: String?
        public let rssi: Int?
        public let isConnectable: Bool?

        public init(id: UUID, localName: String?, rssi: Int?, isConnectable: Bool?) {
            self.id = id
            self.localName = localName
            self.rssi = rssi
            self.isConnectable = isConnectable
        }

        public var rssiDescription: String {
            rssi.map { "\($0) dBm" } ?? "Unavailable"
        }

        static func normalizedRSSI(_ rawValue: Int) -> Int? {
            rawValue == 127 ? nil : rawValue
        }

        static func sortsBefore(_ lhs: Self, _ rhs: Self) -> Bool {
            switch (lhs.rssi, rhs.rssi) {
            case let (.some(left), .some(right)) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    public enum ControllerError: Error, Equatable, Sendable {
        case bluetoothNotPoweredOn
        case unknownPeripheral(UUID)
        case peripheralNotConnectable(UUID)
        case connectionAlreadyActive
        case invalidConnectionTimeout
        case invalidAcquisitionProgressTimeout
        case experimentOneVehicleContextMismatch
        case targetNotSelected
        case peripheralAwaitingTerminalCallback(UUID)
        case attemptGenerationExhausted
        case targetSessionChanged
        case artifactReadAlreadyActive
        case artifactNotFinalized
        case captureFinalized
        case captureIncomplete
        case captureFailed
    }

    private enum AcquisitionError: Error, Equatable, Sendable {
        case characteristicMissingService
        case missingCharacteristicValue
        case unattributedCharacteristicValue
        case missingServices
        case missingIncludedServices
        case missingCharacteristics
        case missingDescriptors
        case serviceNotInCurrentAcquisition
        case characteristicNotInCurrentAcquisition
        case ambiguousReadWhileAlreadyNotifying
        case readProvenanceMismatch
        case subscriptionProvenanceMismatch
        case subscriptionStateMismatch
        case serviceInvalidatedDuringAcquisition
        case artifactAuthorityGenerationExhausted
        case eventQueueSequenceExhausted
    }

    private struct CandidateAdvertisement {
        let observation: PassiveBluetoothAdvertisementObservation
        let receivedAtUptimeNanoseconds: UInt64
        let receivedAtDate: Date
    }

    private struct CallbackReceipt {
        let uptimeNanoseconds: UInt64
        let date: Date
    }

    private struct ArtifactContext {
        let recorder: PassiveCoreBluetoothCaptureRecorder
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let eventWatermark: UInt64
    }

    public private(set) var bluetoothState: CBManagerState = .unknown

    /// True while Nembra still owns an explicit foreground scan request. This is
    /// request intent only; use `isScanning` for CoreBluetooth's current state.
    public var isScanRequested: Bool {
        scanRequested
    }

    /// True only when Nembra owns the request and the exact CoreBluetooth
    /// manager currently reports that it is scanning. This is software transport
    /// state, not RF completeness or scan-generation provenance.
    public var isScanning: Bool {
        scanRequested && centralManager?.isScanning == true
    }

    public private(set) var connectionPhase: ConnectionPhase = .idle
    /// Deterministic presentation snapshot. Sorting is deliberately paid by the
    /// presentation reader, never by CoreBluetooth's high-cadence discovery callback.
    public var discoveredPeripherals: [DiscoveredPeripheral] {
        latestDiscoveryByIdentifier.values.sorted {
            DiscoveredPeripheral.sortsBefore($0, $1)
        }
    }

    /// Exact UUID rediscovery authority is dictionary-backed and does not materialize
    /// or sort the presentation catalog.
    func hasDiscoveredPeripheral(identifier: UUID) -> Bool {
        latestDiscoveryByIdentifier[identifier] != nil
    }

    /// Read-only exact candidate lookup for coordinator connectability policy. This
    /// remains presentation/candidate state, not physical scooter authentication.
    func discoveredPeripheral(identifier: UUID) -> DiscoveredPeripheral? {
        latestDiscoveryByIdentifier[identifier]
    }
    public private(set) var lastDiagnostic: String?
    public private(set) var captureFailed = false

    public var selectedTargetIdentifier: UUID? {
        targetState.selectedTargetIdentifier
    }

    /// True only while the selected target's most recently cancelled/retired
    /// CoreBluetooth attempt is still quarantined awaiting its terminal callback.
    /// Central availability changes alone do not clear this UUID-only quarantine;
    /// the real terminal callback releases it. If that callback never arrives,
    /// relaunch is the fail-closed recovery rather than risking a fresh attempt
    /// being terminated by an older same-identifier callback.
    public var isSelectedTargetAwaitingTerminalCallback: Bool {
        guard let identifier = targetState.selectedTargetIdentifier else { return false }
        return targetState.isAwaitingTerminalCallback(for: identifier)
    }

    public var hasTargetSession: Bool {
        recorder != nil
    }

    /// Authoritative analysis/export is available after the selected target has
    /// one completely drained finite GATT acquisition and no controller-local
    /// acquisition/cancellation transition currently blocks the artifact. Ongoing
    /// notifications are not readiness operations and may continue after this.
    ///
    /// Same-target retry quarantine is independent: retained evidence may remain
    /// ready while `isSelectedTargetAwaitingTerminalCallback` stays true until the
    /// real terminal callback releases that retry boundary.
    public var hasCompleteTargetEvidence: Bool {
        recorder != nil
            && !captureFailed
            && foregroundEvidenceIntegrityValid
            && acquisitionLedger.isReady
            && !selectedTargetCancellationPending
    }

    /// True only after the finite-acquisition Ready boundary itself has
    /// durably crossed the recorder actor under the still-current artifact
    /// authority. This is the product-safe admission state for a terminal
    /// observation Horizon; finite GATT readiness alone is not enough.
    public var canFinalizeObservationHorizon: Bool {
        guard hasCompleteTargetEvidence,
              !artifactReadBarrier.isActive,
              observationBoundaryTask == nil,
              case .observing = observationBoundaryQueueGate.phase,
              let committedReadyEpoch,
              committedReadyEpoch.authority == artifactAuthorityFence.currentAuthority else {
            return false
        }

        // Product eligibility mirrors the trusted Experiment One procedure clock,
        // but this descriptive status is never mutation authority. Finalization
        // still obtains a producer-issued Permit immediately before H allocation.
        if case .eligible = PassiveCoreBluetoothObservationHorizonMinimumDurationGate
            .currentExperimentOneStatus(for: committedReadyEpoch) {
            return true
        }
        return false
    }

    private let vehicleIdentity: VehicleIdentity
    private let initialSessionID: UUID
    private let firstSessionStartedAtOverride: Date?
    private let acquisitionProgressTimeoutNanoseconds: UInt64
    private var hasUsedInitialSessionIdentity = false
    private var recorder: PassiveCoreBluetoothCaptureRecorder?
    private var targetSessionGeneration: UInt64 = 0
    private var artifactAuthorityGeneration: UInt64 = 0
    private let artifactAuthorityFence = PassiveCoreBluetoothArtifactAuthorityFence(
        authority: PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 0,
            authorityGeneration: 0
        )
    )
    private var lastFinalizedArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext?
    /// Exact successful-terminal FIFO resolution retained after immutable artifact
    /// return. It remains inert until transport teardown crosses the real terminal
    /// CoreBluetooth callback and a producer-created fresh recorder is installed.
    private var pendingTerminalQueueResolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt?
    private var targetState = PassiveCoreBluetoothTargetState()
    private var acquisitionLedger = PassiveCoreBluetoothAcquisitionOperationLedger()
    private var gattIdentityRegistry = PassiveCoreBluetoothGATTIdentityRegistry()
    private var selectedTargetCancellationPending = false
    /// Foreground-only evidence remains valid for exactly one durable target capture.
    /// Once the app leaves foreground, that capture cannot regain export/finalization
    /// authority merely by reconnecting transport.
    private var foregroundEvidenceIntegrityValid = true
    private var scanRequested = false

    private var centralManager: CBCentralManager!
    private var peripheralByIdentifier: [UUID: CBPeripheral] = [:]
    private var latestDiscoveryByIdentifier: [UUID: DiscoveredPeripheral] = [:]
    private var latestAdvertisementByIdentifier: [UUID: CandidateAdvertisement] = [:]
    private var activePeripheral: CBPeripheral?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var acquisitionWatchdogTask: Task<Void, Never>?
    private var acquisitionWatchdogState = PassiveCoreBluetoothAcquisitionWatchdogState()
    private var discoveredIncludedServiceObjectIDs: Set<ObjectIdentifier> = []
    private var discoveredCharacteristicServiceObjectIDs: Set<ObjectIdentifier> = []
    private var hasObservedInitialCentralState = false

    private struct PendingEvent {
        let queueSequence: UInt64
        let recorder: PassiveCoreBluetoothCaptureRecorder
        let sessionGeneration: UInt64
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let event: PassiveBluetoothCaptureEvent
        let uptimeNanoseconds: UInt64
        let date: Date
    }

    /// Callback events are synchronously inserted into this MainActor-owned
    /// queue. Each event captures the exact recorder/session generation that was
    /// current at callback entry, so switching research targets cannot redirect
    /// already-queued evidence into the new target artifact.
    private var pendingEvents: [PendingEvent] = []
    private var eventDrainTask: Task<Void, Never>?
    private var lastEnqueuedEventSequence: UInt64 = 0
    /// Furthest global FIFO position whose event was handed to its captured recorder.
    /// Terminal retirement must never advance this recorder-written frontier.
    private var lastProcessedEventSequence: UInt64 = 0
    /// Furthest global FIFO position intentionally settled by either recorder drain
    /// or an accepted retirement producer. This may advance beyond the recorder-
    /// written frontier only after terminal post-H evidence is retired explicitly.
    private var lastResolvedEventSequence: UInt64 = 0
    private var artifactReadBarrier = PassiveCoreBluetoothArtifactReadBarrier()
    private var observationBoundaryQueueGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
    private var observationBoundaryTask: Task<Void, Never>?
    /// Waits only for an already-running old-session recorder drain to settle after
    /// the real terminal CoreBluetooth callback clears transport quarantine. It never
    /// spans retirement -> resolution -> fresh-recorder installation -> gate reopen.
    private var abortedFreshSessionRecoveryTask: Task<Void, Never>?
    private var committedReadyEpoch: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch?

    public init(
        vehicleIdentity: VehicleIdentity,
        sessionID: UUID = UUID(),
        startedAt: Date? = nil,
        acquisitionProgressTimeout: TimeInterval = PassiveCoreBluetoothAcquisitionPolicy.defaultAcquisitionProgressTimeout,
        centralManagerOptions: [String: Any]? = nil
    ) throws {
        guard let acquisitionProgressTimeoutNanoseconds =
                PassiveCoreBluetoothAcquisitionPolicy.acquisitionProgressTimeoutNanoseconds(acquisitionProgressTimeout) else {
            throw ControllerError.invalidAcquisitionProgressTimeout
        }
        self.vehicleIdentity = vehicleIdentity
        initialSessionID = sessionID
        firstSessionStartedAtOverride = startedAt
        self.acquisitionProgressTimeoutNanoseconds = acquisitionProgressTimeoutNanoseconds
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: centralManagerOptions
        )
        bluetoothState = centralManager.state
    }

    deinit {
        connectionTimeoutTask?.cancel()
        acquisitionWatchdogTask?.cancel()
        eventDrainTask?.cancel()
        observationBoundaryTask?.cancel()
        abortedFreshSessionRecoveryTask?.cancel()
    }

    /// Starts an explicit foreground research scan. Every explicit scan owns a
    /// fresh in-memory candidate epoch: CoreBluetooth objects observed by a
    /// previous stopped scan are not left selectable as if freshly rediscovered.
    public func startScanning(captureAdvertisementCadence: Bool = false) throws {
        try ensureCaptureHealthy()
        guard !observationBoundaryQueueGate.isTerminal else {
            throw ControllerError.captureFinalized
        }
        guard centralManager.state == .poweredOn else {
            throw ControllerError.bluetoothNotPoweredOn
        }

        clearCandidateCatalog()
        scanRequested = true
        centralManager.scanForPeripherals(
            withServices: PassiveCoreBluetoothAcquisitionPolicy.foregroundResearchServiceFilter,
            options: PassiveCoreBluetoothAcquisitionPolicy.foregroundResearchScanOptions(
                captureAdvertisementCadence: captureAdvertisementCadence
            )
        )
    }

    public func stopScanning() {
        scanRequested = false
        centralManager.stopScan()
    }

    /// Explicitly selects the observed peripheral as the current research target
    /// and starts a finite connection attempt. Selecting a different candidate
    /// starts a new durable capture session rather than mixing devices.
    public func connect(
        to peripheralIdentifier: UUID,
        timeout: TimeInterval = 12
    ) throws {
        try ensureCaptureHealthy()
        guard !observationBoundaryQueueGate.isTerminal else {
            throw ControllerError.captureFinalized
        }
        // Horizon admission freezes the artifact cutoff. A new transport attempt
        // cannot revoke that closing authority while JSON sealing is in flight.
        guard !observationBoundaryBlocksArtifactMutation else {
            throw ControllerError.captureIncomplete
        }
        guard centralManager.state == .poweredOn else {
            throw ControllerError.bluetoothNotPoweredOn
        }
        guard let timeoutNanoseconds = PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(timeout) else {
            throw ControllerError.invalidConnectionTimeout
        }
        guard connectionPhase == .idle else {
            throw ControllerError.connectionAlreadyActive
        }
        guard let peripheral = peripheralByIdentifier[peripheralIdentifier] else {
            throw ControllerError.unknownPeripheral(peripheralIdentifier)
        }
        if latestDiscoveryByIdentifier[peripheralIdentifier]?.isConnectable == false {
            throw ControllerError.peripheralNotConnectable(peripheralIdentifier)
        }

        do {
            try targetState.validateCanBeginAttempt(for: peripheralIdentifier)
        } catch PassiveCoreBluetoothTargetState.StateError.peripheralAwaitingTerminalCallback(let identifier) {
            throw ControllerError.peripheralAwaitingTerminalCallback(identifier)
        } catch PassiveCoreBluetoothTargetState.StateError.generationExhausted {
            throw ControllerError.attemptGenerationExhausted
        } catch {
            throw ControllerError.targetNotSelected
        }

        try beginTargetSessionIfNeeded(for: peripheralIdentifier)
        do {
            _ = try targetState.beginAttempt(for: peripheralIdentifier)
        } catch PassiveCoreBluetoothTargetState.StateError.peripheralAwaitingTerminalCallback(let identifier) {
            throw ControllerError.peripheralAwaitingTerminalCallback(identifier)
        } catch PassiveCoreBluetoothTargetState.StateError.generationExhausted {
            throw ControllerError.attemptGenerationExhausted
        } catch {
            throw ControllerError.targetNotSelected
        }

        acquisitionLedger.beginConnectionAttempt()
        selectedTargetCancellationPending = false
        guard advanceArtifactAuthority() else {
            throw ControllerError.captureFailed
        }

        stopScanning()
        connectionPhase = .connecting(peripheralIdentifier)
        activePeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        scheduleConnectionTimeout(for: peripheral, nanoseconds: timeoutNanoseconds)
    }


    /// Connects the exact correlated Experiment One target using the mutable recorder
    /// already owned by that same sealed run. This package-internal bridge is the only
    /// controller path that may turn `PassiveBluetoothExperimentOneCaptureAdmission`
    /// into live capture ownership; app/UI code cannot call it directly.
    ///
    /// The admission is consumed once only after controller-global preconditions that
    /// do not depend on its hidden target have passed. The consumed full CoreBluetooth
    /// UUID must then exist in this controller's *current* candidate catalog. A repeatable
    /// UUID is still only a correlated Bluetooth target, never authenticated ES80 identity.
    /// No application characteristic write is performed by this path.
    func connectUsingExperimentOneAdmission(
        _ admission: PassiveBluetoothExperimentOneCaptureAdmission,
        timeout: TimeInterval = 12
    ) throws {
        try ensureCaptureHealthy()
        guard vehicleIdentity == VehicleProfile.aovoproES80.identity else {
            throw ControllerError.experimentOneVehicleContextMismatch
        }
        guard !observationBoundaryQueueGate.isTerminal else {
            throw ControllerError.captureFinalized
        }
        guard !observationBoundaryBlocksArtifactMutation else {
            throw ControllerError.captureIncomplete
        }
        guard centralManager.state == .poweredOn else {
            throw ControllerError.bluetoothNotPoweredOn
        }
        guard let timeoutNanoseconds = PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(timeout) else {
            throw ControllerError.invalidConnectionTimeout
        }
        guard connectionPhase == .idle else {
            throw ControllerError.connectionAlreadyActive
        }
        // Experiment One is one provenance life. Do not replace an already-installed
        // generic or prior recorder with a newly consumed sealed admission.
        guard recorder == nil,
              targetState.selectedTargetIdentifier == nil else {
            throw ControllerError.connectionAlreadyActive
        }
        guard targetSessionGeneration != UInt64.max else {
            throw ControllerError.captureFailed
        }

        // Missing/not-yet-fresh rediscovery is recoverable. Inspect only the sealed
        // producer's read-only staging authority until every controller-local precondition
        // succeeds; do not burn the one-shot recorder handoff merely because scanning needs time.
        let preview = try admission.previewForControllerStaging()
        guard let peripheral = peripheralByIdentifier[preview.peripheralIdentifier],
              let discovery = latestDiscoveryByIdentifier[preview.peripheralIdentifier] else {
            throw ControllerError.unknownPeripheral(preview.peripheralIdentifier)
        }
        if discovery.isConnectable == false {
            throw ControllerError.peripheralNotConnectable(preview.peripheralIdentifier)
        }

        do {
            try targetState.validateCanBeginAttempt(for: preview.peripheralIdentifier)
        } catch PassiveCoreBluetoothTargetState.StateError.peripheralAwaitingTerminalCallback(let identifier) {
            throw ControllerError.peripheralAwaitingTerminalCallback(identifier)
        } catch PassiveCoreBluetoothTargetState.StateError.generationExhausted {
            throw ControllerError.attemptGenerationExhausted
        } catch {
            throw ControllerError.targetNotSelected
        }

        guard let latestAdvertisement = latestAdvertisementByIdentifier[preview.peripheralIdentifier],
              latestAdvertisement.receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds else {
            // Equality does not prove this callback receipt happened after handoff. Keep the
            // admission intact and require a strictly later current-controller observation.
            throw ControllerError.unknownPeripheral(preview.peripheralIdentifier)
        }

        let payload = try admission.consume()
        guard payload.admissionIdentity == preview.admissionIdentity,
              payload.peripheralIdentifier == preview.peripheralIdentifier,
              payload.issuedAtUptimeNanoseconds == preview.issuedAtUptimeNanoseconds,
              case let .singleRepeatableCandidate(correlatedIdentifier) =
                payload.powerCycleEvidence.result.correlation.disposition,
              correlatedIdentifier == payload.peripheralIdentifier else {
            throw ControllerError.targetSessionChanged
        }
        guard observationBoundaryQueueGate.resetForNewCaptureSession() else {
            throw ControllerError.captureIncomplete
        }
        committedReadyEpoch = nil

        let previousAuthority = currentArtifactAuthorityContext()
        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: targetSessionGeneration + 1,
            authorityGeneration: 1
        )
        do {
            try artifactAuthorityFence.transition(
                from: previousAuthority,
                to: freshAuthority
            )
        } catch {
            failCapture(error)
            throw ControllerError.captureFailed
        }
        targetSessionGeneration = freshAuthority.targetSessionGeneration
        artifactAuthorityGeneration = freshAuthority.authorityGeneration
        lastFinalizedArtifactAuthority = nil

        targetState.selectTarget(payload.peripheralIdentifier)
        acquisitionLedger.beginTargetSession()
        gattIdentityRegistry.reset()
        selectedTargetCancellationPending = false
        // This sealed admission publishes a genuinely fresh durable recorder/session,
        // so it is the same authority boundary that may restore foreground evidence
        // validity after a prior scene loss. Transport retry alone never does this.
        foregroundEvidenceIntegrityValid = true
        hasUsedInitialSessionIdentity = true
        recorder = payload.recorder

        enqueue(
            .advertisement(latestAdvertisement.observation),
            receivedAtUptimeNanoseconds: latestAdvertisement.receivedAtUptimeNanoseconds,
            receivedAtDate: latestAdvertisement.receivedAtDate
        )

        do {
            _ = try targetState.beginAttempt(for: payload.peripheralIdentifier)
        } catch PassiveCoreBluetoothTargetState.StateError.peripheralAwaitingTerminalCallback(let identifier) {
            throw ControllerError.peripheralAwaitingTerminalCallback(identifier)
        } catch PassiveCoreBluetoothTargetState.StateError.generationExhausted {
            throw ControllerError.attemptGenerationExhausted
        } catch {
            throw ControllerError.targetNotSelected
        }

        acquisitionLedger.beginConnectionAttempt()
        selectedTargetCancellationPending = false
        guard advanceArtifactAuthority() else {
            throw ControllerError.captureFailed
        }

        stopScanning()
        connectionPhase = .connecting(payload.peripheralIdentifier)
        activePeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        scheduleConnectionTimeout(for: peripheral, nanoseconds: timeoutNanoseconds)
    }

    /// Cancels the active attempt without allowing a subsequent attempt to the
    /// same CoreBluetooth peripheral until one of its terminal callbacks arrives.
    /// A different selected target may start immediately and late callbacks from
    /// the cancelled target are ignored for that new session.
    public func cancelActiveConnection() {
        cancelActiveConnection(cause: .operatorRequest)
    }

    /// Fails the live foreground-only evidence boundary with a cause-specific
    /// interruption before transport teardown. Product shells should use this
    /// instead of presenting foreground integrity loss as an operator cancel.
    public func invalidateActiveCaptureForForegroundLoss() {
        // A terminal artifact is already immutable. Before terminal freeze,
        // foreground loss permanently poisons this durable capture even when H
        // intentionally blocks transport teardown from changing artifact authority.
        if !observationBoundaryQueueGate.isTerminal {
            foregroundEvidenceIntegrityValid = false
        }
        cancelActiveConnection(cause: .foregroundIntegrityLoss)
    }

    /// Ends transport only after the caller has already frozen its immutable
    /// artifact. This intentionally adds no new interruption to that finalized
    /// evidence timeline.
    public func teardownActiveConnectionAfterFinalization() throws {
        guard activePeripheral != nil else {
            _ = try completeTerminalFreshTargetSessionIfReady()
            return
        }
        guard observationBoundaryQueueGate.isTerminal else {
            throw ControllerError.artifactNotFinalized
        }
        guard let finalizedAuthority = lastFinalizedArtifactAuthority,
              finalizedAuthority.matches(
                targetSessionGeneration: targetSessionGeneration,
                authorityGeneration: artifactAuthorityGeneration
              ) else {
            throw ControllerError.artifactNotFinalized
        }
        cancelActiveConnection(cause: .finalizedArtifactTeardown)
    }

    private func cancelActiveConnection(cause: PassiveCoreBluetoothCancellationCause) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        guard let peripheral = activePeripheral else { return }
        if let diagnosticMessage = cause.diagnosticMessage {
            lastDiagnostic = diagnosticMessage
        }

        // Once Horizon admission has frozen the accepted queue cutoff, transport
        // teardown is outside the artifact interval. It may retire live transport
        // state but must not revoke the artifact authority or append interruption
        // evidence to the closing/finalized recorder.
        if observationBoundaryBlocksArtifactMutation {
            _ = targetState.retireActiveAttempt()
            peripheral.delegate = nil
            activePeripheral = nil
            clearAcquisitionObjects()
            connectionPhase = .idle
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        if targetState.selectedTargetIdentifier == peripheral.identifier {
            if let interruptionReason = cause.interruptionReason {
                enqueueInterruption(interruptionReason)
            }
            selectedTargetCancellationPending = true
            if !acquisitionLedger.isReady {
                acquisitionLedger.finishWithoutGattAcquisition()
            }
            guard advanceArtifactAuthority() else { return }
        }

        _ = targetState.retireActiveAttempt()
        peripheral.delegate = nil
        activePeripheral = nil
        clearAcquisitionObjects()
        connectionPhase = .idle
        centralManager.cancelPeripheralConnection(peripheral)
    }

    /// Adds a human-observed stock-app value to the selected target's monotonic
    /// evidence timeline. No marker can exist before explicit target selection.
    public func recordStockAppObservation(
        field: String,
        displayedValue: String,
        note: String? = nil
    ) throws {
        try ensureCaptureHealthy()
        guard !observationBoundaryQueueGate.isTerminal else {
            throw ControllerError.captureFinalized
        }
        guard recorder != nil,
              let selectedTargetIdentifier = targetState.selectedTargetIdentifier else {
            throw ControllerError.targetNotSelected
        }
        guard !selectedTargetCancellationPending,
              !targetState.isAwaitingTerminalCallback(for: selectedTargetIdentifier) else {
            throw ControllerError.peripheralAwaitingTerminalCallback(selectedTargetIdentifier)
        }
        let observation = try PassiveBluetoothStockAppObservation(
            field: field,
            displayedValue: displayedValue,
            note: note
        )
        enqueue(.stockAppState(observation))
    }

    public func captureSnapshot() async throws -> PassiveBluetoothCaptureSession {
        let context = try currentArtifactContext()
        try beginArtifactRead(through: context.eventWatermark)
        defer { endArtifactRead() }

        await flushPendingEvents(through: context.eventWatermark)
        try validate(context)
        let snapshot = await context.recorder.snapshot()
        try validate(context)
        lastFinalizedArtifactAuthority = context.authority
        return snapshot
    }

    public func encodedCaptureJSON(prettyPrinted: Bool = true) async throws -> Data {
        let context = try currentArtifactContext()
        try beginArtifactRead(through: context.eventWatermark)
        defer { endArtifactRead() }

        await flushPendingEvents(through: context.eventWatermark)
        try validate(context)
        let data = try await context.recorder.encodedJSON(prettyPrinted: prettyPrinted)
        try validate(context)
        lastFinalizedArtifactAuthority = context.authority
        return data
    }

    /// Closes the accepted observation interval at one exact MainActor FIFO
    /// cutoff, records the terminal Horizon with the same pre-await clock,
    /// freezes the immutable JSON while post-cut callbacks remain withheld,
    /// then retires only queued evidence proven to be after that Horizon.
    ///
    /// This is Nembra software observation chronology only. It does not
    /// establish RF completeness, scooter identity, or protocol semantics.
    public func encodedFinalizedObservationHorizonJSON(
        prettyPrinted: Bool = true
    ) async throws -> Data {
        try ensureCaptureHealthy()
        guard !artifactReadBarrier.isActive else {
            throw ControllerError.artifactReadAlreadyActive
        }
        guard observationBoundaryTask == nil,
              case .observing = observationBoundaryQueueGate.phase,
              hasCompleteTargetEvidence,
              let recorder,
              let committedReadyEpoch,
              committedReadyEpoch.authority == artifactAuthorityFence.currentAuthority else {
            throw ControllerError.captureIncomplete
        }

        // H cannot be allocated from Ready merely because the queue is drained.
        // The producer samples trusted monotonic uptime here and issues a Permit
        // only after the fixed Experiment One Ready -> H minimum has elapsed.
        let durationPermit = try PassiveCoreBluetoothObservationHorizonMinimumDurationGate
            .authorizeExperimentOneHorizon(for: committedReadyEpoch)
        let horizonAdmission = try durationPermit.beginHorizon(
            queueCutoff: lastEnqueuedEventSequence,
            processedThrough: lastProcessedEventSequence,
            gate: &observationBoundaryQueueGate
        )

        do {
            do {
                await flushPendingEvents(through: horizonAdmission.queueCutoff)
                try requireForegroundEvidenceIntegrity()
                try ensureCaptureHealthy()
                try validateBoundaryAuthority(horizonAdmission.authority)
            } catch {
                let preAttemptFailure = error
                do {
                    let abandonment = try horizonAdmission.abandonBeforeRecorderMutation()
                    try observationBoundaryQueueGate.abortUncommittedHorizon(after: abandonment)
                } catch {
                    // Recovery authority failure is stronger than the original
                    // pre-attempt error because the allocated H lifecycle could not
                    // be proven quarantined. Surface it to the outer fail-closed path.
                    throw error
                }
                throw preAttemptFailure
            }

            let horizonMutationOutcome = try await horizonAdmission
                .recordBoundaryWithMutationOutcome(on: recorder)
            let recordedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.RecordedHorizonBoundary
            switch horizonMutationOutcome {
            case let .recorded(boundary):
                recordedHorizon = boundary
            case let .rejectedBeforeMutation(rejection):
                // Canonical authority was revoked before the recorder mutation body
                // executed. Preserve Ready as the furthest durable boundary and
                // quarantine the exact attempted H transaction as zero-mutation
                // lifecycle provenance. Do not fabricate H evidence.
                try observationBoundaryQueueGate.abortUncommittedHorizon(after: rejection)
                throw ControllerError.targetSessionChanged
            }

            // No actor suspension may occur between the authority-fenced recorder
            // return and typed queue commit. If that exact commit loses lifecycle
            // authority, #507's producer-issued recorded-H token quarantines the
            // durable H without fabricating terminal/frozen success.
            let committedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedHorizonBoundary
            do {
                // Foreground loss can interleave while the recorder actor owns H.
                // Re-check before promoting durable H into queue-committed authority.
                try requireForegroundEvidenceIntegrity()
                committedHorizon = try recordedHorizon.markBoundaryRecorded(
                    on: &observationBoundaryQueueGate,
                    lastProcessedQueueSequence: lastProcessedEventSequence
                )
            } catch {
                let recordedHorizonFailure = error
                do {
                    _ = try observationBoundaryQueueGate.abortRecordedHorizonBeforeGateCommit(
                        recordedHorizon
                    )
                } catch {
                    // Exact quarantine failure is stronger than the triggering
                    // foreground/commit failure; never leave ambiguous recorded H.
                    throw error
                }
                throw recordedHorizonFailure
            }

            let data: Data
            do {
                // Artifact materialization, final authority validation, and explicit
                // terminal freeze form one committed-H pre-freeze transaction. Any
                // failure here preserves H as durable incomplete evidence and must
                // quarantine the exact producer-issued committed H rather than retry
                // under a newer authority or fabricate terminal success.
                data = try await recorder.encodedJSON(prettyPrinted: prettyPrinted)
                // JSON materialization is an actor hop. Foreground integrity must
                // still be valid immediately before the synchronous terminal freeze.
                try requireForegroundEvidenceIntegrity()
                try validateBoundaryAuthority(committedHorizon.authority)
                try committedHorizon.completeHorizonArtifactFreeze(
                    on: &observationBoundaryQueueGate
                )
            } catch {
                let artifactFailure = error
                do {
                    try observationBoundaryQueueGate.abortCommittedHorizonBeforeArtifactFreeze(
                        committedHorizon
                    )
                } catch {
                    // If exact quarantine itself cannot be established, surface that
                    // stronger lifecycle failure; the outer failCapture path remains
                    // closed and still never retires or terminalizes this epoch.
                    throw error
                }
                throw artifactFailure
            }
            // The artifact is already immutable and authority-validated here.
            // Record that truth before fallible post-freeze lifecycle cleanup so a
            // queue-recovery fault cannot relabel a legitimate sealed artifact as
            // if H itself never finalized.
            lastFinalizedArtifactAuthority = committedHorizon.authority
            do {
                let terminalResolution = try resolveQueuedEvidenceAfterTerminalHorizon()
                pendingTerminalQueueResolution = terminalResolution
            } catch {
                // Post-H queue cleanup is lifecycle authority, not artifact content.
                // Preserve the already-sealed data for export while failing the live
                // controller closed so no new capture session can reuse unresolved
                // FIFO state.
                failCapture(
                    error,
                    fallback: "Capture artifact sealed, but terminal queue resolution failed. Start a fresh app session before another capture."
                )
            }
            return data
        } catch {
            failCapture(error)
            throw error
        }
    }

    /// Consumes one sealed terminal lifecycle into the exact next durable recorder only
    /// after transport is idle and same-target terminal-callback quarantine has cleared.
    /// There is deliberately no actor suspension from recorder/authority publication through
    /// gate consumption, so a late callback cannot be relabeled into the fresh session.
    @discardableResult
    private func completeTerminalFreshTargetSessionIfReady(
        startedAt: Date = Date()
    ) throws -> Bool {
        guard observationBoundaryQueueGate.isTerminal,
              let terminalResolution = pendingTerminalQueueResolution else {
            return false
        }
        guard let finalizedAuthority = lastFinalizedArtifactAuthority,
              finalizedAuthority == terminalResolution.terminalAuthority,
              currentArtifactAuthorityContext() == terminalResolution.terminalAuthority else {
            throw ControllerError.artifactNotFinalized
        }
        guard !artifactReadBarrier.isActive,
              observationBoundaryTask == nil,
              activePeripheral == nil,
              connectionPhase == .idle else {
            return false
        }
        guard targetState.selectedTargetIdentifier != nil else {
            throw ControllerError.targetNotSelected
        }
        guard !isSelectedTargetAwaitingTerminalCallback else {
            return false
        }
        guard pendingEvents.isEmpty,
              lastResolvedEventSequence == terminalResolution.resolvedThroughQueueSequence,
              lastEnqueuedEventSequence == terminalResolution.resolvedThroughQueueSequence else {
            throw ControllerError.captureIncomplete
        }

        let freshSession = try PassiveCoreBluetoothTerminalFreshTargetSession.create(
            after: terminalResolution,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )
        let previousAuthority = currentArtifactAuthorityContext()
        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: freshSession.receipt.targetSessionGeneration,
            authorityGeneration: 1
        )

        do {
            // Validate every still-throwing queue-gate condition on a value copy before the
            // reference-backed canonical authority fence advances. Once transition succeeds,
            // publication below is deliberately synchronous and non-failable.
            var reopenedGate = observationBoundaryQueueGate
            try reopenedGate.reopenAfterTerminalFreshTargetSession(
                freshSession.receipt,
                installedRecorder: freshSession.recorder,
                currentResolvedThroughQueueSequence: lastResolvedEventSequence,
                currentLastEnqueuedEventSequence: lastEnqueuedEventSequence
            )
            try artifactAuthorityFence.transition(
                from: previousAuthority,
                to: freshAuthority
            )
            targetSessionGeneration = freshAuthority.targetSessionGeneration
            artifactAuthorityGeneration = freshAuthority.authorityGeneration
            recorder = freshSession.recorder
            hasUsedInitialSessionIdentity = true
            acquisitionLedger.beginTargetSession()
            gattIdentityRegistry.reset()
            selectedTargetCancellationPending = false
            foregroundEvidenceIntegrityValid = true
            committedReadyEpoch = nil
            observationBoundaryQueueGate = reopenedGate
        } catch {
            failCapture(error)
            throw ControllerError.captureFailed
        }

        pendingTerminalQueueResolution = nil
        lastFinalizedArtifactAuthority = nil
        return true
    }

    /// Starts abort recovery only after the real terminal CoreBluetooth callback has
    /// released same-target attempt quarantine. If the old recorder already owns a
    /// drain, wait for that one drain to settle first; retirement itself then remains
    /// one synchronous MainActor transaction through resolution, recorder installation,
    /// authority publication, and exact gate reopen.
    private func scheduleAbortedFreshTargetSessionRecoveryIfNeeded() {
        guard captureFailed,
              case .abortQuarantined = observationBoundaryQueueGate.phase,
              abortedFreshSessionRecoveryTask == nil,
              targetState.selectedTargetIdentifier != nil,
              !isSelectedTargetAwaitingTerminalCallback else {
            return
        }

        let inFlightDrain = eventDrainTask
        abortedFreshSessionRecoveryTask = Task { @MainActor [weak self] in
            if let inFlightDrain {
                await inFlightDrain.value
            }
            guard let self, !Task.isCancelled else { return }
            defer { self.abortedFreshSessionRecoveryTask = nil }

            do {
                _ = try self.completeAbortedFreshTargetSessionIfReady()
            } catch {
                self.lastDiagnostic = Self.diagnostic(
                    error,
                    fallback: "Aborted capture could not establish an exact fresh durable session."
                )
            }
        }
    }

    /// Converts one exact abort-quarantined lifecycle into a genuinely fresh durable
    /// recorder/session. Retired callbacks advance only `lastResolvedEventSequence`;
    /// `lastProcessedEventSequence` remains recorder-written truth. No await occurs
    /// after FIFO retirement begins, so callback/tail drift cannot slip between proof,
    /// applied frontier, fresh-recorder publication, and gate consumption.
    @discardableResult
    private func completeAbortedFreshTargetSessionIfReady(
        startedAt: Date = Date()
    ) throws -> Bool {
        guard captureFailed,
              case .abortQuarantined = observationBoundaryQueueGate.phase else {
            return false
        }
        guard !artifactReadBarrier.isActive,
              observationBoundaryTask == nil,
              eventDrainTask == nil,
              activePeripheral == nil,
              connectionPhase == .idle else {
            return false
        }
        guard targetState.selectedTargetIdentifier != nil else {
            throw ControllerError.targetNotSelected
        }
        guard !isSelectedTargetAwaitingTerminalCallback else {
            return false
        }

        let retirement = try PassiveCoreBluetoothAbortedObservationQueueRetirement.retire(
            from: &pendingEvents,
            currentLastEnqueuedEventSequence: lastEnqueuedEventSequence,
            currentSettledQueueSequence: lastResolvedEventSequence,
            drainIsIdle: eventDrainTask == nil,
            abortedGate: observationBoundaryQueueGate
        ) { pending in
            PassiveCoreBluetoothAbortedObservationQueueRetirement.PendingEvidenceIdentity(
                queueSequence: pending.queueSequence,
                authority: pending.authority
            )
        }

        let resolution = try PassiveCoreBluetoothAbortedQueueResolution.resolve(
            currentResolvedThroughQueueSequence: lastResolvedEventSequence,
            currentLastEnqueuedEventSequence: lastEnqueuedEventSequence,
            retirementReceipt: retirement,
            abortedGate: observationBoundaryQueueGate
        )
        lastResolvedEventSequence = resolution.resolvedThroughQueueSequence

        let freshSession = try PassiveCoreBluetoothAbortedFreshTargetSession.create(
            after: resolution,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )
        let previousAuthority = currentArtifactAuthorityContext()
        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: freshSession.receipt.targetSessionGeneration,
            authorityGeneration: 1
        )

        do {
            // `lastResolvedEventSequence` above is legitimate retired-FIFO chronology and may
            // remain advanced if recovery fails. Canonical artifact authority must not advance
            // until the exact queue-gate reopen has already succeeded on a detached value copy.
            var reopenedGate = observationBoundaryQueueGate
            try reopenedGate.reopenAfterAbortedFreshTargetSession(
                freshSession.receipt,
                installedRecorder: freshSession.recorder,
                currentResolvedThroughQueueSequence: lastResolvedEventSequence,
                currentLastEnqueuedEventSequence: lastEnqueuedEventSequence
            )
            try artifactAuthorityFence.transition(
                from: previousAuthority,
                to: freshAuthority
            )
            targetSessionGeneration = freshAuthority.targetSessionGeneration
            artifactAuthorityGeneration = freshAuthority.authorityGeneration
            recorder = freshSession.recorder
            hasUsedInitialSessionIdentity = true
            acquisitionLedger.beginTargetSession()
            gattIdentityRegistry.reset()
            selectedTargetCancellationPending = false
            foregroundEvidenceIntegrityValid = true
            committedReadyEpoch = nil
            observationBoundaryQueueGate = reopenedGate
        } catch {
            lastDiagnostic = Self.diagnostic(
                error,
                fallback: "Abort recovery failed while installing exact fresh capture authority."
            )
            throw ControllerError.captureFailed
        }

        // Candidate objects/advertisements predate the recovered durable session.
        // Keep the correlated UUID selection, but require fresh rediscovery before a
        // later connection attempt can proceed on this recorder.
        clearCandidateCatalog()
        pendingTerminalQueueResolution = nil
        lastFinalizedArtifactAuthority = nil
        captureFailed = false
        lastDiagnostic = "Aborted observation epoch retired exactly; fresh capture session is ready for rediscovery."
        return true
    }

    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {
        if targetState.selectedTargetIdentifier == identifier, recorder != nil {
            return
        }

        guard targetSessionGeneration != UInt64.max else {
            throw ControllerError.captureFailed
        }

        let latestAdvertisement = latestAdvertisementByIdentifier[identifier]
        let startedAt = latestAdvertisement?.receivedAtDate
            ?? (!hasUsedInitialSessionIdentity ? firstSessionStartedAtOverride : nil)
            ?? Date()
        let sessionID = hasUsedInitialSessionIdentity ? UUID() : initialSessionID
        let newRecorder = try PassiveCoreBluetoothCaptureRecorder(
            id: sessionID,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )

        guard observationBoundaryQueueGate.resetForNewCaptureSession() else {
            throw ControllerError.captureIncomplete
        }
        committedReadyEpoch = nil

        let previousAuthority = currentArtifactAuthorityContext()
        let nextTargetSessionGeneration = targetSessionGeneration + 1
        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: nextTargetSessionGeneration,
            authorityGeneration: 1
        )
        do {
            // Transition the canonical fence first, then publish the complete
            // durable-session authority pair synchronously with no actor hop.
            try artifactAuthorityFence.transition(
                from: previousAuthority,
                to: freshAuthority
            )
        } catch {
            failCapture(error)
            throw ControllerError.captureFailed
        }
        targetSessionGeneration = freshAuthority.targetSessionGeneration
        artifactAuthorityGeneration = freshAuthority.authorityGeneration
        lastFinalizedArtifactAuthority = nil

        targetState.selectTarget(identifier)
        acquisitionLedger.beginTargetSession()
        gattIdentityRegistry.reset()
        selectedTargetCancellationPending = false
        // Only publication of a genuinely fresh durable recorder/session may
        // restore foreground-only evidence validity after a prior scene loss.
        foregroundEvidenceIntegrityValid = true
        hasUsedInitialSessionIdentity = true
        recorder = newRecorder

        // Preserve at most the selected candidate's latest already-observed
        // advertisement, with the exact callback clocks from when it was actually
        // received. Other broad-scan devices remain candidate-catalog entries only.
        if let latestAdvertisement {
            enqueue(
                .advertisement(latestAdvertisement.observation),
                receivedAtUptimeNanoseconds: latestAdvertisement.receivedAtUptimeNanoseconds,
                receivedAtDate: latestAdvertisement.receivedAtDate
            )
        }
    }

    private func currentArtifactContext() throws -> ArtifactContext {
        try ensureCaptureHealthy()
        guard let recorder else { throw ControllerError.targetNotSelected }
        guard hasCompleteTargetEvidence else { throw ControllerError.captureIncomplete }

        let eventWatermark: UInt64
        switch observationBoundaryQueueGate.phase {
        case .observing:
            eventWatermark = lastEnqueuedEventSequence
        case .terminal:
            guard let terminalQueueCutoff = observationBoundaryQueueGate.terminalQueueCutoff else {
                throw ControllerError.captureIncomplete
            }
            eventWatermark = terminalQueueCutoff
        case .awaitingReady, .drainingReady, .abortQuarantined, .drainingHorizon, .horizonBoundaryRecorded:
            throw ControllerError.captureIncomplete
        }

        return ArtifactContext(
            recorder: recorder,
            authority: currentArtifactAuthorityContext(),
            eventWatermark: eventWatermark
        )
    }

    private func validate(_ context: ArtifactContext) throws {
        try ensureCaptureHealthy()
        guard context.authority.matches(
            targetSessionGeneration: targetSessionGeneration,
            authorityGeneration: artifactAuthorityGeneration
        ) else {
            throw ControllerError.targetSessionChanged
        }
        guard hasCompleteTargetEvidence else {
            throw ControllerError.captureIncomplete
        }
    }

    private func beginArtifactRead(through watermark: UInt64) throws {
        do {
            try artifactReadBarrier.begin(through: watermark)
        } catch PassiveCoreBluetoothArtifactReadBarrier.StateError.alreadyActive {
            throw ControllerError.artifactReadAlreadyActive
        }
    }

    private func endArtifactRead() {
        artifactReadBarrier.end()
        if eventDrainTask == nil, !pendingEvents.isEmpty, !captureFailed {
            startDrainIfNeeded()
        }
        scheduleAbortedFreshTargetSessionRecoveryIfNeeded()
    }

    private func advanceArtifactAuthority() -> Bool {
        // Defense in depth: once H owns the immutable cutoff, no transport path may
        // replace the artifact authority. Callers still perform their own transport
        // cleanup so this guard is not used as lifecycle control flow.
        guard !observationBoundaryBlocksArtifactMutation else { return false }
        guard artifactAuthorityGeneration != UInt64.max else {
            failCapture(AcquisitionError.artifactAuthorityGenerationExhausted)
            return false
        }

        let previousAuthority = currentArtifactAuthorityContext()
        let nextAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: previousAuthority.targetSessionGeneration,
            authorityGeneration: previousAuthority.authorityGeneration + 1
        )
        do {
            // The fence transition is the mutation-point authority. Publish the
            // mirrored MainActor value immediately afterward with no suspension.
            try artifactAuthorityFence.transition(
                from: previousAuthority,
                to: nextAuthority
            )
        } catch {
            failCapture(error)
            return false
        }
        artifactAuthorityGeneration = nextAuthority.authorityGeneration
        lastFinalizedArtifactAuthority = nil

        // #455 deliberately keeps an invalidated committed Ready epoch quarantined
        // until resolved-frontier recovery is composed. Do not silently return the
        // same recorder to awaitingReady or reacquire GATT under a newer authority.
        if case .observing = observationBoundaryQueueGate.phase,
           let committedReadyEpoch {
            do {
                try observationBoundaryQueueGate.abortObservationEpoch(committedReadyEpoch)
                self.committedReadyEpoch = nil
            } catch {
                failCapture(error)
                return false
            }
            failCapture(ControllerError.targetSessionChanged)
            return false
        }
        return true
    }

    private func currentArtifactAuthorityContext() -> PassiveCoreBluetoothArtifactAuthorityContext {
        PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: targetSessionGeneration,
            authorityGeneration: artifactAuthorityGeneration
        )
    }

    /// Horizon admission is the immutable observation cutoff. From the instant the
    /// gate enters drainingHorizon, later transport callbacks are outside the
    /// accepted artifact interval and must not replace artifact authority.
    private var observationBoundaryBlocksArtifactMutation: Bool {
        switch observationBoundaryQueueGate.phase {
        case .drainingHorizon, .horizonBoundaryRecorded, .terminal:
            true
        case .awaitingReady, .drainingReady, .observing, .abortQuarantined:
            false
        }
    }

    /// Starts the Ready transaction synchronously on MainActor as soon as
    /// the finite acquisition ledger reaches its accepted ready state.
    /// The queue cutoff, recorder-completed frontier, authority, and clocks
    /// are frozen before the first actor hop. Later callbacks may enqueue,
    /// but the queue gate keeps them behind this exact prefix until the
    /// durable boundary is recorded.
    private func beginFiniteAcquisitionReadyBoundaryIfNeeded() {
        guard !captureFailed,
              acquisitionLedger.isReady,
              case .awaitingReady = observationBoundaryQueueGate.phase,
              observationBoundaryTask == nil,
              let recorder else { return }

        do {
            let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
                queueCutoff: lastEnqueuedEventSequence,
                processedThrough: lastProcessedEventSequence,
                authorityFence: artifactAuthorityFence,
                gate: &observationBoundaryQueueGate
            )

            observationBoundaryTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.flushPendingEvents(through: admission.queueCutoff)

                do {
                    // The Ready FIFO drain is an actor suspension. Foreground loss may
                    // poison this exact durable capture while it is suspended, so prove
                    // foreground integrity and generic health before the first recorder
                    // attempt. If either fails, consume the exact unused Ready admission
                    // and quarantine its transaction rather than leaving `.drainingReady`.
                    do {
                        try self.requireForegroundEvidenceIntegrity()
                        try self.ensureCaptureHealthy()
                        try self.validateBoundaryAuthority(admission.authority)
                    } catch {
                        let preAttemptFailure = error
                        do {
                            let abandonment = try admission.abandonBeforeRecorderAttempt()
                            try self.observationBoundaryQueueGate.abortReadyBeforeRecorderAttempt(
                                after: abandonment
                            )
                        } catch {
                            // Exact lifecycle-quarantine failure is stronger than the
                            // triggering foreground/health error. Keep capture fail-closed.
                            throw error
                        }
                        throw preAttemptFailure
                    }

                    let outcome = try await admission.recordBoundaryWithMutationOutcome(on: recorder)
                    switch outcome {
                    case let .rejectedBeforeMutation(rejection):
                        try self.observationBoundaryQueueGate.abortUncommittedReady(after: rejection)
                        self.failCapture(ControllerError.targetSessionChanged)

                    case let .recorded(recordedReady):
                        do {
                            try self.requireForegroundEvidenceIntegrity()
                            // This typed queue commit is intentionally the immediate
                            // MainActor statement after the recorder actor returns.
                            // No await is permitted in this interlock.
                            self.committedReadyEpoch = try recordedReady.markBoundaryRecorded(
                                on: &self.observationBoundaryQueueGate,
                                lastProcessedQueueSequence: self.lastProcessedEventSequence
                            )
                        } catch {
                            // Recorder mutation already happened, so quarantine with
                            // the distinct recorded-before-commit origin. Never label
                            // this a zero-mutation rejection.
                            let recordedReadyFailure = error
                            do {
                                _ = try self.observationBoundaryQueueGate.abortRecordedReadyBeforeGateCommit(
                                    recordedReady
                                )
                            } catch {
                                // Exact quarantine failure is stronger lifecycle evidence than
                                // the triggering queue-commit failure. Never suppress it.
                                throw error
                            }
                            throw recordedReadyFailure
                        }
                    }
                } catch {
                    self.failCapture(error)
                }

                self.observationBoundaryTask = nil
                if !self.pendingEvents.isEmpty, !self.captureFailed {
                    self.startDrainIfNeeded()
                }
            }
        } catch {
            failCapture(error)
        }
    }

    private func requireForegroundEvidenceIntegrity() throws {
        guard foregroundEvidenceIntegrityValid else {
            throw ControllerError.captureIncomplete
        }
    }

    private func validateBoundaryAuthority(
        _ authority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws {
        guard authority == currentArtifactAuthorityContext(),
              authority == artifactAuthorityFence.currentAuthority else {
            throw ControllerError.targetSessionChanged
        }
    }

    private func resolveQueuedEvidenceAfterTerminalHorizon() throws
        -> PassiveCoreBluetoothTerminalQueueResolution.Receipt {
        // Retirement validates the complete global H+1...tail suffix and removes
        // only evidence carrying the exact terminal artifact authority. The
        // projection uses authority captured on each queued event, never whichever
        // controller generation happens to be current at cleanup time.
        let retirement = try PassiveCoreBluetoothTerminalQueueRetirement.retire(
            from: &pendingEvents,
            currentLastEnqueuedEventSequence: lastEnqueuedEventSequence,
            terminalGate: observationBoundaryQueueGate
        ) { pending in
            PassiveCoreBluetoothTerminalQueueRetirement.PendingEvidenceIdentity(
                queueSequence: pending.queueSequence,
                authority: pending.authority
            )
        }

        // Convert accepted retirement into explicit resolved-FIFO authority without
        // laundering discarded callbacks into the recorder-written frontier. This
        // consumer is synchronous on MainActor, immediately after retirement, so a
        // new callback cannot make the receipt stale between the two producers.
        let resolution = try PassiveCoreBluetoothTerminalQueueResolution.resolve(
            currentResolvedThroughQueueSequence: lastResolvedEventSequence,
            currentLastEnqueuedEventSequence: lastEnqueuedEventSequence,
            retirementReceipt: retirement,
            terminalGate: observationBoundaryQueueGate
        )
        lastResolvedEventSequence = resolution.resolvedThroughQueueSequence
        return resolution
    }

    private func scheduleConnectionTimeout(for peripheral: CBPeripheral, nanoseconds: UInt64) {
        connectionTimeoutTask?.cancel()
        let identifier = peripheral.identifier
        connectionTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled,
                  let self,
                  let peripheral = self.activePeripheral,
                  peripheral.identifier == identifier,
                  self.connectionPhase == .connecting(identifier),
                  self.targetState.acceptsActiveCallback(from: identifier) else { return }

            if self.observationBoundaryBlocksArtifactMutation {
                // The timeout happened outside the admitted artifact horizon. Retire
                // transport state only; do not append interruption evidence or revoke
                // the authority currently sealing H.
                self.connectionTimeoutTask = nil
                self.selectedTargetCancellationPending = true
                _ = self.targetState.retireActiveAttempt()
                peripheral.delegate = nil
                self.activePeripheral = nil
                self.clearAcquisitionObjects()
                self.connectionPhase = .idle
                self.centralManager.cancelPeripheralConnection(peripheral)
                return
            }

            self.lastDiagnostic = "Connection attempt timed out and was cancelled."
            self.enqueueInterruption("connection attempt timed out")
            if self.targetState.selectedTargetIdentifier == identifier {
                self.selectedTargetCancellationPending = true
                self.acquisitionLedger.finishWithoutGattAcquisition()
                guard self.advanceArtifactAuthority() else { return }
            }
            _ = self.targetState.retireActiveAttempt()
            peripheral.delegate = nil
            self.activePeripheral = nil
            self.clearAcquisitionObjects()
            self.connectionPhase = .idle
            self.connectionTimeoutTask = nil
            self.centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    private func currentAcquisitionWatchdogContext() -> PassiveCoreBluetoothAcquisitionWatchdogContext? {
        guard let peripheral = activePeripheral else { return nil }
        return PassiveCoreBluetoothAcquisitionWatchdogContext(
            peripheralIdentifier: peripheral.identifier,
            targetSessionGeneration: targetSessionGeneration,
            acquisitionGeneration: acquisitionLedger.readiness.generation
        )
    }

    private func refreshAcquisitionWatchdog() {
        cancelAcquisitionWatchdog()
        if acquisitionLedger.isReady {
            beginFiniteAcquisitionReadyBoundaryIfNeeded()
            return
        }
        guard acquisitionLedger.phase == .acquiring,
              let context = currentAcquisitionWatchdogContext() else { return }

        let ticket: PassiveCoreBluetoothAcquisitionWatchdogState.Ticket
        do {
            ticket = try acquisitionWatchdogState.arm(for: context)
        } catch {
            failCapture(error)
            return
        }
        let timeoutNanoseconds = acquisitionProgressTimeoutNanoseconds

        acquisitionWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  self.acquisitionWatchdogState.acceptsExpiry(
                    ticket,
                    currentContext: self.currentAcquisitionWatchdogContext()
                  ),
                  self.acquisitionLedger.phase == .acquiring,
                  self.targetState.acceptsActiveCallback(from: ticket.context.peripheralIdentifier) else { return }

            self.acquisitionWatchdogTask = nil
            self.acquisitionWatchdogState.cancel()
            let pendingOperationCount = self.acquisitionLedger.pendingOperationCount
            let timeoutDiagnostic = "Finite GATT acquisition timed out after no progress; \(pendingOperationCount) finite operation(s) remain pending."
            self.enqueueInterruption("finite GATT acquisition progress timed out")
            self.cancelActiveConnection(cause: .interruptionAlreadyRecorded)
            self.lastDiagnostic = timeoutDiagnostic
        }
    }

    private func cancelAcquisitionWatchdog() {
        acquisitionWatchdogTask?.cancel()
        acquisitionWatchdogTask = nil
        acquisitionWatchdogState.cancel()
    }

    private func beginDiscovery(on peripheral: CBPeripheral) throws {
        clearAcquisitionObjects()
        try acquisitionLedger.beginAcquisition()
        refreshAcquisitionWatchdog()
        peripheral.discoverServices(nil)
    }

    private func newlyScheduledTopologyOperations(
        for service: CBService
    ) -> [PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey] {
        let serviceID = ObjectIdentifier(service)
        var operations: [PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey] = []
        if discoveredIncludedServiceObjectIDs.insert(serviceID).inserted {
            operations.append(.includedServices(serviceID))
        }
        if discoveredCharacteristicServiceObjectIDs.insert(serviceID).inserted {
            operations.append(.characteristics(serviceID))
        }
        return operations
    }

    private func issueTopologyOperations(
        _ operations: [PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey],
        for service: CBService,
        on peripheral: CBPeripheral
    ) {
        for operation in operations {
            switch operation {
            case .includedServices:
                peripheral.discoverIncludedServices(nil, for: service)
            case .characteristics:
                peripheral.discoverCharacteristics(nil, for: service)
            default:
                break
            }
        }
    }

    private func attributeKey(
        for characteristic: CBCharacteristic,
        on peripheral: CBPeripheral
    ) throws -> PassiveCoreBluetoothTargetState.AttributeKey {
        guard let service = characteristic.service else {
            throw AcquisitionError.characteristicMissingService
        }
        return PassiveCoreBluetoothTargetState.AttributeKey(
            peripheralIdentifier: peripheral.identifier,
            serviceUUID: CoreBluetoothCaptureMapping.normalizedUUID(service.uuid),
            characteristicUUID: CoreBluetoothCaptureMapping.normalizedUUID(characteristic.uuid)
        )
    }

    private func validateCurrentService(_ service: CBService) throws {
        let uuid = CoreBluetoothCaptureMapping.normalizedUUID(service.uuid)
        guard gattIdentityRegistry.containsService(uuid: uuid, instance: service) else {
            throw AcquisitionError.serviceNotInCurrentAcquisition
        }
    }

    private func validateCurrentCharacteristic(_ characteristic: CBCharacteristic) throws {
        guard let service = characteristic.service else {
            throw AcquisitionError.characteristicMissingService
        }
        let serviceUUID = CoreBluetoothCaptureMapping.normalizedUUID(service.uuid)
        let characteristicUUID = CoreBluetoothCaptureMapping.normalizedUUID(characteristic.uuid)
        guard gattIdentityRegistry.containsService(uuid: serviceUUID, instance: service),
              gattIdentityRegistry.containsCharacteristic(
                serviceUUID: serviceUUID,
                characteristicUUID: characteristicUUID,
                instance: characteristic
              ) else {
            throw AcquisitionError.characteristicNotInCurrentAcquisition
        }
    }

    private func plannedCharacteristicOperations(
        for characteristic: CBCharacteristic
    ) -> [PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey] {
        let characteristicID = ObjectIdentifier(characteristic)
        let plan = PassiveCoreBluetoothAcquisitionPolicy.plan(for: characteristic)
        var operations: [PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey] = []
        if plan.shouldDiscoverDescriptors {
            operations.append(.descriptors(characteristicID))
        }
        if plan.shouldReadValue {
            operations.append(.read(characteristicID))
        } else if plan.shouldSubscribeForValueUpdates {
            operations.append(.subscription(characteristicID))
        }
        return operations
    }

    private func issueCharacteristicAcquisition(
        _ characteristic: CBCharacteristic,
        on peripheral: CBPeripheral
    ) throws {
        let plan = PassiveCoreBluetoothAcquisitionPolicy.plan(for: characteristic)
        if plan.shouldDiscoverDescriptors {
            peripheral.discoverDescriptors(for: characteristic)
        }

        let key = try attributeKey(for: characteristic, on: peripheral)
        if plan.shouldReadValue {
            targetState.markReadRequested(key)
            peripheral.readValue(for: characteristic)
        } else if plan.shouldSubscribeForValueUpdates {
            targetState.markSubscriptionRequested(key, enabled: true)
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    private func callbackReceipt() -> CallbackReceipt {
        CallbackReceipt(
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            date: Date()
        )
    }

    private func enqueue(_ event: PassiveBluetoothCaptureEvent) {
        let receipt = callbackReceipt()
        enqueue(event, receipt: receipt)
    }

    private func enqueue(_ event: PassiveBluetoothCaptureEvent, receipt: CallbackReceipt) {
        enqueue(
            event,
            receivedAtUptimeNanoseconds: receipt.uptimeNanoseconds,
            receivedAtDate: receipt.date
        )
    }

    private func enqueue(
        _ event: PassiveBluetoothCaptureEvent,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date
    ) {
        guard !captureFailed, let recorder else { return }
        // Transport callbacks still update controller state after a sealed
        // Horizon, but this recorder generation is immutable and accepts no
        // new evidence. A later capture requires a fresh controller/session.
        guard !observationBoundaryQueueGate.isTerminal else { return }
        guard lastEnqueuedEventSequence != UInt64.max else {
            failCapture(AcquisitionError.eventQueueSequenceExhausted)
            return
        }
        lastEnqueuedEventSequence += 1
        pendingEvents.append(
            PendingEvent(
                queueSequence: lastEnqueuedEventSequence,
                recorder: recorder,
                sessionGeneration: targetSessionGeneration,
                authority: currentArtifactAuthorityContext(),
                event: event,
                uptimeNanoseconds: receivedAtUptimeNanoseconds,
                date: receivedAtDate
            )
        )
        startDrainIfNeeded()
    }

    private func enqueueInterruption(_ reason: String, receipt: CallbackReceipt? = nil) {
        do {
            let event = PassiveBluetoothCaptureEvent.interruption(
                try PassiveBluetoothCaptureInterruption(reason: reason)
            )
            if let receipt {
                enqueue(event, receipt: receipt)
            } else {
                enqueue(event)
            }
        } catch {
            failCapture(error)
        }
    }

    private func startDrainIfNeeded() {
        guard eventDrainTask == nil,
              let firstPendingSequence = pendingEvents.first?.queueSequence,
              let pendingTailSequence = pendingEvents.last?.queueSequence,
              let boundaryDrainUpperBound = observationBoundaryQueueGate.permittedDrainUpperBound(
                firstPending: firstPendingSequence,
                pendingTail: pendingTailSequence
              ),
              let artifactDrainUpperBound = artifactReadBarrier.permittedDrainUpperBound(
                firstPending: firstPendingSequence,
                pendingTail: pendingTailSequence
              ) else { return }
        let drainThroughSequence = min(boundaryDrainUpperBound, artifactDrainUpperBound)

        eventDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while let first = self.pendingEvents.first,
                  first.queueSequence <= drainThroughSequence {
                let next = self.pendingEvents.removeFirst()
                var shouldStop = false
                do {
                    try await next.recorder.record(
                        next.event,
                        receivedAtUptimeNanoseconds: next.uptimeNanoseconds,
                        receivedAtDate: next.date
                    )
                } catch {
                    // A discarded previous target session must never poison the
                    // current target if one of its queued records fails later.
                    if next.sessionGeneration == self.targetSessionGeneration {
                        self.failCapture(error)
                        self.pendingEvents.removeAll { $0.sessionGeneration == next.sessionGeneration }
                        shouldStop = true
                    }
                }
                self.lastProcessedEventSequence = max(
                    self.lastProcessedEventSequence,
                    next.queueSequence
                )
                // Normal drain resolves the same queue position by recorder handoff.
                // Terminal retirement may later move only the distinct resolved
                // frontier beyond this recorder-written value.
                self.lastResolvedEventSequence = max(
                    self.lastResolvedEventSequence,
                    next.queueSequence
                )
                if shouldStop { break }
            }
            self.eventDrainTask = nil
            if !self.pendingEvents.isEmpty, !self.captureFailed {
                self.startDrainIfNeeded()
            }
        }
    }

    private func flushPendingEvents(through watermark: UInt64) async {
        while !captureFailed, lastProcessedEventSequence < watermark {
            if eventDrainTask == nil {
                startDrainIfNeeded()
            }
            guard let drain = eventDrainTask else { return }
            await drain.value
        }
    }

    private func failCapture(_ error: Error, fallback: String? = nil) {
        guard !captureFailed else { return }
        captureFailed = true
        if let fallback {
            lastDiagnostic = Self.diagnostic(error, fallback: fallback)
        } else {
            lastDiagnostic = "Capture stopped after evidence/acquisition failure: \(String(describing: error))"
        }
        scanRequested = false
        centralManager.stopScan()
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        observationBoundaryTask?.cancel()
        observationBoundaryTask = nil
        if let activePeripheral {
            _ = targetState.retireActiveAttempt()
            activePeripheral.delegate = nil
            centralManager.cancelPeripheralConnection(activePeripheral)
            self.activePeripheral = nil
        }
        clearAcquisitionObjects()
        connectionPhase = .idle
        // Abort quarantine may be entered by the terminal callback itself.
        // Schedule here so recovery does not depend on a second callback that
        // CoreBluetooth is not required to deliver. The scheduler still refuses
        // to run while any retired same-target attempt awaits its real terminal.
        scheduleAbortedFreshTargetSessionRecoveryIfNeeded()
    }

    private func ensureCaptureHealthy() throws {
        if captureFailed {
            throw ControllerError.captureFailed
        }
    }

    private func clearCandidateCatalog() {
        peripheralByIdentifier.removeAll()
        latestDiscoveryByIdentifier.removeAll()
        latestAdvertisementByIdentifier.removeAll()
    }

    private func clearAcquisitionObjects() {
        cancelAcquisitionWatchdog()
        targetState.resetAcquisitionProvenance()
        gattIdentityRegistry.reset()
        discoveredIncludedServiceObjectIDs.removeAll()
        discoveredCharacteristicServiceObjectIDs.removeAll()
    }

    private func clearActiveConnectionState(for identifier: UUID) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        if activePeripheral?.identifier == identifier {
            activePeripheral?.delegate = nil
            activePeripheral = nil
        }
        clearAcquisitionObjects()
        if connectionPhase == .connecting(identifier) || connectionPhase == .connected(identifier) {
            connectionPhase = .idle
        }
    }

    private static func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: "unknown"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized"
        case .poweredOff: "poweredOff"
        case .poweredOn: "poweredOn"
        @unknown default: "future(\(state.rawValue))"
        }
    }

    private static func diagnostic(_ error: Error?, fallback: String) -> String {
        guard let error else { return fallback }
        let nsError = error as NSError
        return "\(fallback) [\(nsError.domain):\(nsError.code)]"
    }

    private func handleDisconnect(
        _ peripheral: CBPeripheral,
        platformEventTimestamp: TimeInterval?,
        isReconnecting: Bool?,
        error: Error?,
        receipt: CallbackReceipt
    ) {
        let identifier = peripheral.identifier
        let disposition = targetState.completeDisconnect(from: identifier)
        guard disposition != .ignored else { return }

        // After Horizon admission/freeze, consume CoreBluetooth transport cleanup
        // only. The finalized/closing artifact authority is immutable until a real
        // terminal callback has released same-target quarantine. Only then may the
        // exact producer-created fresh recorder consume terminal resolution authority.
        if observationBoundaryQueueGate.isTerminal || observationBoundaryBlocksArtifactMutation {
            selectedTargetCancellationPending = false
            if case .active = disposition {
                clearActiveConnectionState(for: identifier)
            }
            do {
                _ = try completeTerminalFreshTargetSessionIfReady()
            } catch {
                failCapture(error)
            }
            return
        }

        // Abort quarantine is recoverable only after this real terminal callback has
        // cleared the old attempt's same-identifier quarantine. Do not enqueue the
        // callback into the abandoned recorder or advance its authority again.
        if case .abortQuarantined = observationBoundaryQueueGate.phase {
            selectedTargetCancellationPending = false
            if case .active = disposition {
                clearActiveConnectionState(for: identifier)
            }
            scheduleAbortedFreshTargetSessionRecoveryIfNeeded()
            return
        }

        // A retired target may disconnect after the operator has already selected
        // B. Consume its quarantine but never append A evidence to B's recorder.
        if targetState.selectedTargetIdentifier == identifier {
            selectedTargetCancellationPending = false
            if !acquisitionLedger.isReady {
                acquisitionLedger.finishWithoutGattAcquisition()
            }
            guard advanceArtifactAuthority() else { return }
            do {
                enqueue(
                    .connection(
                        try CoreBluetoothCaptureMapping.connection(
                            peripheralIdentifier: identifier,
                            state: .disconnected,
                            platformEventTimestamp: platformEventTimestamp,
                            isReconnecting: isReconnecting,
                            error: error
                        )
                    ),
                    receipt: receipt
                )
            } catch {
                failCapture(error)
                return
            }
            if case .active = disposition {
                lastDiagnostic = Self.diagnostic(error, fallback: "Peripheral disconnected.")
            }
        }

        if case .active = disposition {
            clearActiveConnectionState(for: identifier)
        }
    }
}

extension ForegroundCoreBluetoothCaptureController: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let receipt = callbackReceipt()
        let previous = bluetoothState
        bluetoothState = central.state

        if hasObservedInitialCentralState, previous != central.state,
           !observationBoundaryQueueGate.isTerminal,
           !observationBoundaryBlocksArtifactMutation {
            if hasTargetSession, !advanceArtifactAuthority() { return }
            enqueueInterruption(
                "Bluetooth central state changed \(Self.stateDescription(previous)) -> \(Self.stateDescription(central.state))",
                receipt: receipt
            )
        }
        hasObservedInitialCentralState = true

        guard central.state == .poweredOn else {
            scanRequested = false
            if central.isScanning {
                central.stopScan()
            }
            if activePeripheral != nil {
                activePeripheral?.delegate = nil
                activePeripheral = nil
                connectionTimeoutTask?.cancel()
                connectionTimeoutTask = nil
                connectionPhase = .idle
                clearAcquisitionObjects()
            }
            if hasTargetSession, !acquisitionLedger.isReady {
                acquisitionLedger.finishWithoutGattAcquisition()
            }
            selectedTargetCancellationPending = false
            targetState.resetForCentralInvalidation()
            // CoreBluetooth transport objects discovered before this central
            // invalidation are not treated as fresh candidates afterward.
            clearCandidateCatalog()
            return
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard PassiveCoreBluetoothDiscoveryAdmissionPolicy.accepts(
            callbackIsFromActiveManager: central === centralManager,
            isPoweredOn: central.state == .poweredOn,
            isScanning: scanRequested && central.isScanning
        ) else { return }
        guard !observationBoundaryBlocksArtifactMutation else { return }

        let receipt = callbackReceipt()
        let normalizedRSSI = DiscoveredPeripheral.normalizedRSSI(RSSI.intValue)

        peripheralByIdentifier[peripheral.identifier] = peripheral
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        let discovery = DiscoveredPeripheral(
            id: peripheral.identifier,
            localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name,
            rssi: normalizedRSSI,
            isConnectable: connectable
        )
        latestDiscoveryByIdentifier[peripheral.identifier] = discovery

        do {
            let observation = try CoreBluetoothCaptureMapping.advertisement(
                peripheralIdentifier: peripheral.identifier,
                advertisementData: advertisementData,
                rssi: RSSI
            )
            latestAdvertisementByIdentifier[peripheral.identifier] = CandidateAdvertisement(
                observation: observation,
                receivedAtUptimeNanoseconds: receipt.uptimeNanoseconds,
                receivedAtDate: receipt.date
            )
            if targetState.selectedTargetIdentifier == peripheral.identifier, recorder != nil {
                enqueue(.advertisement(observation), receipt: receipt)
            }
        } catch {
            // Broad discovery remains a candidate catalog before target selection.
            // A malformed candidate observation cannot make an as-yet nonexistent
            // target artifact fail; once selected, the same mapping failure is a
            // target acquisition failure and therefore fails closed.
            if targetState.selectedTargetIdentifier == peripheral.identifier, recorder != nil {
                failCapture(error, fallback: "Selected-target advertisement mapping failed.")
            } else {
                lastDiagnostic = Self.diagnostic(error, fallback: "Candidate advertisement mapping failed.")
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let receipt = callbackReceipt()
        let identifier = peripheral.identifier
        guard targetState.acceptsActiveCallback(from: identifier),
              targetState.selectedTargetIdentifier == identifier else { return }

        if observationBoundaryBlocksArtifactMutation {
            // A connect callback that arrives after H admission belongs to transport
            // cleanup, not a new finite-acquisition epoch inside the sealed artifact.
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            selectedTargetCancellationPending = true
            _ = targetState.retireActiveAttempt()
            peripheral.delegate = nil
            activePeripheral = nil
            clearAcquisitionObjects()
            connectionPhase = .idle
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        activePeripheral = peripheral
        peripheral.delegate = self
        connectionPhase = .connected(identifier)

        do {
            enqueue(
                .connection(
                    try CoreBluetoothCaptureMapping.connection(
                        peripheralIdentifier: identifier,
                        state: .connected
                    )
                ),
                receipt: receipt
            )
            try beginDiscovery(on: peripheral)
        } catch {
            failCapture(error)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        let identifier = peripheral.identifier
        let disposition = targetState.completeFailedConnection(from: identifier)
        guard disposition != .ignored else { return }

        if observationBoundaryBlocksArtifactMutation {
            // This terminal transport callback arrived outside H. Consume transport
            // state only and preserve the authority of the closing artifact. A failed
            // connect is also a real same-attempt terminal callback, so once target-state
            // quarantine is released it must drive the same fresh-session completion seam
            // as disconnect rather than leaving a finalized capture stuck terminal.
            selectedTargetCancellationPending = false
            if case .active = disposition {
                clearActiveConnectionState(for: identifier)
            }
            do {
                _ = try completeTerminalFreshTargetSessionIfReady()
            } catch {
                failCapture(error)
            }
            return
        }

        if case .abortQuarantined = observationBoundaryQueueGate.phase {
            selectedTargetCancellationPending = false
            if case .active = disposition {
                clearActiveConnectionState(for: identifier)
            }
            scheduleAbortedFreshTargetSessionRecoveryIfNeeded()
            return
        }

        if targetState.selectedTargetIdentifier == identifier {
            selectedTargetCancellationPending = false
            if !acquisitionLedger.isReady {
                acquisitionLedger.finishWithoutGattAcquisition()
            }
            guard advanceArtifactAuthority() else { return }
            do {
                enqueue(
                    .connection(
                        try CoreBluetoothCaptureMapping.connection(
                            peripheralIdentifier: identifier,
                            state: .failedToConnect,
                            error: error
                        )
                    ),
                    receipt: receipt
                )
            } catch {
                failCapture(error)
                return
            }
            if case .active = disposition {
                lastDiagnostic = Self.diagnostic(error, fallback: "Failed to connect to peripheral.")
            }
        }

        if case .active = disposition {
            clearActiveConnectionState(for: identifier)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        handleDisconnect(
            peripheral,
            platformEventTimestamp: nil,
            isReconnecting: nil,
            error: error,
            receipt: receipt
        )
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        handleDisconnect(
            peripheral,
            platformEventTimestamp: TimeInterval(timestamp),
            isReconnecting: isReconnecting,
            error: error,
            receipt: receipt
        )
    }
}

extension ForegroundCoreBluetoothCaptureController: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
        guard !observationBoundaryBlocksArtifactMutation else { return }
        if let error {
            failCapture(error, fallback: "Service discovery failed; capture is incomplete.")
            return
        }
        guard let services = peripheral.services else {
            failCapture(AcquisitionError.missingServices, fallback: "Service discovery completed without a services collection; capture is incomplete.")
            return
        }

        var plans: [(CBService, [PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey])] = []
        var childOperations: [PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey] = []
        do {
            for service in services {
                let serviceUUID = CoreBluetoothCaptureMapping.normalizedUUID(service.uuid)
                try gattIdentityRegistry.registerService(uuid: serviceUUID, instance: service)
                enqueue(
                    .service(try CoreBluetoothCaptureMapping.service(
                        peripheralIdentifier: peripheral.identifier,
                        service: service
                    )),
                    receipt: receipt
                )
                let operations = newlyScheduledTopologyOperations(for: service)
                plans.append((service, operations))
                childOperations.append(contentsOf: operations)
            }
            try acquisitionLedger.complete(.services, starting: childOperations)
            refreshAcquisitionWatchdog()
        } catch {
            failCapture(error)
            return
        }

        for (service, operations) in plans {
            issueTopologyOperations(operations, for: service, on: peripheral)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverIncludedServicesFor service: CBService,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
        guard !observationBoundaryBlocksArtifactMutation else { return }
        if let error {
            failCapture(error, fallback: "Included-service discovery failed; capture is incomplete.")
            return
        }
        guard let includedServices = service.includedServices else {
            failCapture(AcquisitionError.missingIncludedServices, fallback: "Included-service discovery completed without a collection; capture is incomplete.")
            return
        }

        var plans: [(CBService, [PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey])] = []
        var childOperations: [PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey] = []
        do {
            try validateCurrentService(service)
            for included in includedServices {
                let includedUUID = CoreBluetoothCaptureMapping.normalizedUUID(included.uuid)
                try gattIdentityRegistry.registerService(uuid: includedUUID, instance: included)
                enqueue(
                    .includedService(try CoreBluetoothCaptureMapping.includedService(
                        peripheralIdentifier: peripheral.identifier,
                        parentService: service,
                        includedService: included
                    )),
                    receipt: receipt
                )
                let operations = newlyScheduledTopologyOperations(for: included)
                plans.append((included, operations))
                childOperations.append(contentsOf: operations)
            }
            try acquisitionLedger.complete(
                .includedServices(ObjectIdentifier(service)),
                starting: childOperations
            )
            refreshAcquisitionWatchdog()
        } catch {
            failCapture(error)
            return
        }

        for (included, operations) in plans {
            issueTopologyOperations(operations, for: included, on: peripheral)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
        guard !observationBoundaryBlocksArtifactMutation else { return }
        if let error {
            failCapture(error, fallback: "Characteristic discovery failed; capture is incomplete.")
            return
        }
        guard let characteristics = service.characteristics else {
            failCapture(AcquisitionError.missingCharacteristics, fallback: "Characteristic discovery completed without a collection; capture is incomplete.")
            return
        }

        var childOperations: [PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey] = []
        do {
            try validateCurrentService(service)
            for characteristic in characteristics {
                let serviceUUID = CoreBluetoothCaptureMapping.normalizedUUID(service.uuid)
                let characteristicUUID = CoreBluetoothCaptureMapping.normalizedUUID(characteristic.uuid)
                try gattIdentityRegistry.registerCharacteristic(
                    serviceUUID: serviceUUID,
                    characteristicUUID: characteristicUUID,
                    instance: characteristic
                )
                enqueue(
                    .characteristic(try CoreBluetoothCaptureMapping.characteristic(
                        peripheralIdentifier: peripheral.identifier,
                        characteristic: characteristic
                    )),
                    receipt: receipt
                )
                childOperations.append(contentsOf: plannedCharacteristicOperations(for: characteristic))
            }
            try acquisitionLedger.complete(
                .characteristics(ObjectIdentifier(service)),
                starting: childOperations
            )
            refreshAcquisitionWatchdog()
        } catch {
            failCapture(error)
            return
        }

        for characteristic in characteristics {
            do {
                try issueCharacteristicAcquisition(characteristic, on: peripheral)
            } catch {
                failCapture(error)
                return
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverDescriptorsFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
        guard !observationBoundaryBlocksArtifactMutation else { return }
        if let error {
            failCapture(error, fallback: "Descriptor discovery failed; capture is incomplete.")
            return
        }
        guard let descriptors = characteristic.descriptors else {
            failCapture(AcquisitionError.missingDescriptors, fallback: "Descriptor discovery completed without a collection; capture is incomplete.")
            return
        }

        do {
            try validateCurrentCharacteristic(characteristic)
            guard let service = characteristic.service else {
                throw AcquisitionError.characteristicMissingService
            }
            let serviceUUID = CoreBluetoothCaptureMapping.normalizedUUID(service.uuid)
            let characteristicUUID = CoreBluetoothCaptureMapping.normalizedUUID(characteristic.uuid)
            for descriptor in descriptors {
                try gattIdentityRegistry.registerDescriptor(
                    serviceUUID: serviceUUID,
                    characteristicUUID: characteristicUUID,
                    descriptorUUID: CoreBluetoothCaptureMapping.normalizedUUID(descriptor.uuid),
                    instance: descriptor
                )
                enqueue(
                    .descriptor(try CoreBluetoothCaptureMapping.descriptor(
                        peripheralIdentifier: peripheral.identifier,
                        descriptor: descriptor
                    )),
                    receipt: receipt
                )
            }
            try acquisitionLedger.complete(.descriptors(ObjectIdentifier(characteristic)))
            refreshAcquisitionWatchdog()
        } catch {
            failCapture(error)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
        guard !observationBoundaryBlocksArtifactMutation else { return }

        let key: PassiveCoreBluetoothTargetState.AttributeKey
        do {
            try validateCurrentCharacteristic(characteristic)
            key = try attributeKey(for: characteristic, on: peripheral)
        } catch {
            failCapture(error)
            return
        }

        let characteristicID = ObjectIdentifier(characteristic)
        let readOperation = PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey.read(characteristicID)
        let readIsPending = acquisitionLedger.isPending(readOperation)

        if readIsPending, characteristic.isNotifying {
            failCapture(
                AcquisitionError.ambiguousReadWhileAlreadyNotifying,
                fallback: "A tracked read callback arrived while the characteristic was already notifying; provenance is ambiguous."
            )
            return
        }
        if let error {
            failCapture(error, fallback: "Characteristic value acquisition failed; capture is incomplete.")
            return
        }
        guard let payload = characteristic.value else {
            failCapture(
                AcquisitionError.missingCharacteristicValue,
                fallback: "Characteristic value callback had no payload; capture is incomplete."
            )
            return
        }

        let origin: PassiveBluetoothValueOrigin
        if readIsPending {
            guard targetState.consumeReadRequest(key) else {
                failCapture(AcquisitionError.readProvenanceMismatch)
                return
            }
            origin = .readResponse
        } else if characteristic.isNotifying {
            origin = .subscriptionUpdate
        } else {
            failCapture(
                AcquisitionError.unattributedCharacteristicValue,
                fallback: "Unattributed characteristic value callback; capture is incomplete."
            )
            return
        }

        do {
            enqueue(
                .value(try CoreBluetoothCaptureMapping.value(
                    peripheralIdentifier: peripheral.identifier,
                    characteristic: characteristic,
                    origin: origin,
                    payload: payload
                )),
                receipt: receipt
            )

            if readIsPending {
                let plan = PassiveCoreBluetoothAcquisitionPolicy.plan(for: characteristic)
                if plan.shouldSubscribeForValueUpdates {
                    let subscriptionOperation = PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey.subscription(characteristicID)
                    try acquisitionLedger.complete(readOperation, starting: [subscriptionOperation])
                    targetState.markSubscriptionRequested(key, enabled: true)
                    peripheral.setNotifyValue(true, for: characteristic)
                } else {
                    try acquisitionLedger.complete(readOperation)
                }
                refreshAcquisitionWatchdog()
            }
        } catch {
            failCapture(error)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
        guard !observationBoundaryBlocksArtifactMutation else { return }

        let key: PassiveCoreBluetoothTargetState.AttributeKey
        do {
            try validateCurrentCharacteristic(characteristic)
            key = try attributeKey(for: characteristic, on: peripheral)
        } catch {
            failCapture(error)
            return
        }
        let requestedEnabled = targetState.consumeSubscriptionRequest(key)
        let operation = PassiveCoreBluetoothAcquisitionOperationLedger.OperationKey.subscription(
            ObjectIdentifier(characteristic)
        )
        let subscriptionIsPending = acquisitionLedger.isPending(operation)

        do {
            enqueue(
                .subscription(
                    try CoreBluetoothCaptureMapping.subscription(
                        peripheralIdentifier: peripheral.identifier,
                        characteristic: characteristic,
                        requestedEnabled: requestedEnabled,
                        error: error
                    )
                ),
                receipt: receipt
            )
        } catch {
            failCapture(error)
            return
        }

        if let error {
            failCapture(error, fallback: "Notification subscription failed; capture is incomplete.")
            return
        }

        if subscriptionIsPending {
            guard let requestedEnabled else {
                failCapture(AcquisitionError.subscriptionProvenanceMismatch)
                return
            }
            guard requestedEnabled == characteristic.isNotifying else {
                failCapture(
                    AcquisitionError.subscriptionStateMismatch,
                    fallback: "Notification-state callback did not reach the state requested by this acquisition."
                )
                return
            }
            do {
                try acquisitionLedger.complete(operation)
                refreshAcquisitionWatchdog()
            } catch {
                failCapture(error)
            }
        } else if requestedEnabled != nil {
            failCapture(AcquisitionError.subscriptionProvenanceMismatch)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
        if observationBoundaryQueueGate.isTerminal || observationBoundaryBlocksArtifactMutation {
            return
        }

        let uuids = invalidatedServices
            .map { CoreBluetoothCaptureMapping.normalizedUUID($0.uuid) }
            .joined(separator: ",")
        enqueueInterruption(
            uuids.isEmpty
                ? "GATT services invalidated"
                : "GATT services invalidated: \(uuids)",
            receipt: receipt
        )

        guard acquisitionLedger.phase == .ready else {
            failCapture(
                AcquisitionError.serviceInvalidatedDuringAcquisition,
                fallback: "GATT services changed before the current acquisition drained; callback generations are ambiguous."
            )
            return
        }
        guard advanceArtifactAuthority() else { return }

        do {
            try beginDiscovery(on: peripheral)
        } catch {
            failCapture(error)
        }
    }
}
