@preconcurrency import CoreBluetooth
import Combine
import Foundation
import SwiftUI

// CoreBluetooth exposes this dictionary key as CBAdvertisementDataIsConnectable.
let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable

@main
@MainActor
struct NembraApp: App {
    var body: some Scene {
        WindowGroup {
            TuyaSecureLinkPreflightView()
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
final class TuyaSecureLinkPreflightController: NSObject, ObservableObject {
    struct Candidate: Identifiable, Equatable {
        let id: UUID
        var name: String
        var rssi: Int?
        var score: Int
        var reasons: [String]
        var advertisementCount: Int

        var rssiText: String { rssi.map { "\($0) dBm" } ?? "RSSI unavailable" }
        var likelyScooter: Bool { score >= 70 }
    }

    struct Event: Codable {
        let at: Date
        let kind: String
        let peripheralID: String?
        let details: [String: String]
    }

    struct ExportEnvelope: Codable {
        let schemaVersion: Int
        let purpose: String
        let createdAt: Date
        let finishedAt: Date
        let selectedPeripheralID: String?
        let selectedPeripheralName: String?
        let tuyaVirtualID: String?
        let tuyaProductID: String?
        let currentTuyaOdometerMiles: String
        let userTrackedLifetimeMiles: String
        let userTrackedOdometerHistory: String
        let serviceFD50Seen: Bool
        let writeCharacteristicSeen: Bool
        let notifyCharacteristicSeen: Bool
        let readCharacteristicSeen: Bool
        let notificationsEnabled: Bool
        let applicationPayloadCount: Int
        let lastConnectionDurationSeconds: Double
        let survivedThirtySecondCutoff: Bool
        let disconnectCount: Int
        let result: String
        let limitations: [String]
        let events: [Event]
    }

    enum Stage: Equatable {
        case ready
        case scanning
        case candidateReady
        case connecting
        case listening
        case authBlocked
        case payloadReceived
        case survivedCutoffNoPayload
        case disconnected
        case readyToShare
    }

    static let fd50 = CBUUID(string: "FD50")
    static let writeUUID = CBUUID(string: "00000001-0000-1001-8001-00805F9B07D0")
    static let notifyUUID = CBUUID(string: "00000002-0000-1001-8001-00805F9B07D0")
    static let readUUID = CBUUID(string: "00000003-0000-1001-8001-00805F9B07D0")
    static let previousPhysicalPeripheralID = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!

    @Published private(set) var stage: Stage = .ready
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedPeripheralID: UUID?
    @Published private(set) var selectedPeripheralName: String?
    @Published private(set) var isConnected = false
    @Published private(set) var serviceFD50Seen = false
    @Published private(set) var writeCharacteristicSeen = false
    @Published private(set) var notifyCharacteristicSeen = false
    @Published private(set) var readCharacteristicSeen = false
    @Published private(set) var notificationsEnabled = false
    @Published private(set) var applicationPayloadCount = 0
    @Published private(set) var disconnectCount = 0
    @Published private(set) var lastConnectionDurationSeconds: Double = 0
    @Published private(set) var survivedThirtySecondCutoff = false
    @Published private(set) var status = "This next test is indoor and short. No riding and no charger are required."
    @Published private(set) var exportURL: URL?

    @Published var tuyaVirtualID = ""
    @Published var tuyaProductID = ""
    @Published var currentTuyaOdometerMiles = "1070.0"
    @Published var userTrackedLifetimeMiles = "2164.8"

    private var central: CBCentralManager!
    private var peripheralByID: [UUID: CBPeripheral] = [:]
    private var candidateByID: [UUID: Candidate] = [:]
    private var activePeripheral: CBPeripheral?
    private var connectedAt: Date?
    private var events: [Event] = []
    private var scanStopTask: Task<Void, Never>?
    private var cutoffTask: Task<Void, Never>?
    private var autoConnectIssued = false
    private let createdAt = Date()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        bluetoothState = central.state
    }

    deinit {
        scanStopTask?.cancel()
        cutoffTask?.cancel()
    }

    var bestCandidate: Candidate? { candidates.max(by: { $0.score < $1.score }) }

    var resultTitle: String {
        switch stage {
        case .authBlocked: return "TUYA AUTH BLOCKER CONFIRMED"
        case .payloadReceived: return "REAL TUYA PAYLOAD RECEIVED"
        case .survivedCutoffNoPayload: return "CONNECTION SURVIVED 30 SECONDS"
        case .readyToShare: return "PREFLIGHT JSON READY"
        default: return "TUYA SECURE-LINK PREFLIGHT"
        }
    }

    var resultCode: String {
        switch stage {
        case .authBlocked: return "bound_tuya_unauthenticated_timeout"
        case .payloadReceived: return "application_payload_observed"
        case .survivedCutoffNoPayload: return "survived_cutoff_without_payload"
        case .disconnected: return "unexpected_disconnect"
        case .readyToShare: return applicationPayloadCount > 0 ? "application_payload_observed" : (survivedThirtySecondCutoff ? "survived_cutoff_without_payload" : "preflight_exported")
        default: return "in_progress"
        }
    }

    func currentConnectionSeconds(now: Date = Date()) -> Double {
        guard let connectedAt else { return lastConnectionDurationSeconds }
        return max(0, now.timeIntervalSince(connectedAt))
    }

    func startScan() {
        guard bluetoothState == .poweredOn else {
            status = "Turn Bluetooth on first."
            return
        }
        resetRunKeepingReferences()
        stage = .scanning
        status = "Scanning only for Tuya FD50 devices. If the same scooter UUID appears, Nembra will connect automatically."
        record("scan_started")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scanStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, !Task.isCancelled, self.stage == .scanning else { return }
            self.central.stopScan()
            self.stage = self.candidates.isEmpty ? .ready : .candidateReady
            self.status = self.candidates.isEmpty ? "No Tuya FD50 scooter appeared. Keep the scooter ON and try again." : "I found Tuya candidates. Tap the one marked LIKELY SCOOTER."
            self.record("scan_timeout", details: ["candidateCount": String(self.candidates.count)])
        }
    }

    func connect(_ candidate: Candidate) {
        guard bluetoothState == .poweredOn, let peripheral = peripheralByID[candidate.id] else { return }
        scanStopTask?.cancel()
        central.stopScan()
        selectedPeripheralID = candidate.id
        selectedPeripheralName = candidate.name
        activePeripheral = peripheral
        peripheral.delegate = self
        stage = .connecting
        status = "Connecting to \(candidate.name). This test listens only; it does not send scooter control commands."
        record("connect_requested", peripheral: peripheral, details: ["score": String(candidate.score), "reasons": candidate.reasons.joined(separator: ",")])
        central.connect(peripheral)
    }

    func stopAndExport() {
        cutoffTask?.cancel()
        scanStopTask?.cancel()
        if central.isScanning { central.stopScan() }
        if let activePeripheral, activePeripheral.state != .disconnected {
            lastConnectionDurationSeconds = currentConnectionSeconds()
            central.cancelPeripheralConnection(activePeripheral)
        }
        buildExport()
    }

    func resetAll() {
        if central.isScanning { central.stopScan() }
        if let activePeripheral, activePeripheral.state != .disconnected { central.cancelPeripheralConnection(activePeripheral) }
        tuyaVirtualID = ""
        tuyaProductID = ""
        currentTuyaOdometerMiles = "1070.0"
        userTrackedLifetimeMiles = "2164.8"
        events.removeAll()
        resetRunKeepingReferences()
        status = "Reset. This next test is indoor and short."
    }

    private func resetRunKeepingReferences() {
        scanStopTask?.cancel()
        cutoffTask?.cancel()
        peripheralByID.removeAll()
        candidateByID.removeAll()
        candidates.removeAll()
        activePeripheral = nil
        selectedPeripheralID = nil
        selectedPeripheralName = nil
        connectedAt = nil
        isConnected = false
        serviceFD50Seen = false
        writeCharacteristicSeen = false
        notifyCharacteristicSeen = false
        readCharacteristicSeen = false
        notificationsEnabled = false
        applicationPayloadCount = 0
        disconnectCount = 0
        lastConnectionDurationSeconds = 0
        survivedThirtySecondCutoff = false
        autoConnectIssued = false
        exportURL = nil
        stage = .ready
    }

    private func buildExport() {
        let envelope = ExportEnvelope(
            schemaVersion: 1,
            purpose: "Nembra Tuya FD50 secure-link preflight after physical capture C7D09A22",
            createdAt: createdAt,
            finishedAt: Date(),
            selectedPeripheralID: selectedPeripheralID?.uuidString,
            selectedPeripheralName: selectedPeripheralName,
            tuyaVirtualID: normalized(tuyaVirtualID),
            tuyaProductID: normalized(tuyaProductID),
            currentTuyaOdometerMiles: currentTuyaOdometerMiles,
            userTrackedLifetimeMiles: userTrackedLifetimeMiles,
            userTrackedOdometerHistory: "665.3 + 429.5 + 1070 = 2164.8 miles",
            serviceFD50Seen: serviceFD50Seen,
            writeCharacteristicSeen: writeCharacteristicSeen,
            notifyCharacteristicSeen: notifyCharacteristicSeen,
            readCharacteristicSeen: readCharacteristicSeen,
            notificationsEnabled: notificationsEnabled,
            applicationPayloadCount: applicationPayloadCount,
            lastConnectionDurationSeconds: lastConnectionDurationSeconds,
            survivedThirtySecondCutoff: survivedThirtySecondCutoff,
            disconnectCount: disconnectCount,
            result: resultCode,
            limitations: [
                "This preflight does not contain the Tuya account password and never asks for it.",
                "This build does not issue application-characteristic writes, unbind commands, reset commands, speed-limit commands, lock commands, or other scooter controls.",
                "A Tuya Virtual ID or Product ID entered by the operator is reference metadata, not Bluetooth-derived telemetry.",
                "No speed, battery, power, mode, brake, light, lock, cruise, odometer, or charging DP semantic is accepted until authenticated application payloads are physically observed."
            ],
            events: events
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(envelope)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nembra-Tuya-Preflight-\(UUID().uuidString.prefix(8)).json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            stage = .readyToShare
            status = "Preflight JSON ready. Share this one back into ChatGPT; no outdoor ride is needed yet."
        } catch {
            status = "Could not create JSON: \(error.localizedDescription)"
        }
    }

    private func normalized(_ string: String) -> String? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func scoreCandidate(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) -> (Int, [String]) {
        var score = 0
        var reasons: [String] = []
        if peripheral.identifier == Self.previousPhysicalPeripheralID {
            score += 100
            reasons.append("same iPhone peripheral UUID as capture C7D09A22")
        }
        let localName = ((advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "").lowercased()
        if localName == "demo" {
            score += 50
            reasons.append("local name demo")
        }
        if let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID], services.contains(Self.fd50) {
            score += 35
            reasons.append("FD50 service")
        }
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data], serviceData[Self.fd50] != nil {
            score += 35
            reasons.append("FD50 service data")
        }
        if let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           manufacturer.count >= 2,
           manufacturer[manufacturer.startIndex] == 0xD0,
           manufacturer[manufacturer.index(after: manufacturer.startIndex)] == 0x07 {
            score += 35
            reasons.append("Tuya company ID 0x07D0")
        }
        if rssi.intValue != 127, rssi.intValue > -75 {
            score += 10
            reasons.append("nearby signal")
        }
        return (score, reasons)
    }

    private func record(_ kind: String, peripheral: CBPeripheral? = nil, details: [String: String] = [:]) {
        events.append(Event(at: Date(), kind: kind, peripheralID: peripheral?.identifier.uuidString, details: details))
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined() }
}

extension TuyaSecureLinkPreflightController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        record("central_state", details: ["raw": String(central.state.rawValue)])
        if central.state != .poweredOn, stage != .readyToShare {
            status = "Bluetooth is unavailable. Turn it back on to run the preflight."
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let scored = scoreCandidate(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
        guard scored.0 > 0 else { return }
        peripheralByID[peripheral.identifier] = peripheral
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Tuya peripheral"
        let existing = candidateByID[peripheral.identifier]
        let candidate = Candidate(id: peripheral.identifier, name: localName, rssi: RSSI.intValue == 127 ? existing?.rssi : RSSI.intValue, score: max(existing?.score ?? 0, scored.0), reasons: Array(Set((existing?.reasons ?? []) + scored.1)).sorted(), advertisementCount: (existing?.advertisementCount ?? 0) + 1)
        candidateByID[peripheral.identifier] = candidate
        candidates = candidateByID.values.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return (lhs.rssi ?? -127) > (rhs.rssi ?? -127)
        }
        record("tuya_candidate", peripheral: peripheral, details: ["name": candidate.name, "score": String(candidate.score), "rssi": candidate.rssi.map(String.init) ?? "", "reasons": candidate.reasons.joined(separator: ",")])

        if !autoConnectIssued, peripheral.identifier == Self.previousPhysicalPeripheralID, candidate.advertisementCount >= 2 {
            autoConnectIssued = true
            connect(candidate)
        } else if stage == .scanning, candidate.likelyScooter {
            stage = .candidateReady
            status = "Likely scooter found. I highlighted it so you do not have to guess between unnamed Bluetooth devices."
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectedAt = Date()
        selectedPeripheralName = peripheral.name ?? selectedPeripheralName ?? "Simple Peripheral"
        stage = .listening
        status = "Connected. Listening to Tuya FD50 for 36 seconds. Do not touch the scooter controls yet."
        peripheral.delegate = self
        record("connected", peripheral: peripheral, details: ["name": selectedPeripheralName ?? ""])
        peripheral.discoverServices([Self.fd50])

        cutoffTask?.cancel()
        cutoffTask = Task { @MainActor [weak self, weak peripheral] in
            try? await Task.sleep(nanoseconds: 36_000_000_000)
            guard let self, let peripheral, !Task.isCancelled, self.isConnected, self.activePeripheral?.identifier == peripheral.identifier else { return }
            self.lastConnectionDurationSeconds = self.currentConnectionSeconds()
            self.survivedThirtySecondCutoff = true
            self.record("survived_30_second_cutoff", peripheral: peripheral, details: ["seconds": String(format: "%.3f", self.lastConnectionDurationSeconds), "payloadCount": String(self.applicationPayloadCount)])
            if self.applicationPayloadCount > 0 {
                self.stage = .payloadReceived
                self.status = "Real Tuya application payloads are arriving and the link survived the old cutoff. Stop and share this preflight."
            } else {
                self.stage = .survivedCutoffNoPayload
                self.status = "The link survived the old cutoff but no application payload arrived. Stop and share this result before doing any outdoor test."
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        stage = .disconnected
        status = "Connection failed. Keep the scooter ON and run the preflight again."
        record("connect_failed", peripheral: peripheral, details: ["error": error?.localizedDescription ?? "unknown"])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        cutoffTask?.cancel()
        let duration = connectedAt.map { Date().timeIntervalSince($0) } ?? 0
        lastConnectionDurationSeconds = max(lastConnectionDurationSeconds, duration)
        isConnected = false
        connectedAt = nil
        disconnectCount += 1
        record("disconnected", peripheral: peripheral, details: ["seconds": String(format: "%.3f", duration), "error": error?.localizedDescription ?? "none", "payloadCount": String(applicationPayloadCount)])

        if applicationPayloadCount == 0, duration >= 27, duration <= 33 {
            stage = .authBlocked
            status = "The scooter rejected this unauthenticated Tuya connection at the same ~30-second window. Good — stop here and share the preflight. Do NOT redo the outdoor calibration."
        } else if applicationPayloadCount > 0 {
            stage = .payloadReceived
            status = "Application payloads were observed before disconnect. Stop and share this preflight so I can map the next safe step."
        } else {
            stage = .disconnected
            status = "Bluetooth disconnected outside the expected Tuya timeout window. Stop and share this preflight instead of repeatedly reconnecting."
        }
    }
}

extension TuyaSecureLinkPreflightController: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            record("service_discovery_error", peripheral: peripheral, details: ["error": error.localizedDescription])
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.fd50 }) else {
            status = "Connected device did not expose FD50. This is probably not the scooter. Stop and rescan."
            record("fd50_missing", peripheral: peripheral)
            return
        }
        serviceFD50Seen = true
        record("fd50_service_seen", peripheral: peripheral)
        peripheral.discoverCharacteristics([Self.writeUUID, Self.notifyUUID, Self.readUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            record("characteristic_discovery_error", peripheral: peripheral, details: ["error": error.localizedDescription])
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.writeUUID {
                writeCharacteristicSeen = true
                record("tuya_write_characteristic_seen", peripheral: peripheral, details: ["properties": String(characteristic.properties.rawValue)])
            } else if characteristic.uuid == Self.notifyUUID {
                notifyCharacteristicSeen = true
                record("tuya_notify_characteristic_seen", peripheral: peripheral, details: ["properties": String(characteristic.properties.rawValue)])
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == Self.readUUID {
                readCharacteristicSeen = true
                record("tuya_optional_read_characteristic_seen", peripheral: peripheral, details: ["properties": String(characteristic.properties.rawValue)])
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == Self.notifyUUID {
            notificationsEnabled = characteristic.isNotifying && error == nil
            record("notification_state", peripheral: peripheral, details: ["enabled": notificationsEnabled ? "true" : "false", "error": error?.localizedDescription ?? "none"])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            record("value_error", peripheral: peripheral, details: ["characteristic": characteristic.uuid.uuidString, "error": error.localizedDescription])
            return
        }
        guard let value = characteristic.value, !value.isEmpty else {
            record("empty_value", peripheral: peripheral, details: ["characteristic": characteristic.uuid.uuidString])
            return
        }
        record("characteristic_value", peripheral: peripheral, details: ["characteristic": characteristic.uuid.uuidString, "base64": value.base64EncodedString(), "hex": Self.hex(value)])
        if characteristic.uuid == Self.notifyUUID {
            applicationPayloadCount += 1
            if applicationPayloadCount == 1 {
                stage = .payloadReceived
                status = "FIRST REAL TUYA PAYLOAD RECEIVED. Keep the scooter still for a few seconds, then stop and share this preflight."
            }
        }
    }
}

struct TuyaSecureLinkPreflightView: View {
    @StateObject private var capture = TuyaSecureLinkPreflightController()
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    beforeYouStart
                    referenceCard
                    testCard
                    if !capture.candidates.isEmpty { candidateCard }
                    if capture.selectedPeripheralID != nil { liveCard }
                    if capture.stage == .authBlocked || capture.stage == .payloadReceived || capture.stage == .survivedCutoffNoPayload || capture.stage == .disconnected { resultCard }
                    if let url = capture.exportURL { shareCard(url) }
                    advancedCard
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Nembra Capture")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TUYA SECURE-LINK PREFLIGHT")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.green)
            Text("Next test · indoor only")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("About 30–60 seconds. No riding. No charger. No repeated reconnect loop.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("READ / NOTIFY ONLY · NO SCOOTER COMMAND WRITES", systemImage: "shield.checkered")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var beforeYouStart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("BEFORE YOU START", systemImage: "checklist")
                .font(.headline)
                .foregroundStyle(.white)
            Text("1. Keep the scooter ON and near the iPhone.\n2. In the Tuya app, open the scooter → edit/••• → Device Information and copy the Virtual ID. Product ID is optional if shown.\n3. Then fully close the Tuya app so it is not holding the Bluetooth connection.\n4. Come back here and tap Start preflight.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Do not enter your Tuya password anywhere in Nembra Capture.", systemImage: "lock.shield")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .padding(18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var referenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("TUYA DEVICE INFO + ODOMETER REFERENCE", systemImage: "number.square")
                .font(.headline)
                .foregroundStyle(.white)
            TextField("Virtual ID from Tuya Device Information", text: $capture.tuyaVirtualID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField("Product ID / PID (optional)", text: $capture.tuyaProductID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Tuya current miles", text: $capture.currentTuyaOdometerMiles)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                TextField("Lifetime miles", text: $capture.userTrackedLifetimeMiles)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Reference loaded: 665.3 + 429.5 + 1070 = 2164.8 lifetime miles. This stays labeled as your tracked history until Bluetooth data proves an odometer DP.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("RUN THE PREFLIGHT", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(stageText)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(stageColor)
            }
            Text(capture.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if capture.stage == .ready || capture.stage == .candidateReady || capture.stage == .disconnected {
                Button("Start Tuya preflight") { capture.startScan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(capture.bluetoothState != .poweredOn)
            } else if capture.stage == .scanning {
                ProgressView("Finding the known Tuya FD50 scooter…").tint(.white)
            } else if capture.stage == .connecting {
                ProgressView("Connecting…").tint(.white)
            }
        }
        .padding(18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var candidateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FOUND TUYA DEVICES")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(capture.candidates) { candidate in
                Button { capture.connect(candidate) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(candidate.name).font(.headline).foregroundStyle(.white)
                                if candidate.likelyScooter {
                                    Text("LIKELY SCOOTER")
                                        .font(.caption2.monospaced().weight(.bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(.green, in: Capsule())
                                }
                            }
                            Text(candidate.reasons.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("\(candidate.rssiText) · confidence score \(candidate.score)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(candidate.likelyScooter ? .green.opacity(0.10) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(capture.stage == .connecting || capture.isConnected)
            }
        }
        .padding(18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var liveCard: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            VStack(alignment: .leading, spacing: 10) {
                Label("LIVE SECURE-LINK CHECK", systemImage: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(.white)
                LabeledContent("Device", value: capture.selectedPeripheralName ?? "Tuya peripheral")
                LabeledContent("Connection", value: capture.isConnected ? "Connected" : "Disconnected")
                LabeledContent("Connected time", value: String(format: "%.1f s", capture.currentConnectionSeconds(now: context.date)))
                LabeledContent("FD50", value: capture.serviceFD50Seen ? "Seen" : "Waiting")
                LabeledContent("Write 0001", value: capture.writeCharacteristicSeen ? "Seen · NOT USED" : "Waiting")
                LabeledContent("Notify 0002", value: capture.notifyCharacteristicSeen ? (capture.notificationsEnabled ? "Listening" : "Seen") : "Waiting")
                LabeledContent("Optional read 0003", value: capture.readCharacteristicSeen ? "Seen" : "Not exposed")
                LabeledContent("Application payloads", value: "\(capture.applicationPayloadCount)")
                LabeledContent("Disconnects", value: "\(capture.disconnectCount)")
                Text("If this reaches about 30 seconds and the scooter beeps/disconnects with zero payloads, Capture will stop the loop and mark the Tuya authentication blocker instead of reconnecting forever.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(capture.resultTitle)
                .font(.title3.bold())
                .foregroundStyle(capture.stage == .payloadReceived ? .green : .orange)
            Text(resultExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Stop & prepare preflight JSON") { capture.stopAndExport() }
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background((capture.stage == .payloadReceived ? Color.green : Color.orange).opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func shareCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("PREFLIGHT READY TO SHARE", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(url.lastPathComponent)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text("Share this JSON back into ChatGPT. This is the only test I need from you before deciding the next authentication step; do not redo the outdoor calibration yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ShareLink(item: url) {
                Label("Share Tuya preflight JSON", systemImage: "square.and.arrow.up.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var advancedCard: some View {
        DisclosureGroup("Advanced / reset", isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 12) {
                Text("The previous full 17-step calibration is intentionally not shown here. Physical capture C7D09A22 already proved the Tuya FD50 transport and the repeatable unauthenticated timeout. Outdoor calibration stays locked until real authenticated application payloads exist.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Reset preflight") { capture.resetAll() }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .tint(.white)
        .padding(18)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var stageText: String {
        switch capture.stage {
        case .ready: return "READY"
        case .scanning: return "SCANNING"
        case .candidateReady: return "FOUND"
        case .connecting: return "CONNECTING"
        case .listening: return "LISTENING"
        case .authBlocked: return "AUTH BLOCKED"
        case .payloadReceived: return "PAYLOAD!"
        case .survivedCutoffNoPayload: return "36S+"
        case .disconnected: return "STOPPED"
        case .readyToShare: return "DONE"
        }
    }

    private var stageColor: Color {
        switch capture.stage {
        case .payloadReceived, .readyToShare: return .green
        case .authBlocked, .disconnected: return .orange
        default: return .secondary
        }
    }

    private var resultExplanation: String {
        switch capture.stage {
        case .authBlocked:
            return "This matches the first physical run: Tuya FD50 connected, but the bound scooter did not authenticate Nembra and removed the link around 30 seconds. The Virtual ID you entered is now bundled with the exact preflight evidence for the next secure-link implementation step."
        case .payloadReceived:
            return "Actual bytes arrived from Tuya characteristic 0002. That is the gate we needed. Share the JSON before changing modes, lights, brakes, charger state, or riding."
        case .survivedCutoffNoPayload:
            return "The BLE link stayed alive beyond the old timeout, but no application payload arrived. Share this result; the next step will focus on the secure application session rather than repeating rides."
        default:
            return "The connection ended outside the known timeout. Share the result so I can distinguish transport failure from Tuya authentication behavior."
        }
    }
}
