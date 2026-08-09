@preconcurrency import CoreBluetooth
import Combine
import CoreTransferable
import Dispatch
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ES80OneTimeBluetoothDumper: NSObject, ObservableObject {
    struct Candidate: Identifiable, Equatable {
        let id: UUID
        var name: String?
        var rssi: Int?
        var connectable: Bool?
        var lastSeen: Date

        var displayName: String { name?.isEmpty == false ? name! : "Unnamed peripheral" }
        var rssiText: String { rssi.map { "\($0) dBm" } ?? "RSSI unavailable" }
    }

    struct ErrorRecord: Codable, Equatable {
        let domain: String
        let code: Int
        let description: String
    }

    struct Event: Codable, Identifiable {
        let id: Int
        let wallClock: Date
        let monotonicNanoseconds: UInt64
        let kind: String
        let peripheralID: String?
        let serviceUUID: String?
        let characteristicUUID: String?
        let descriptorUUID: String?
        let origin: String?
        let valueBase64: String?
        let valueHex: String?
        let rssi: Int?
        let details: [String: String]
        let error: ErrorRecord?
    }

    struct ExportEnvelope: Codable {
        let schemaVersion: Int
        let purpose: String
        let captureID: String
        let createdAt: Date
        let finishedAt: Date
        let selectedPeripheralID: String?
        let selectedPeripheralName: String?
        let eventCount: Int
        let buildIdentifier: String?
        let buildSourceCommit: String?
        let limitations: [String]
        let events: [Event]
    }

    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedPeripheralID: UUID?
    @Published private(set) var selectedPeripheralName: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var eventCount = 0
    @Published private(set) var connectedAt: Date?
    @Published private(set) var lastMessage = "Turn the scooter on when you are ready, then start scanning."
    @Published private(set) var exportData: Data?
    @Published private(set) var exportFilename = "Nembra-ES80-Bluetooth-Dump.json"

    private var central: CBCentralManager!
    private var peripheralByID: [UUID: CBPeripheral] = [:]
    private var candidateByID: [UUID: Candidate] = [:]
    private var activePeripheral: CBPeripheral?
    private var events: [Event] = []
    private var nextEventID = 1
    private let captureID = UUID()
    private let createdAt = Date()
    private var pendingReads = Set<ObjectIdentifier>()
    private var subscribeAfterRead = Set<ObjectIdentifier>()
    private var rssiTask: Task<Void, Never>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        bluetoothState = central.state
    }

    deinit {
        rssiTask?.cancel()
    }

    func startScanning() {
        exportData = nil
        guard central.state == .poweredOn else {
            lastMessage = "Bluetooth is not powered on yet."
            return
        }
        guard !isConnected, !isConnecting else { return }

        if !isScanning {
            candidateByID.removeAll(keepingCapacity: true)
            candidates.removeAll(keepingCapacity: true)
            peripheralByID.removeAll(keepingCapacity: true)
            record(kind: "scan_started", details: [
                "allowDuplicates": "true",
                "serviceFilter": "none"
            ])
        }

        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        lastMessage = "Scanning broadly. If possible, power the ES80 on now and tap the device that appears."
    }

    func stopScanning() {
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
        record(kind: "scan_stopped")
        lastMessage = "Scan stopped."
    }

    func connect(to candidate: Candidate) {
        guard central.state == .poweredOn,
              !isConnecting,
              !isConnected,
              candidate.connectable != false,
              let peripheral = peripheralByID[candidate.id] else { return }

        stopScanning()
        exportData = nil
        selectedPeripheralID = candidate.id
        selectedPeripheralName = candidate.name
        activePeripheral = peripheral
        peripheral.delegate = self
        isConnecting = true
        lastMessage = "Connecting to \(candidate.displayName)…"
        record(
            kind: "connect_requested",
            peripheral: peripheral,
            details: ["displayName": candidate.displayName]
        )
        central.connect(peripheral)
    }

    func stopAndPrepareJSON() {
        if isScanning { stopScanning() }
        record(kind: "operator_stop_requested", peripheral: activePeripheral)
        rssiTask?.cancel()
        rssiTask = nil
        if let activePeripheral, activePeripheral.state != .disconnected {
            central.cancelPeripheralConnection(activePeripheral)
        }
        prepareJSON()
        lastMessage = "Capture frozen. Share the JSON back into this chat so we can decode the ES80 Bluetooth layout."
    }

    func prepareJSON() {
        let envelope = ExportEnvelope(
            schemaVersion: 1,
            purpose: "One-time passive ES80 CoreBluetooth dump for Nembra protocol research",
            captureID: captureID.uuidString,
            createdAt: createdAt,
            finishedAt: Date(),
            selectedPeripheralID: selectedPeripheralID?.uuidString,
            selectedPeripheralName: selectedPeripheralName,
            eventCount: events.count,
            buildIdentifier: normalizedBundleString("NembraCaptureBuildIdentifier"),
            buildSourceCommit: normalizedBundleString("NembraCaptureBuildCommitSHA"),
            limitations: [
                "This is a CoreBluetooth application-level capture, not an over-the-air BLE packet sniffer.",
                "It records advertisements exposed by iOS, discovered GATT topology, readable characteristic values, notify/indicate callbacks, descriptor values that CoreBluetooth allows to be read, RSSI, lifecycle events, and errors.",
                "No application characteristic-value write is issued by this utility.",
                "Observed bytes are raw evidence and are not automatically battery, speed, power, throttle, brake, or command semantics."
            ],
            events: events
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            exportData = try encoder.encode(envelope)
            exportFilename = "Nembra-ES80-Bluetooth-Dump-\(captureID.uuidString.prefix(8)).json"
        } catch {
            lastMessage = "JSON encoding failed: \(error.localizedDescription)"
        }
    }

    func reset() {
        if isScanning { central.stopScan() }
        isScanning = false
        rssiTask?.cancel()
        rssiTask = nil
        if let activePeripheral, activePeripheral.state != .disconnected {
            central.cancelPeripheralConnection(activePeripheral)
        }
        activePeripheral = nil
        isConnecting = false
        isConnected = false
        connectedAt = nil
        selectedPeripheralID = nil
        selectedPeripheralName = nil
        peripheralByID.removeAll()
        candidateByID.removeAll()
        candidates.removeAll()
        pendingReads.removeAll()
        subscribeAfterRead.removeAll()
        events.removeAll(keepingCapacity: true)
        nextEventID = 1
        eventCount = 0
        exportData = nil
        lastMessage = "Reset complete. Start a fresh scan when the scooter is ready."
    }

    private func startRSSIPolling() {
        rssiTask?.cancel()
        rssiTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isConnected, let peripheral = self.activePeripheral else { return }
                peripheral.readRSSI()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func normalizedBundleString(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }

    private func record(
        kind: String,
        peripheral: CBPeripheral? = nil,
        service: CBService? = nil,
        characteristic: CBCharacteristic? = nil,
        descriptor: CBDescriptor? = nil,
        origin: String? = nil,
        value: Data? = nil,
        rssi: Int? = nil,
        details: [String: String] = [:],
        error: Error? = nil
    ) {
        let event = Event(
            id: nextEventID,
            wallClock: Date(),
            monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            kind: kind,
            peripheralID: peripheral?.identifier.uuidString,
            serviceUUID: service?.uuid.uuidString.uppercased() ?? characteristic?.service?.uuid.uuidString.uppercased() ?? descriptor?.characteristic?.service?.uuid.uuidString.uppercased(),
            characteristicUUID: characteristic?.uuid.uuidString.uppercased() ?? descriptor?.characteristic?.uuid.uuidString.uppercased(),
            descriptorUUID: descriptor?.uuid.uuidString.uppercased(),
            origin: origin,
            valueBase64: value?.base64EncodedString(),
            valueHex: value.map(Self.hex),
            rssi: rssi,
            details: details,
            error: error.map(Self.errorRecord)
        )
        events.append(event)
        nextEventID += 1
        eventCount = events.count
    }

    private static func errorRecord(_ error: Error) -> ErrorRecord {
        let ns = error as NSError
        return ErrorRecord(domain: ns.domain, code: ns.code, description: ns.localizedDescription)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    private static func characteristicProperties(_ properties: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if properties.contains(.broadcast) { names.append("broadcast") }
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        if properties.contains(.authenticatedSignedWrites) { names.append("authenticatedSignedWrites") }
        if properties.contains(.extendedProperties) { names.append("extendedProperties") }
        if properties.contains(.notifyEncryptionRequired) { names.append("notifyEncryptionRequired") }
        if properties.contains(.indicateEncryptionRequired) { names.append("indicateEncryptionRequired") }
        return names.joined(separator: ",")
    }

    private static func describeDescriptorValue(_ value: Any?) -> [String: String] {
        guard let value else { return ["valueType": "nil"] }
        if let data = value as? Data {
            return [
                "valueType": "Data",
                "valueBase64": data.base64EncodedString(),
                "valueHex": hex(data)
            ]
        }
        if let string = value as? String {
            return ["valueType": "String", "value": string]
        }
        if let number = value as? NSNumber {
            return ["valueType": "NSNumber", "value": number.stringValue]
        }
        return ["valueType": String(describing: type(of: value)), "value": String(describing: value)]
    }

    private static func advertisementDetails(_ advertisementData: [String: Any], rssi: NSNumber) -> [String: String] {
        var details: [String: String] = [:]
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String { details["localName"] = name }
        if let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber { details["isConnectable"] = connectable.boolValue ? "true" : "false" }
        if let tx = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber { details["txPower"] = tx.stringValue }
        if let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            details["manufacturerDataBase64"] = manufacturer.base64EncodedString()
            details["manufacturerDataHex"] = hex(manufacturer)
        }
        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            details["serviceUUIDs"] = uuids.map { $0.uuidString.uppercased() }.joined(separator: ",")
        }
        if let uuids = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] {
            details["overflowServiceUUIDs"] = uuids.map { $0.uuidString.uppercased() }.joined(separator: ",")
        }
        if let uuids = advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] {
            details["solicitedServiceUUIDs"] = uuids.map { $0.uuidString.uppercased() }.joined(separator: ",")
        }
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (uuid, data) in serviceData {
                let key = uuid.uuidString.uppercased()
                details["serviceData.\(key).base64"] = data.base64EncodedString()
                details["serviceData.\(key).hex"] = hex(data)
            }
        }
        details["rssiRaw"] = rssi.stringValue
        details["advertisementKeys"] = advertisementData.keys.sorted().joined(separator: ",")
        for key in advertisementData.keys.sorted() where details["raw.\(key)"] == nil {
            let value = advertisementData[key]
            if let data = value as? Data {
                details["raw.\(key).base64"] = data.base64EncodedString()
                details["raw.\(key).hex"] = hex(data)
            } else {
                details["raw.\(key)"] = String(describing: value ?? "nil")
            }
        }
        return details
    }

    private static func centralStateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "future"
        }
    }
}

extension ES80OneTimeBluetoothDumper: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        record(kind: "central_state", details: ["state": Self.centralStateName(central.state)])
        if central.state != .poweredOn, isScanning {
            isScanning = false
            lastMessage = "Bluetooth became unavailable."
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let normalizedRSSI = RSSI.intValue == 127 ? nil : RSSI.intValue
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
        peripheralByID[peripheral.identifier] = peripheral
        candidateByID[peripheral.identifier] = Candidate(
            id: peripheral.identifier,
            name: localName,
            rssi: normalizedRSSI,
            connectable: connectable,
            lastSeen: Date()
        )
        candidates = candidateByID.values.sorted {
            switch ($0.rssi, $1.rssi) {
            case let (.some(left), .some(right)) where left != right: return left > right
            case (.some, .none): return true
            case (.none, .some): return false
            default: return $0.id.uuidString < $1.id.uuidString
            }
        }
        record(
            kind: "advertisement",
            peripheral: peripheral,
            rssi: normalizedRSSI,
            details: Self.advertisementDetails(advertisementData, rssi: RSSI)
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnecting = false
        isConnected = true
        connectedAt = Date()
        activePeripheral = peripheral
        peripheral.delegate = self
        selectedPeripheralName = peripheral.name ?? selectedPeripheralName
        record(kind: "connected", peripheral: peripheral, details: ["peripheralName": peripheral.name ?? ""])
        lastMessage = "Connected. Dumping all discoverable/readable/notifying GATT data. Leave it running for about 60–90 seconds."
        peripheral.discoverServices(nil)
        peripheral.readRSSI()
        startRSSIPolling()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnecting = false
        isConnected = false
        record(kind: "connect_failed", peripheral: peripheral, error: error)
        lastMessage = "Connection failed. You can scan and try the candidate again."
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        rssiTask?.cancel()
        rssiTask = nil
        isConnecting = false
        isConnected = false
        record(kind: "disconnected", peripheral: peripheral, error: error)
        if exportData == nil {
            lastMessage = "Disconnected. You can still prepare/share the data already captured."
        }
    }
}

extension ES80OneTimeBluetoothDumper: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        record(kind: "services_discovered", peripheral: peripheral, error: error)
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            record(
                kind: "service",
                peripheral: peripheral,
                service: service,
                details: ["isPrimary": service.isPrimary ? "true" : "false"]
            )
            peripheral.discoverIncludedServices(nil, for: service)
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        record(kind: "included_services_discovered", peripheral: peripheral, service: service, error: error)
        guard error == nil else { return }
        for included in service.includedServices ?? [] {
            record(
                kind: "included_service",
                peripheral: peripheral,
                service: service,
                details: [
                    "includedServiceUUID": included.uuid.uuidString.uppercased(),
                    "includedServiceIsPrimary": included.isPrimary ? "true" : "false"
                ]
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        record(kind: "characteristics_discovered", peripheral: peripheral, service: service, error: error)
        guard error == nil else { return }

        for characteristic in service.characteristics ?? [] {
            let properties = Self.characteristicProperties(characteristic.properties)
            record(
                kind: "characteristic",
                peripheral: peripheral,
                characteristic: characteristic,
                details: [
                    "properties": properties,
                    "isNotifyingAtDiscovery": characteristic.isNotifying ? "true" : "false"
                ]
            )

            peripheral.discoverDescriptors(for: characteristic)

            let key = ObjectIdentifier(characteristic)
            let canRead = characteristic.properties.contains(.read)
            let canNotify = characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)

            if canRead {
                pendingReads.insert(key)
                if canNotify { subscribeAfterRead.insert(key) }
                record(kind: "characteristic_read_requested", peripheral: peripheral, characteristic: characteristic)
                peripheral.readValue(for: characteristic)
            } else if canNotify {
                record(kind: "subscription_requested", peripheral: peripheral, characteristic: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        record(kind: "descriptors_discovered", peripheral: peripheral, characteristic: characteristic, error: error)
        guard error == nil else { return }
        for descriptor in characteristic.descriptors ?? [] {
            record(kind: "descriptor", peripheral: peripheral, descriptor: descriptor)
            record(kind: "descriptor_read_requested", peripheral: peripheral, descriptor: descriptor)
            peripheral.readValue(for: descriptor)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let key = ObjectIdentifier(characteristic)
        let wasPendingRead = pendingReads.remove(key) != nil
        let shouldSubscribeNow = wasPendingRead && subscribeAfterRead.remove(key) != nil
        let origin = wasPendingRead ? "read" : (characteristic.isNotifying ? "notify_or_indicate" : "unsolicited_callback")

        if let error {
            record(
                kind: "characteristic_value_error",
                peripheral: peripheral,
                characteristic: characteristic,
                origin: origin,
                error: error
            )
        } else {
            record(
                kind: "characteristic_value",
                peripheral: peripheral,
                characteristic: characteristic,
                origin: origin,
                value: characteristic.value,
                details: ["byteCount": String(characteristic.value?.count ?? 0)]
            )
        }

        if shouldSubscribeNow {
            record(kind: "subscription_requested_after_read", peripheral: peripheral, characteristic: characteristic)
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        record(
            kind: "subscription_state",
            peripheral: peripheral,
            characteristic: characteristic,
            details: ["isNotifying": characteristic.isNotifying ? "true" : "false"],
            error: error
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        var details = Self.describeDescriptorValue(descriptor.value)
        details["descriptorUUID"] = descriptor.uuid.uuidString.uppercased()
        record(
            kind: error == nil ? "descriptor_value" : "descriptor_value_error",
            peripheral: peripheral,
            descriptor: descriptor,
            details: details,
            error: error
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let normalized = RSSI.intValue == 127 ? nil : RSSI.intValue
        record(kind: "rssi", peripheral: peripheral, rssi: normalized, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        for service in invalidatedServices {
            record(kind: "service_invalidated", peripheral: peripheral, service: service)
        }
        record(kind: "services_rediscovery_requested", peripheral: peripheral)
        peripheral.discoverServices(nil)
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        selectedPeripheralName = peripheral.name ?? selectedPeripheralName
        record(kind: "peripheral_name_updated", peripheral: peripheral, details: ["name": peripheral.name ?? ""])
    }
}

private struct ES80OneTimeDumpTransfer: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { transfer in
            transfer.data
        }
        .suggestedFileName { transfer in transfer.filename }
    }
}

@MainActor
struct ES80OneTimeBluetoothDumpView: View {
    @StateObject private var dumper = ES80OneTimeBluetoothDumper()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    instructions
                    statusPanel
                    controls
                    candidateList
                    capturePanel
                    if let data = dumper.exportData {
                        sharePanel(data: data)
                    }
                }
                .frame(maxWidth: 720)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Nembra Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ONE-TIME ES80 BLE DUMP")
                .font(.caption.monospaced().weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("Get the Bluetooth facts, then delete this utility.")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
            Text("This build is intentionally simple. It records the raw CoreBluetooth evidence Nembra needs before anyone guesses what battery, speed, power, range, controls, or Tuya-style values mean.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Passive only", systemImage: "shield.checkered")
                .font(.headline)
            Text("Keep the scooter stationary and unplugged from its charger. Close the stock scooter app. Tap Start Scan, power the scooter on, then connect to the device that appears. Leave the capture connected for about 60–90 seconds before Stop & Prepare JSON.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("No application characteristic writes are sent. Notification subscription is used only where the characteristic advertises notify/indicate support.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Bluetooth", value: bluetoothStateText)
            LabeledContent("Scan", value: dumper.isScanning ? "Running" : "Stopped")
            LabeledContent("Connection", value: connectionText)
            LabeledContent("Events captured", value: "\(dumper.eventCount)")
            if let connectedAt = dumper.connectedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LabeledContent("Connected time", value: elapsedText(from: connectedAt, to: context.date))
                }
            }
            Text(dumper.lastMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(dumper.isScanning ? "Stop Scan" : "Start Scan") {
                dumper.isScanning ? dumper.stopScanning() : dumper.startScanning()
            }
            .buttonStyle(.borderedProminent)
            .disabled(dumper.isConnecting || dumper.isConnected || dumper.bluetoothState != .poweredOn)

            Button("Reset", role: .destructive) {
                dumper.reset()
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var candidateList: some View {
        if !dumper.isConnected && !dumper.isConnecting {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Nearby Bluetooth devices")
                        .font(.headline)
                    Spacer()
                    Text("\(dumper.candidates.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if dumper.candidates.isEmpty {
                    Text(dumper.isScanning ? "Scanning… power the scooter on now." : "Start a scan to see nearby peripherals.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(dumper.candidates) { candidate in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.displayName)
                                        .font(.headline)
                                    Text(candidate.id.uuidString)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer(minLength: 12)
                                Text(candidate.rssiText)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Button(candidate.connectable == false ? "Not connectable" : "Connect & dump everything") {
                                dumper.connect(to: candidate)
                            }
                            .buttonStyle(.bordered)
                            .disabled(candidate.connectable == false)
                        }
                        .padding(12)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var capturePanel: some View {
        if dumper.selectedPeripheralID != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Capture")
                    .font(.headline)
                if let name = dumper.selectedPeripheralName {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                }
                if let id = dumper.selectedPeripheralID {
                    Text(id.uuidString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text("The app is collecting advertisements already seen, complete GATT topology, characteristic properties, readable values, notify/indicate streams, readable descriptor values, RSSI and all callback errors/timestamps it can observe through CoreBluetooth.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Stop & Prepare JSON") {
                    dumper.stopAndPrepareJSON()
                }
                .buttonStyle(.borderedProminent)
                .disabled(dumper.eventCount == 0 || dumper.exportData != nil)
            }
            .padding(16)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func sharePanel(data: Data) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("JSON READY", systemImage: "checkmark.circle.fill")
                .font(.headline)
            Text("Share this exact file back into ChatGPT. That is the raw evidence we can use to identify the ES80 service/characteristic layout and start mapping real values instead of guessing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ShareLink(
                item: ES80OneTimeDumpTransfer(data: data, filename: dumper.exportFilename),
                preview: SharePreview(dumper.exportFilename)
            ) {
                Label("Share Bluetooth JSON", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var bluetoothStateText: String {
        switch dumper.bluetoothState {
        case .unknown: return "Unknown"
        case .resetting: return "Resetting"
        case .unsupported: return "Unsupported"
        case .unauthorized: return "Permission needed"
        case .poweredOff: return "Off"
        case .poweredOn: return "On"
        @unknown default: return "Future state"
        }
    }

    private var connectionText: String {
        if dumper.isConnected { return "Connected" }
        if dumper.isConnecting { return "Connecting" }
        if dumper.selectedPeripheralID != nil { return "Disconnected" }
        return "None"
    }

    private func elapsedText(from start: Date, to end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
