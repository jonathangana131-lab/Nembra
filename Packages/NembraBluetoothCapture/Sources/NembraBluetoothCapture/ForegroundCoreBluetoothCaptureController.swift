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
/// This is intentionally not wired into production scooter control/reconnect.
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
        case captureFailed
    }

    public private(set) var bluetoothState: CBManagerState = .unknown
    public private(set) var isScanning = false
    public private(set) var connectionPhase: ConnectionPhase = .idle
    public private(set) var discoveredPeripherals: [DiscoveredPeripheral] = []
    public private(set) var lastDiagnostic: String?
    public private(set) var captureFailed = false

    private let recorder: PassiveCoreBluetoothCaptureRecorder
    private var centralManager: CBCentralManager!
    private var peripheralByIdentifier: [UUID: CBPeripheral] = [:]
    private var latestDiscoveryByIdentifier: [UUID: DiscoveredPeripheral] = [:]
    private var activePeripheral: CBPeripheral?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var pendingInitialReadCharacteristicIDs: Set<ObjectIdentifier> = []
    private var discoveredIncludedServiceObjectIDs: Set<ObjectIdentifier> = []
    private var discoveredCharacteristicServiceObjectIDs: Set<ObjectIdentifier> = []
    private var hasObservedInitialCentralState = false

    private struct PendingEvent {
        let event: PassiveBluetoothCaptureEvent
        let uptimeNanoseconds: UInt64
        let date: Date
    }

    /// Callback events are synchronously inserted into this MainActor-owned
    /// queue. One drain task forwards them to the recorder actor serially, so
    /// unstructured task scheduling can never reorder CoreBluetooth callbacks.
    private var pendingEvents: [PendingEvent] = []
    private var eventDrainTask: Task<Void, Never>?

    public init(
        vehicleIdentity: VehicleIdentity,
        sessionID: UUID = UUID(),
        startedAt: Date = Date(),
        centralManagerOptions: [String: Any]? = nil
    ) throws {
        recorder = try PassiveCoreBluetoothCaptureRecorder(
            id: sessionID,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )
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

    /// Requests a connection to a peripheral the current research scan has
    /// actually observed. CoreBluetooth connection requests do not time out on
    /// their own, so this controller owns a finite cancellation deadline.
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

        stopScanning()
        connectionPhase = .connecting(peripheralIdentifier)
        activePeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        scheduleConnectionTimeout(for: peripheral, nanoseconds: timeoutNanoseconds)
    }

    public func cancelActiveConnection() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        if let activePeripheral {
            centralManager.cancelPeripheralConnection(activePeripheral)
        }
    }

    /// Adds a human-observed stock-app value to the same monotonic evidence
    /// timeline. This does not assert any DP/byte meaning.
    public func recordStockAppObservation(
        field: String,
        displayedValue: String,
        note: String? = nil
    ) throws {
        try ensureCaptureHealthy()
        let observation = try PassiveBluetoothStockAppObservation(
            field: field,
            displayedValue: displayedValue,
            note: note
        )
        enqueue(.stockAppState(observation))
    }

    public func captureSnapshot() async throws -> PassiveBluetoothCaptureSession {
        try ensureCaptureHealthy()
        await flushPendingEvents()
        try ensureCaptureHealthy()
        return await recorder.snapshot()
    }

    public func encodedCaptureJSON(prettyPrinted: Bool = true) async throws -> Data {
        try ensureCaptureHealthy()
        await flushPendingEvents()
        try ensureCaptureHealthy()
        return try await recorder.encodedJSON(prettyPrinted: prettyPrinted)
    }

    private func scheduleConnectionTimeout(for peripheral: CBPeripheral, nanoseconds: UInt64) {
        connectionTimeoutTask?.cancel()
        let identifier = peripheral.identifier
        connectionTimeoutTask = Task { @MainActor [weak self, weak peripheral] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled,
                  let self,
                  let peripheral,
                  self.connectionPhase == .connecting(identifier) else { return }

            self.lastDiagnostic = "Connection attempt timed out and was cancelled."
            self.enqueueInterruption("connection attempt timed out")
            self.centralManager.cancelPeripheralConnection(peripheral)
            self.connectionPhase = .idle
            self.activePeripheral = nil
            self.connectionTimeoutTask = nil
        }
    }

    private func beginDiscovery(on peripheral: CBPeripheral) {
        pendingInitialReadCharacteristicIDs.removeAll()
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

    private func acquirePassively(
        _ characteristic: CBCharacteristic,
        on peripheral: CBPeripheral
    ) {
        let plan = PassiveCoreBluetoothAcquisitionPolicy.plan(for: characteristic)
        if plan.shouldDiscoverDescriptors {
            peripheral.discoverDescriptors(for: characteristic)
        }

        let characteristicID = ObjectIdentifier(characteristic)
        if plan.shouldReadValue {
            // Read first, then subscribe after its callback. This avoids falsely
            // classifying a requested read response as an unsolicited subscribed
            // update on characteristics that support both mechanisms.
            pendingInitialReadCharacteristicIDs.insert(characteristicID)
            peripheral.readValue(for: characteristic)
        } else if plan.shouldSubscribeForValueUpdates {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    private func subscribeAfterInitialReadIfNeeded(
        _ characteristic: CBCharacteristic,
        on peripheral: CBPeripheral
    ) {
        let plan = PassiveCoreBluetoothAcquisitionPolicy.plan(for: characteristic)
        if plan.shouldSubscribeForValueUpdates {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    private func enqueue(_ event: PassiveBluetoothCaptureEvent) {
        guard !captureFailed else { return }
        pendingEvents.append(
            PendingEvent(
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
        guard eventDrainTask == nil, !pendingEvents.isEmpty, !captureFailed else { return }
        eventDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !self.pendingEvents.isEmpty, !self.captureFailed {
                let next = self.pendingEvents.removeFirst()
                do {
                    try await self.recorder.record(
                        next.event,
                        receivedAtUptimeNanoseconds: next.uptimeNanoseconds,
                        receivedAtDate: next.date
                    )
                } catch {
                    self.failCapture(error)
                }
            }
            self.eventDrainTask = nil
            if !self.pendingEvents.isEmpty, !self.captureFailed {
                self.startDrainIfNeeded()
            }
        }
    }

    private func flushPendingEvents() async {
        while let drain = eventDrainTask {
            await drain.value
        }
        if !pendingEvents.isEmpty, !captureFailed {
            startDrainIfNeeded()
            await flushPendingEvents()
        }
    }

    private func failCapture(_ error: Error) {
        guard !captureFailed else { return }
        captureFailed = true
        lastDiagnostic = "Capture stopped after evidence-recording failure: \(String(describing: error))"
        centralManager.stopScan()
        isScanning = false
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        if let activePeripheral {
            centralManager.cancelPeripheralConnection(activePeripheral)
        }
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

    private func clearActiveConnectionState() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        activePeripheral?.delegate = nil
        activePeripheral = nil
        pendingInitialReadCharacteristicIDs.removeAll()
        discoveredIncludedServiceObjectIDs.removeAll()
        discoveredCharacteristicServiceObjectIDs.removeAll()
        connectionPhase = .idle
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
                // CoreBluetooth invalidates connection/GATT state when central
                // availability drops; never preserve stale discovered objects as
                // continuous evidence across this boundary.
                clearActiveConnectionState()
            }
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
        let connectable = (advertisementData[CBAdvertisementDataIsConnectableKey] as? NSNumber)?.boolValue
        let discovery = DiscoveredPeripheral(
            id: peripheral.identifier,
            localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name,
            rssi: RSSI.intValue,
            isConnectable: connectable
        )
        latestDiscoveryByIdentifier[peripheral.identifier] = discovery
        updateDiscoveryList()

        do {
            enqueue(
                .advertisement(
                    try CoreBluetoothCaptureMapping.advertisement(
                        peripheralIdentifier: peripheral.identifier,
                        advertisementData: advertisementData,
                        rssi: RSSI
                    )
                )
            )
        } catch {
            failCapture(error)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        activePeripheral = peripheral
        peripheral.delegate = self
        connectionPhase = .connected(peripheral.identifier)
        beginDiscovery(on: peripheral)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        lastDiagnostic = Self.diagnostic(error, fallback: "Failed to connect to peripheral.")
        enqueueInterruption("connection attempt failed")
        clearActiveConnectionState()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        lastDiagnostic = Self.diagnostic(error, fallback: "Peripheral disconnected.")
        enqueueInterruption("peripheral disconnected")
        clearActiveConnectionState()
    }
}

extension ForegroundCoreBluetoothCaptureController: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lastDiagnostic = Self.diagnostic(error, fallback: "Service discovery failed.")
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
        if let error {
            lastDiagnostic = Self.diagnostic(error, fallback: "Included-service discovery failed.")
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
        if let error {
            lastDiagnostic = Self.diagnostic(error, fallback: "Characteristic discovery failed.")
            return
        }

        for characteristic in service.characteristics ?? [] {
            do {
                enqueue(.characteristic(try CoreBluetoothCaptureMapping.characteristic(
                    peripheralIdentifier: peripheral.identifier,
                    characteristic: characteristic
                )))
            } catch {
                failCapture(error)
                return
            }
            acquirePassively(characteristic, on: peripheral)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverDescriptorsFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            lastDiagnostic = Self.diagnostic(error, fallback: "Descriptor discovery failed.")
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
        let characteristicID = ObjectIdentifier(characteristic)
        let wasInitialRead = pendingInitialReadCharacteristicIDs.remove(characteristicID) != nil

        if let error {
            lastDiagnostic = Self.diagnostic(error, fallback: "Characteristic value update failed.")
            if wasInitialRead {
                subscribeAfterInitialReadIfNeeded(characteristic, on: peripheral)
            }
            return
        }
        guard let payload = characteristic.value else {
            if wasInitialRead {
                subscribeAfterInitialReadIfNeeded(characteristic, on: peripheral)
            }
            return
        }

        let origin: PassiveBluetoothValueOrigin = wasInitialRead
            ? .readResponse
            : (characteristic.isNotifying ? .subscriptionUpdate : .readResponse)

        do {
            enqueue(.value(try CoreBluetoothCaptureMapping.value(
                peripheralIdentifier: peripheral.identifier,
                characteristic: characteristic,
                origin: origin,
                payload: payload
            )))
        } catch {
            failCapture(error)
            return
        }

        if wasInitialRead {
            subscribeAfterInitialReadIfNeeded(characteristic, on: peripheral)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            lastDiagnostic = Self.diagnostic(error, fallback: "Notification subscription failed.")
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        let uuids = invalidatedServices
            .map { CoreBluetoothCaptureMapping.normalizedUUID($0.uuid) }
            .joined(separator: ",")
        enqueueInterruption(
            uuids.isEmpty
                ? "GATT services invalidated"
                : "GATT services invalidated: \(uuids)"
        )

        pendingInitialReadCharacteristicIDs.removeAll()
        discoveredIncludedServiceObjectIDs.removeAll()
        discoveredCharacteristicServiceObjectIDs.removeAll()
        peripheral.discoverServices(nil)
    }
}
