@preconcurrency import CoreBluetooth
import Dispatch
import Foundation
import NembraCore

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
        public let rssi: Int
        public let isConnectable: Bool?

        public init(id: UUID, localName: String?, rssi: Int, isConnectable: Bool?) {
            self.id = id
            self.localName = localName
            self.rssi = rssi
            self.isConnectable = isConnectable
        }
    }

    public enum ControllerError: Error, Equatable, Sendable {
        case bluetoothNotPoweredOn
        case unknownPeripheral(UUID)
        case peripheralNotConnectable(UUID)
        case connectionAlreadyActive
        case invalidConnectionTimeout
        case targetNotSelected
        case peripheralAwaitingTerminalCallback(UUID)
        case attemptGenerationExhausted
        case targetSessionChanged
        case captureFailed
    }

    private enum AcquisitionError: Error, Equatable, Sendable {
        case characteristicMissingService
        case missingCharacteristicValue
        case unattributedCharacteristicValue
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

    public var hasTargetSession: Bool {
        recorder != nil
    }

    private let vehicleIdentity: VehicleIdentity
    private let initialSessionID: UUID
    private let initialStartedAt: Date
    private var hasUsedInitialSessionIdentity = false
    private var recorder: PassiveCoreBluetoothCaptureRecorder?
    private var targetSessionGeneration: UInt64 = 0
    private var targetState = PassiveCoreBluetoothTargetState()

    private var centralManager: CBCentralManager!
    private var peripheralByIdentifier: [UUID: CBPeripheral] = [:]
    private var latestDiscoveryByIdentifier: [UUID: DiscoveredPeripheral] = [:]
    private var latestAdvertisementByIdentifier: [UUID: PassiveBluetoothAdvertisementObservation] = [:]
    private var activePeripheral: CBPeripheral?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var discoveredIncludedServiceObjectIDs: Set<ObjectIdentifier> = []
    private var discoveredCharacteristicServiceObjectIDs: Set<ObjectIdentifier> = []
    private var hasObservedInitialCentralState = false

    private struct PendingEvent {
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

    public init(
        vehicleIdentity: VehicleIdentity,
        sessionID: UUID = UUID(),
        startedAt: Date = Date(),
        centralManagerOptions: [String: Any]? = nil
    ) throws {
        self.vehicleIdentity = vehicleIdentity
        initialSessionID = sessionID
        initialStartedAt = startedAt
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
        eventDrainTask?.cancel()
    }

    /// Starts an explicit foreground research scan. The initial physical
    /// fingerprint is intentionally unfiltered because ES80 service identity is
    /// not yet verified. Duplicate advertisements are opt-in for cadence study.
    /// Discoveries populate only an in-memory candidate catalog until one target
    /// is explicitly selected through `connect(to:)`.
    public func startScanning(captureAdvertisementCadence: Bool = false) throws {
        try ensureCaptureHealthy()
        guard centralManager.state == .poweredOn else {
            throw ControllerError.bluetoothNotPoweredOn
        }

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
        try ensureCaptureHealthy()
        let (recorder, generation) = try currentRecorder()
        await flushPendingEvents()
        try ensureCaptureHealthy()
        guard generation == targetSessionGeneration else {
            throw ControllerError.targetSessionChanged
        }
        return await recorder.snapshot()
    }

    public func encodedCaptureJSON(prettyPrinted: Bool = true) async throws -> Data {
        try ensureCaptureHealthy()
        let (recorder, generation) = try currentRecorder()
        await flushPendingEvents()
        try ensureCaptureHealthy()
        guard generation == targetSessionGeneration else {
            throw ControllerError.targetSessionChanged
        }
        return try await recorder.encodedJSON(prettyPrinted: prettyPrinted)
    }

    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {
        if targetState.selectedTargetIdentifier == identifier, recorder != nil {
            return
        }

        guard targetSessionGeneration != UInt64.max else {
            throw ControllerError.captureFailed
        }

        targetState.selectTarget(identifier)
        let sessionID = hasUsedInitialSessionIdentity ? UUID() : initialSessionID
        let startedAt = hasUsedInitialSessionIdentity ? Date() : initialStartedAt
        let newRecorder = try PassiveCoreBluetoothCaptureRecorder(
            id: sessionID,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )
        hasUsedInitialSessionIdentity = true
        targetSessionGeneration += 1
        recorder = newRecorder

        // Preserve at most the selected candidate's latest advertisement as the
        // first target-scoped evidence. Other broad-scan devices remain catalog
        // entries only and can never enter this recorder.
        if let advertisement = latestAdvertisementByIdentifier[identifier] {
            enqueue(.advertisement(advertisement))
        }
    }

    private func currentRecorder() throws -> (PassiveCoreBluetoothCaptureRecorder, UInt64) {
        guard let recorder else { throw ControllerError.targetNotSelected }
        return (recorder, targetSessionGeneration)
    }

    private func scheduleConnectionTimeout(for peripheral: CBPeripheral, nanoseconds: UInt64) {
        connectionTimeoutTask?.cancel()
        let identifier = peripheral.identifier
        connectionTimeoutTask = Task { @MainActor [weak self, weak peripheral] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled,
                  let self,
                  let peripheral,
                  self.connectionPhase == .connecting(identifier),
                  self.targetState.acceptsActiveCallback(from: identifier) else { return }

            self.lastDiagnostic = "Connection attempt timed out and was cancelled."
            self.enqueueInterruption("connection attempt timed out")
            _ = self.targetState.retireActiveAttempt()
            peripheral.delegate = nil
            self.activePeripheral = nil
            self.clearAcquisitionObjects()
            self.connectionPhase = .idle
            self.connectionTimeoutTask = nil
            self.centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    private func beginDiscovery(on peripheral: CBPeripheral) {
        targetState.resetAcquisitionProvenance()
        discoveredIncludedServiceObjectIDs.removeAll()
        discoveredCharacteristicServiceObjectIDs.removeAll()
        peripheral.discoverServices(nil)
    }

    private func discoverTopology(for service: CBService, on peripheral: CBPeripheral) {
        let serviceID = ObjectIdentifier(service)
        if discoveredIncludedServiceObjectIDs.insert(serviceID).inserted {
            peripheral.discoverIncludedServices(nil, for: service)
        }
        if discoveredCharacteristicServiceObjectIDs.insert(serviceID).inserted {
            peripheral.discoverCharacteristics(nil, for: service)
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

    private func acquirePassively(
        _ characteristic: CBCharacteristic,
        on peripheral: CBPeripheral
    ) throws {
        let plan = PassiveCoreBluetoothAcquisitionPolicy.plan(for: characteristic)
        if plan.shouldDiscoverDescriptors {
            peripheral.discoverDescriptors(for: characteristic)
        }

        let key = try attributeKey(for: characteristic, on: peripheral)
        if plan.shouldReadValue {
            // Track the request before calling CoreBluetooth so a callback can be
            // classified as a read response only when this adapter actually has
            // an outstanding read identity for the same target/GATT path.
            targetState.markReadRequested(key)
            peripheral.readValue(for: characteristic)
        } else if plan.shouldSubscribeForValueUpdates {
            targetState.markSubscriptionRequested(key, enabled: true)
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    private func subscribeAfterInitialReadIfNeeded(
        _ characteristic: CBCharacteristic,
        on peripheral: CBPeripheral
    ) throws {
        let plan = PassiveCoreBluetoothAcquisitionPolicy.plan(for: characteristic)
        if plan.shouldSubscribeForValueUpdates {
            let key = try attributeKey(for: characteristic, on: peripheral)
            targetState.markSubscriptionRequested(key, enabled: true)
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    private func enqueue(_ event: PassiveBluetoothCaptureEvent) {
        guard !captureFailed, let recorder else { return }
        pendingEvents.append(
            PendingEvent(
                recorder: recorder,
                sessionGeneration: targetSessionGeneration,
                event: event,
                uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                date: Date()
            )
        )
        startDrainIfNeeded()
    }

    private func enqueueInterruption(_ reason: String) {
        do {
            enqueue(.interruption(try PassiveBluetoothCaptureInterruption(reason: reason)))
        } catch {
            failCapture(error)
        }
    }

    private func startDrainIfNeeded() {
        guard eventDrainTask == nil, !pendingEvents.isEmpty else { return }
        eventDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !self.pendingEvents.isEmpty {
                let next = self.pendingEvents.removeFirst()
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
                        break
                    }
                }
            }
            self.eventDrainTask = nil
            if !self.pendingEvents.isEmpty {
                self.startDrainIfNeeded()
            }
        }
    }

    private func flushPendingEvents() async {
        while let drain = eventDrainTask {
            await drain.value
        }
        if !pendingEvents.isEmpty {
            startDrainIfNeeded()
            await flushPendingEvents()
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
        discoveredPeripherals = latestDiscoveryByIdentifier.values.sorted { lhs, rhs in
            if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func clearAcquisitionObjects() {
        targetState.resetAcquisitionProvenance()
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
        error: Error?
    ) {
        let identifier = peripheral.identifier
        let disposition = targetState.completeDisconnect(from: identifier)
        guard disposition != .ignored else { return }

        // A retired target may disconnect after the operator has already selected
        // B. Consume its quarantine but never append A evidence to B's recorder.
        if targetState.selectedTargetIdentifier == identifier {
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
                    )
                )
            } catch {
                failCapture(error)
                return
            }
            lastDiagnostic = Self.diagnostic(error, fallback: "Peripheral disconnected.")
        }

        if case .active = disposition {
            clearActiveConnectionState(for: identifier)
        }
    }
}

extension ForegroundCoreBluetoothCaptureController: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let previous = bluetoothState
        bluetoothState = central.state

        if hasObservedInitialCentralState, previous != central.state {
            enqueueInterruption(
                "Bluetooth central state changed \(Self.stateDescription(previous)) -> \(Self.stateDescription(central.state))"
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
            targetState.resetForCentralInvalidation()
            return
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        peripheralByIdentifier[peripheral.identifier] = peripheral
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        let discovery = DiscoveredPeripheral(
            id: peripheral.identifier,
            localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name,
            rssi: RSSI.intValue,
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
            latestAdvertisementByIdentifier[peripheral.identifier] = observation
            if targetState.selectedTargetIdentifier == peripheral.identifier, recorder != nil {
                enqueue(.advertisement(observation))
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
                )
            )
        } catch {
            failCapture(error)
            return
        }
        beginDiscovery(on: peripheral)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let identifier = peripheral.identifier
        let disposition = targetState.completeFailedConnection(from: identifier)
        guard disposition != .ignored else { return }

        if targetState.selectedTargetIdentifier == identifier {
            do {
                enqueue(
                    .connection(
                        try CoreBluetoothCaptureMapping.connection(
                            peripheralIdentifier: identifier,
                            state: .failedToConnect,
                            error: error
                        )
                    )
                )
            } catch {
                failCapture(error)
                return
            }
            lastDiagnostic = Self.diagnostic(error, fallback: "Failed to connect to peripheral.")
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
        handleDisconnect(
            peripheral,
            platformEventTimestamp: nil,
            isReconnecting: nil,
            error: error
        )
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        handleDisconnect(
            peripheral,
            platformEventTimestamp: TimeInterval(timestamp),
            isReconnecting: isReconnecting,
            error: error
        )
    }
}

extension ForegroundCoreBluetoothCaptureController: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
        if let error {
            failCapture(error, fallback: "Service discovery failed; capture is incomplete.")
            return
        }

        for service in peripheral.services ?? [] {
            do {
                enqueue(.service(try CoreBluetoothCaptureMapping.service(
                    peripheralIdentifier: peripheral.identifier,
                    service: service
                )))
            } catch {
                failCapture(error)
                return
            }
            discoverTopology(for: service, on: peripheral)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverIncludedServicesFor service: CBService,
        error: Error?
    ) {
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
        if let error {
            failCapture(error, fallback: "Included-service discovery failed; capture is incomplete.")
            return
        }

        for included in service.includedServices ?? [] {
            do {
                enqueue(.includedService(try CoreBluetoothCaptureMapping.includedService(
                    peripheralIdentifier: peripheral.identifier,
                    parentService: service,
                    includedService: included
                )))
            } catch {
                failCapture(error)
                return
            }
            discoverTopology(for: included, on: peripheral)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
        if let error {
            failCapture(error, fallback: "Characteristic discovery failed; capture is incomplete.")
            return
        }

        for characteristic in service.characteristics ?? [] {
            do {
                enqueue(.characteristic(try CoreBluetoothCaptureMapping.characteristic(
                    peripheralIdentifier: peripheral.identifier,
                    characteristic: characteristic
                )))
                try acquirePassively(characteristic, on: peripheral)
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
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
        if let error {
            failCapture(error, fallback: "Descriptor discovery failed; capture is incomplete.")
            return
        }

        for descriptor in characteristic.descriptors ?? [] {
            do {
                enqueue(.descriptor(try CoreBluetoothCaptureMapping.descriptor(
                    peripheralIdentifier: peripheral.identifier,
                    descriptor: descriptor
                )))
            } catch {
                failCapture(error)
                return
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }

        let key: PassiveCoreBluetoothTargetState.AttributeKey
        do {
            key = try attributeKey(for: characteristic, on: peripheral)
        } catch {
            failCapture(error)
            return
        }
        let wasTrackedRead = targetState.consumeReadRequest(key)

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
        if wasTrackedRead {
            origin = .readResponse
        } else if characteristic.isNotifying {
            origin = .subscriptionUpdate
        } else {
            // CoreBluetooth does not label this callback strongly enough to call
            // it a read. Without a tracked request or notifying state, exporting
            // `.readResponse` would fabricate provenance.
            failCapture(
                AcquisitionError.unattributedCharacteristicValue,
                fallback: "Unattributed characteristic value callback; capture is incomplete."
            )
            return
        }

        do {
            enqueue(.value(try CoreBluetoothCaptureMapping.value(
                peripheralIdentifier: peripheral.identifier,
                characteristic: characteristic,
                origin: origin,
                payload: payload
            )))
            if wasTrackedRead {
                try subscribeAfterInitialReadIfNeeded(characteristic, on: peripheral)
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
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }

        let key: PassiveCoreBluetoothTargetState.AttributeKey
        do {
            key = try attributeKey(for: characteristic, on: peripheral)
        } catch {
            failCapture(error)
            return
        }
        let requestedEnabled = targetState.consumeSubscriptionRequest(key)

        do {
            enqueue(
                .subscription(
                    try CoreBluetoothCaptureMapping.subscription(
                        peripheralIdentifier: peripheral.identifier,
                        characteristic: characteristic,
                        requestedEnabled: requestedEnabled,
                        error: error
                    )
                )
            )
        } catch {
            failCapture(error)
            return
        }

        if let error {
            // Preserve the structured subscription callback first, then fail the
            // target artifact closed because subsequent missing value evidence
            // must not be misread as a proven absence.
            failCapture(error, fallback: "Notification subscription failed; capture is incomplete.")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }

        let uuids = invalidatedServices
            .map { CoreBluetoothCaptureMapping.normalizedUUID($0.uuid) }
            .joined(separator: ",")
        enqueueInterruption(
            uuids.isEmpty
                ? "GATT services invalidated"
                : "GATT services invalidated: \(uuids)"
        )

        clearAcquisitionObjects()
        peripheral.discoverServices(nil)
    }
}
