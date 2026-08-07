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
        case targetNotSelected
        case peripheralAwaitingTerminalCallback(UUID)
        case attemptGenerationExhausted
        case targetSessionChanged
        case artifactReadAlreadyActive
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
    public private(set) var isScanning = false
    public private(set) var connectionPhase: ConnectionPhase = .idle
    public private(set) var discoveredPeripherals: [DiscoveredPeripheral] = []
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
            && acquisitionLedger.isReady
            && !selectedTargetCancellationPending
    }

    private let vehicleIdentity: VehicleIdentity
    private let initialSessionID: UUID
    private let firstSessionStartedAtOverride: Date?
    private let acquisitionProgressTimeoutNanoseconds: UInt64
    private var hasUsedInitialSessionIdentity = false
    private var recorder: PassiveCoreBluetoothCaptureRecorder?
    private var targetSessionGeneration: UInt64 = 0
    private var artifactAuthorityGeneration: UInt64 = 0
    private var targetState = PassiveCoreBluetoothTargetState()
    private var acquisitionLedger = PassiveCoreBluetoothAcquisitionOperationLedger()
    private var gattIdentityRegistry = PassiveCoreBluetoothGATTIdentityRegistry()
    private var selectedTargetCancellationPending = false

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
    private var lastProcessedEventSequence: UInt64 = 0
    private var artifactReadBarrier = PassiveCoreBluetoothArtifactReadBarrier()

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
    }

    /// Starts an explicit foreground research scan. Every explicit scan owns a
    /// fresh in-memory candidate epoch: CoreBluetooth objects observed by a
    /// previous stopped scan are not left selectable as if freshly rediscovered.
    public func startScanning(captureAdvertisementCadence: Bool = false) throws {
        try ensureCaptureHealthy()
        guard centralManager.state == .poweredOn else {
            throw ControllerError.bluetoothNotPoweredOn
        }

        clearCandidateCatalog()
        centralManager.scanForPeripherals(
            withServices: PassiveCoreBluetoothAcquisitionPolicy.foregroundResearchServiceFilter,
            options: PassiveCoreBluetoothAcquisitionPolicy.foregroundResearchScanOptions(
                captureAdvertisementCadence: captureAdvertisementCadence
            )
        )
        isScanning = true
    }

    public func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    /// Explicitly selects the observed peripheral as the current research target
    /// and starts a finite connection attempt. Selecting a different candidate
    /// starts a new durable capture session rather than mixing devices.
    public func connect(
        to peripheralIdentifier: UUID,
        timeout: TimeInterval = 12
    ) throws {
        try ensureCaptureHealthy()
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

    /// Cancels the active attempt without allowing a subsequent attempt to the
    /// same CoreBluetooth peripheral until one of its terminal callbacks arrives.
    /// A different selected target may start immediately and late callbacks from
    /// the cancelled target are ignored for that new session.
    public func cancelActiveConnection() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        guard let peripheral = activePeripheral else { return }
        lastDiagnostic = "Connection cancellation requested."

        if targetState.selectedTargetIdentifier == peripheral.identifier {
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
        guard recorder != nil else { throw ControllerError.targetNotSelected }
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
        return data
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

        targetState.selectTarget(identifier)
        acquisitionLedger.beginTargetSession()
        gattIdentityRegistry.reset()
        selectedTargetCancellationPending = false
        hasUsedInitialSessionIdentity = true
        targetSessionGeneration += 1
        recorder = newRecorder
        guard advanceArtifactAuthority() else {
            throw ControllerError.captureFailed
        }

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
        return ArtifactContext(
            recorder: recorder,
            authority: PassiveCoreBluetoothArtifactAuthorityContext(
                targetSessionGeneration: targetSessionGeneration,
                authorityGeneration: artifactAuthorityGeneration
            ),
            eventWatermark: lastEnqueuedEventSequence
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
    }

    private func advanceArtifactAuthority() -> Bool {
        guard artifactAuthorityGeneration != UInt64.max else {
            failCapture(AcquisitionError.artifactAuthorityGenerationExhausted)
            return false
        }
        artifactAuthorityGeneration += 1
        return true
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
            self.cancelActiveConnection()
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
              let drainThroughSequence = artifactReadBarrier.permittedDrainUpperBound(
                firstPending: firstPendingSequence,
                pendingTail: pendingTailSequence
              ) else { return }

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
        centralManager.stopScan()
        isScanning = false
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        if let activePeripheral {
            _ = targetState.retireActiveAttempt()
            activePeripheral.delegate = nil
            centralManager.cancelPeripheralConnection(activePeripheral)
            self.activePeripheral = nil
        }
        clearAcquisitionObjects()
        connectionPhase = .idle
    }

    private func ensureCaptureHealthy() throws {
        if captureFailed {
            throw ControllerError.captureFailed
        }
    }

    private func updateDiscoveryList() {
        discoveredPeripherals = latestDiscoveryByIdentifier.values.sorted {
            DiscoveredPeripheral.sortsBefore($0, $1)
        }
    }

    private func clearCandidateCatalog() {
        peripheralByIdentifier.removeAll()
        latestDiscoveryByIdentifier.removeAll()
        latestAdvertisementByIdentifier.removeAll()
        updateDiscoveryList()
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

        if hasObservedInitialCentralState, previous != central.state {
            if hasTargetSession, !advanceArtifactAuthority() { return }
            enqueueInterruption(
                "Bluetooth central state changed \(Self.stateDescription(previous)) -> \(Self.stateDescription(central.state))",
                receipt: receipt
            )
        }
        hasObservedInitialCentralState = true

        guard central.state == .poweredOn else {
            if isScanning {
                central.stopScan()
                isScanning = false
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
        updateDiscoveryList()

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
