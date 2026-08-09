@preconcurrency import CoreBluetooth
import Combine
@preconcurrency import CoreLocation
import CoreTransferable
import Dispatch
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One-purpose capture utility: learn a scooter from raw, passive CoreBluetooth evidence.
///
/// This intentionally exposes no application-characteristic write API. It may scan, connect,
/// discover GATT topology, read characteristics/descriptors, subscribe to notify/indicate
/// characteristics, sample RSSI/location reference data, and record operator scenario markers.
@MainActor
final class ES80GuidedBluetoothCapture: NSObject, ObservableObject {
    struct Candidate: Identifiable, Equatable {
        let id: UUID
        var name: String?
        var rssi: Int?
        var connectable: Bool?
        var firstSeen: Date
        var lastSeen: Date
        var advertisementCount: Int
        var appearedAfterPowerOn: Bool

        var displayName: String {
            guard let name, !name.isEmpty else { return "Unnamed peripheral" }
            return name
        }

        var rssiText: String {
            rssi.map { "\($0) dBm" } ?? "RSSI unavailable"
        }
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
        let scenarioID: String?
        let scenarioTitle: String?
        let details: [String: String]
        let error: ErrorRecord?
    }

    struct ScenarioRun: Codable, Identifiable, Equatable {
        enum State: String, Codable {
            case completed
            case skipped
        }

        let id: UUID
        let scenarioID: String
        let scenarioTitle: String
        let phase: String
        let startedAt: Date
        let finishedAt: Date
        let startedAtMonotonicNanoseconds: UInt64
        let finishedAtMonotonicNanoseconds: UInt64
        let state: State
        let note: String?
        let startEventID: Int
        let endEventID: Int

        var durationSeconds: Double {
            guard finishedAtMonotonicNanoseconds >= startedAtMonotonicNanoseconds else { return 0 }
            return Double(finishedAtMonotonicNanoseconds - startedAtMonotonicNanoseconds) / 1_000_000_000
        }
    }

    struct CaptureSummary: Codable {
        let advertisementCount: Int
        let serviceUUIDs: [String]
        let characteristicUUIDs: [String]
        let readableCharacteristicUUIDs: [String]
        let notifyingCharacteristicUUIDs: [String]
        let descriptorUUIDs: [String]
        let characteristicValueEventCount: Int
        let descriptorValueEventCount: Int
        let locationReferenceSampleCount: Int
        let completedScenarioCount: Int
        let skippedScenarioCount: Int
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
        let locationReferenceAuthorization: String
        let summary: CaptureSummary
        let scenarioRuns: [ScenarioRun]
        let limitations: [String]
        let events: [Event]
    }

    struct ScenarioDefinition: Identifiable, Equatable {
        enum MotionClass: String {
            case stationary
            case walking
            case moving
            case elevatedWheel
        }

        let id: String
        let phase: String
        let title: String
        let instruction: String
        let completionHint: String
        let recommendedSeconds: Int
        let optional: Bool
        let motionClass: MotionClass
        let caution: String?
    }

    enum DiscoveryStage: Equatable {
        case idle
        case baselineScanning
        case waitingForPowerOn
        case poweredOnScanning
        case quickScanning
        case connecting
        case connected
    }

    static let scenarios: [ScenarioDefinition] = [
        .init(id: "stationary-idle", phase: "Stationary", title: "Idle baseline", instruction: "Leave the scooter powered on, stationary, and untouched. This gives us a clean baseline for every live Bluetooth stream.", completionHint: "Let it sit for about 20 seconds, then complete the step.", recommendedSeconds: 20, optional: false, motionClass: .stationary, caution: nil),
        .init(id: "eco-mode", phase: "Modes", title: "ECO mode", instruction: "While fully stopped, switch the scooter to ECO mode using the scooter's own controls. Do not use another Bluetooth app while Nembra is connected.", completionHint: "Leave ECO selected for about 10 seconds.", recommendedSeconds: 10, optional: true, motionClass: .stationary, caution: "Skip this step if your scooter does not have ECO mode."),
        .init(id: "drive-mode", phase: "Modes", title: "Drive / Normal mode", instruction: "While fully stopped, switch to the normal/Drive mode using the scooter's own controls.", completionHint: "Leave the mode selected for about 10 seconds.", recommendedSeconds: 10, optional: true, motionClass: .stationary, caution: "Skip if your scooter has no separate normal/Drive mode."),
        .init(id: "sport-mode", phase: "Modes", title: "Sport mode", instruction: "While fully stopped, switch to Sport/high-performance mode using the scooter's own controls.", completionHint: "Leave Sport selected for about 10 seconds.", recommendedSeconds: 10, optional: true, motionClass: .stationary, caution: "Skip if your scooter has no Sport mode."),
        .init(id: "light-off", phase: "Controls", title: "Light OFF", instruction: "While stopped, make sure the headlight is OFF. Leave it that way briefly so we can identify any state change.", completionHint: "Wait about 8 seconds.", recommendedSeconds: 8, optional: true, motionClass: .stationary, caution: "Skip if there is no user-controlled light."),
        .init(id: "light-on", phase: "Controls", title: "Light ON", instruction: "While stopped, turn the headlight ON using the scooter's own controls.", completionHint: "Leave it ON for about 8 seconds.", recommendedSeconds: 8, optional: true, motionClass: .stationary, caution: "Skip if there is no user-controlled light."),
        .init(id: "brake-hold", phase: "Controls", title: "Brake held", instruction: "While fully stationary, squeeze and hold the brake lever. Keep the scooter from moving.", completionHint: "Hold about 5 seconds, release, then complete.", recommendedSeconds: 5, optional: false, motionClass: .stationary, caution: nil),
        .init(id: "brake-pulses", phase: "Controls", title: "Brake pulses", instruction: "While stationary, squeeze and release the brake three times with a clear pause between each press.", completionHint: "Complete after the third release.", recommendedSeconds: 8, optional: false, motionClass: .stationary, caution: nil),
        .init(id: "walk-roll", phase: "Motion", title: "Walking wheel roll", instruction: "Walk the scooter forward slowly by hand for a short distance, then stop. Do not ride it during this step.", completionHint: "A few seconds of clean rolling is enough.", recommendedSeconds: 10, optional: false, motionClass: .walking, caution: "Keep both hands on the scooter and do not touch the phone until the scooter is stopped again."),
        .init(id: "elevated-wheel", phase: "Motion", title: "Optional unloaded motor sweep", instruction: "Only if the scooter can be supported securely with the driven wheel completely clear: gently apply throttle for a few seconds, release, and let the wheel stop.", completionHint: "Complete only after the wheel is fully stopped.", recommendedSeconds: 8, optional: true, motionClass: .elevatedWheel, caution: "Skip unless the scooter is genuinely stable. Keep hands, clothing, cables, and people away from the spinning wheel."),
        .init(id: "ride-slow", phase: "Ride", title: "Slow straight ride", instruction: "Start this step while fully stopped. Secure the phone in a pocket or fixed mount, then ride straight at a slow steady speed. Stop completely before touching the phone again.", completionHint: "Aim for roughly 20 seconds of steady low-speed riding.", recommendedSeconds: 20, optional: false, motionClass: .moving, caution: "Never interact with the phone while the scooter is moving."),
        .init(id: "ride-medium", phase: "Ride", title: "Medium straight ride", instruction: "Start while stopped, secure the phone, then ride at a comfortable medium speed. Stop fully before completing this step.", completionHint: "Aim for roughly 20 seconds at a fairly steady speed.", recommendedSeconds: 20, optional: false, motionClass: .moving, caution: "Use a safe, legal, low-traffic area. Do not watch or touch the phone while moving."),
        .init(id: "accelerate-coast-brake", phase: "Ride", title: "Accelerate → coast → brake", instruction: "Start while stopped and secure the phone. Accelerate smoothly, hold briefly, release throttle to coast, then brake normally to a complete stop.", completionHint: "Complete the step only after you are fully stopped.", recommendedSeconds: 25, optional: false, motionClass: .moving, caution: "No phone interaction while moving. Use a clear, safe area with plenty of stopping distance."),
        .init(id: "eco-ride", phase: "Mode rides", title: "ECO ride", instruction: "While stopped, select ECO. Start the step, secure the phone, then do one short straight acceleration and steady segment. Stop fully before touching the phone.", completionHint: "About 20 seconds is enough.", recommendedSeconds: 20, optional: true, motionClass: .moving, caution: "Skip if ECO does not exist. Never use the phone while moving."),
        .init(id: "drive-ride", phase: "Mode rides", title: "Drive / Normal ride", instruction: "While stopped, select normal/Drive. Start the step, secure the phone, ride one short straight segment, then stop fully.", completionHint: "About 20 seconds is enough.", recommendedSeconds: 20, optional: true, motionClass: .moving, caution: "Skip if there is no separate normal/Drive mode. Never use the phone while moving."),
        .init(id: "sport-ride", phase: "Mode rides", title: "Sport ride", instruction: "While stopped, select Sport. Start the step, secure the phone, then do one short controlled straight segment. Stop fully before touching the phone.", completionHint: "We need a clean change, not maximum speed.", recommendedSeconds: 20, optional: true, motionClass: .moving, caution: "Do not chase top speed. Use only a speed and location that are safe and legal. Never interact with the phone while moving."),
        .init(id: "post-ride-idle", phase: "Finish", title: "Post-ride idle", instruction: "Leave the scooter powered on and stationary after the ride segments. Do not touch any controls.", completionHint: "Wait about 20 seconds so we can compare hot/post-motion idle with the opening baseline.", recommendedSeconds: 20, optional: false, motionClass: .stationary, caution: nil)
    ]

    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var discoveryStage: DiscoveryStage = .idle
    @Published private(set) var isScanning = false
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedPeripheralID: UUID?
    @Published private(set) var selectedPeripheralName: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var eventCount = 0
    @Published private(set) var connectedAt: Date?
    @Published private(set) var lastMessage = "Start with the scooter OFF so Nembra can learn which Bluetooth device appears when you power it on."
    @Published private(set) var exportData: Data?
    @Published private(set) var exportFilename = "Nembra-Scooter-Learning-Capture.json"
    @Published private(set) var activeScenarioID: String?
    @Published private(set) var activeScenarioStartedAt: Date?
    @Published private(set) var activeScenarioStartedUptimeNanoseconds: UInt64?
    @Published private(set) var currentScenarioIndex = 0
    @Published private(set) var scenarioRuns: [ScenarioRun] = []
    @Published private(set) var locationAuthorizationText = "Not requested"
    @Published private(set) var latestReferenceSpeedMPH: Double?
    @Published private(set) var latestReferenceHorizontalAccuracy: Double?
    @Published private(set) var droppedEventCount = 0

    private var central: CBCentralManager!
    private let locationManager = CLLocationManager()
    private var peripheralByID: [UUID: CBPeripheral] = [:]
    private var candidateByID: [UUID: Candidate] = [:]
    private var baselinePeripheralIDs: Set<UUID> = []
    private var activePeripheral: CBPeripheral?
    private var events: [Event] = []
    private var nextEventID = 1
    private let captureID = UUID()
    private let createdAt = Date()
    private var pendingReads = Set<ObjectIdentifier>()
    private var subscribeAfterRead = Set<ObjectIdentifier>()
    private var rssiTask: Task<Void, Never>?
    private var activeScenarioRunID: UUID?
    private var activeScenarioStartEventID: Int?
    private var observedServices: Set<String> = []
    private var observedCharacteristics: Set<String> = []
    private var readableCharacteristics: Set<String> = []
    private var notifyingCharacteristics: Set<String> = []
    private var observedDescriptors: Set<String> = []
    private var advertisementCount = 0
    private var characteristicValueEventCount = 0
    private var descriptorValueEventCount = 0
    private var locationReferenceSampleCount = 0
    private let maximumInMemoryEvents = 500_000

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        bluetoothState = central.state
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .otherNavigation
        refreshLocationAuthorizationText()
    }

    deinit {
        rssiTask?.cancel()
        locationManager.stopUpdatingLocation()
    }

    var currentScenario: ScenarioDefinition? {
        guard Self.scenarios.indices.contains(currentScenarioIndex) else { return nil }
        return Self.scenarios[currentScenarioIndex]
    }

    var completedScenarioCount: Int { scenarioRuns.filter { $0.state == .completed }.count }
    var skippedScenarioCount: Int { scenarioRuns.filter { $0.state == .skipped }.count }
    var scenarioProgressFraction: Double {
        guard !Self.scenarios.isEmpty else { return 1 }
        return min(1, Double(currentScenarioIndex) / Double(Self.scenarios.count))
    }

    func beginBaselineScan() {
        guard central.state == .poweredOn, !isConnected, !isConnecting else {
            lastMessage = "Bluetooth must be on and no scooter can already be connected."
            return
        }
        stopScanningIfNeeded(recordStop: false)
        baselinePeripheralIDs.removeAll()
        candidateByID.removeAll()
        candidates.removeAll()
        peripheralByID.removeAll()
        exportData = nil
        discoveryStage = .baselineScanning
        record(kind: "discovery_baseline_started")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        lastMessage = "Scooter OFF baseline is running. Leave the scooter OFF for about 8–10 seconds."
    }

    func finishBaseline() {
        guard discoveryStage == .baselineScanning else { return }
        stopScanningIfNeeded()
        baselinePeripheralIDs = Set(candidateByID.keys)
        discoveryStage = .waitingForPowerOn
        record(kind: "discovery_baseline_finished", details: ["baselinePeripheralCount": String(baselinePeripheralIDs.count)])
        lastMessage = "Baseline saved. Now turn the scooter ON, then tap Scan after power-on."
    }

    func beginPoweredOnScan() {
        guard central.state == .poweredOn, !isConnected, !isConnecting else { return }
        stopScanningIfNeeded(recordStop: false)
        candidateByID.removeAll()
        candidates.removeAll()
        peripheralByID.removeAll()
        discoveryStage = .poweredOnScanning
        record(kind: "discovery_power_on_scan_started", details: ["baselinePeripheralCount": String(baselinePeripheralIDs.count)])
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        lastMessage = "Scanning after power-on. Devices marked NEW were not present in the OFF baseline."
    }

    func beginQuickScan() {
        guard central.state == .poweredOn, !isConnected, !isConnecting else { return }
        stopScanningIfNeeded(recordStop: false)
        baselinePeripheralIDs.removeAll()
        candidateByID.removeAll()
        candidates.removeAll()
        peripheralByID.removeAll()
        discoveryStage = .quickScanning
        record(kind: "discovery_quick_scan_started")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        lastMessage = "Quick scanning. Pick the scooter only if you are confident which Bluetooth device it is."
    }

    func stopScan() {
        stopScanningIfNeeded()
        if discoveryStage == .baselineScanning {
            baselinePeripheralIDs = Set(candidateByID.keys)
            discoveryStage = .waitingForPowerOn
        }
        lastMessage = "Scan stopped."
    }

    func connect(to candidate: Candidate) {
        guard central.state == .poweredOn, !isConnecting, !isConnected, candidate.connectable != false, let peripheral = peripheralByID[candidate.id] else { return }
        stopScanningIfNeeded()
        exportData = nil
        selectedPeripheralID = candidate.id
        selectedPeripheralName = candidate.name
        activePeripheral = peripheral
        peripheral.delegate = self
        isConnecting = true
        discoveryStage = .connecting
        lastMessage = "Connecting to \(candidate.displayName)…"
        record(kind: "connect_requested", peripheral: peripheral, details: ["displayName": candidate.displayName, "appearedAfterPowerOn": candidate.appearedAfterPowerOn ? "true" : "false", "advertisementCountBeforeConnect": String(candidate.advertisementCount)])
        central.connect(peripheral)
    }

    func requestReferenceLocationIfNeeded() {
        refreshLocationAuthorizationText()
        switch locationManager.authorizationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: startReferenceLocation()
        default: record(kind: "location_reference_unavailable", details: ["authorization": locationAuthorizationText])
        }
    }

    func beginScenario(_ scenario: ScenarioDefinition) {
        guard isConnected else { lastMessage = "Connect the scooter before starting calibration steps."; return }
        guard activeScenarioID == nil else { lastMessage = "Finish or skip the current step first."; return }
        activeScenarioRunID = UUID()
        activeScenarioID = scenario.id
        activeScenarioStartedAt = Date()
        activeScenarioStartedUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        record(kind: "scenario_started", peripheral: activePeripheral, scenario: scenario, details: ["phase": scenario.phase, "recommendedSeconds": String(scenario.recommendedSeconds), "optional": scenario.optional ? "true" : "false", "motionClass": scenario.motionClass.rawValue])
        activeScenarioStartEventID = nextEventID - 1
        lastMessage = scenario.motionClass == .moving ? "Recording \(scenario.title). Do not touch the phone until you are fully stopped again." : "Recording \(scenario.title)."
    }

    func completeActiveScenario(note: String? = nil) {
        guard let scenarioID = activeScenarioID, let scenario = Self.scenarios.first(where: { $0.id == scenarioID }), let runID = activeScenarioRunID, let startedAt = activeScenarioStartedAt, let startedUptime = activeScenarioStartedUptimeNanoseconds, let startEventID = activeScenarioStartEventID else { return }
        let finishedAt = Date()
        let finishedUptime = DispatchTime.now().uptimeNanoseconds
        record(kind: "scenario_completed", peripheral: activePeripheral, scenario: scenario, details: ["durationSeconds": String(format: "%.3f", Double(finishedUptime - startedUptime) / 1_000_000_000), "operatorNote": normalizedOptional(note) ?? ""])
        let endEventID = nextEventID - 1
        scenarioRuns.append(ScenarioRun(id: runID, scenarioID: scenario.id, scenarioTitle: scenario.title, phase: scenario.phase, startedAt: startedAt, finishedAt: finishedAt, startedAtMonotonicNanoseconds: startedUptime, finishedAtMonotonicNanoseconds: finishedUptime, state: .completed, note: normalizedOptional(note), startEventID: startEventID, endEventID: endEventID))
        clearActiveScenario()
        advancePastScenario(scenario.id)
        lastMessage = "Saved \(scenario.title). Continue to the next step when ready."
    }

    func skipScenario(_ scenario: ScenarioDefinition, reason: String? = nil) {
        guard activeScenarioID == nil else { return }
        let now = Date()
        let uptime = DispatchTime.now().uptimeNanoseconds
        record(kind: "scenario_skipped", peripheral: activePeripheral, scenario: scenario, details: ["reason": normalizedOptional(reason) ?? "not available / intentionally skipped"])
        let eventID = nextEventID - 1
        scenarioRuns.append(ScenarioRun(id: UUID(), scenarioID: scenario.id, scenarioTitle: scenario.title, phase: scenario.phase, startedAt: now, finishedAt: now, startedAtMonotonicNanoseconds: uptime, finishedAtMonotonicNanoseconds: uptime, state: .skipped, note: normalizedOptional(reason), startEventID: eventID, endEventID: eventID))
        advancePastScenario(scenario.id)
        lastMessage = "Skipped \(scenario.title)."
    }

    func recordCustomAction(_ label: String) {
        guard let normalized = normalizedOptional(label) else { return }
        record(kind: "operator_custom_action", peripheral: activePeripheral, details: ["label": normalized])
        lastMessage = "Marked: \(normalized)"
    }

    func recordReference(label: String, value: String) {
        guard let normalizedLabel = normalizedOptional(label), let normalizedValue = normalizedOptional(value) else { return }
        record(kind: "operator_reference_value", peripheral: activePeripheral, details: ["label": normalizedLabel, "value": normalizedValue])
        lastMessage = "Reference saved: \(normalizedLabel) = \(normalizedValue)"
    }

    func prepareJSON() {
        if let scenarioID = activeScenarioID, let scenario = Self.scenarios.first(where: { $0.id == scenarioID }) { record(kind: "scenario_capture_exported_while_active", peripheral: activePeripheral, scenario: scenario) }
        let summary = CaptureSummary(advertisementCount: advertisementCount, serviceUUIDs: observedServices.sorted(), characteristicUUIDs: observedCharacteristics.sorted(), readableCharacteristicUUIDs: readableCharacteristics.sorted(), notifyingCharacteristicUUIDs: notifyingCharacteristics.sorted(), descriptorUUIDs: observedDescriptors.sorted(), characteristicValueEventCount: characteristicValueEventCount, descriptorValueEventCount: descriptorValueEventCount, locationReferenceSampleCount: locationReferenceSampleCount, completedScenarioCount: completedScenarioCount, skippedScenarioCount: skippedScenarioCount)
        let envelope = ExportEnvelope(schemaVersion: 2, purpose: "Guided scooter Bluetooth learning capture for Nembra protocol/capability calibration", captureID: captureID.uuidString, createdAt: createdAt, finishedAt: Date(), selectedPeripheralID: selectedPeripheralID?.uuidString, selectedPeripheralName: selectedPeripheralName, eventCount: events.count, buildIdentifier: normalizedBundleString("NembraCaptureBuildIdentifier"), buildSourceCommit: normalizedBundleString("NembraCaptureBuildCommitSHA"), locationReferenceAuthorization: locationAuthorizationText, summary: summary, scenarioRuns: scenarioRuns, limitations: ["This is a CoreBluetooth application-level capture, not an over-the-air BLE packet sniffer.", "It records advertisements exposed by iOS, GATT topology, readable characteristic values, notify/indicate callbacks, descriptor values exposed by CoreBluetooth, RSSI, lifecycle/errors, operator scenario markers, and optional iPhone location speed reference.", "This utility never issues CoreBluetooth application-characteristic value writes.", "Notification subscription may update the standard GATT Client Characteristic Configuration descriptor as required by CoreBluetooth; that is subscription transport state, not a scooter command.", "Observed bytes are raw evidence. Battery, speed, power, mode, brake, throttle, light, lock, cruise, and other semantics must be inferred only from repeatable scenario correlations.", "Another scooter app may not be able to stay connected at the same time. The guided flow is designed around scooter-local controls while Nembra owns the Bluetooth connection.", "Moving scenarios are started and completed only while fully stopped; the phone must not be handled while the scooter is moving."], events: events)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            exportData = try encoder.encode(envelope)
            exportFilename = "Nembra-Scooter-Learning-\(captureID.uuidString.prefix(8)).json"
            lastMessage = "Dataset ready. Share this exact JSON back into ChatGPT so the Bluetooth values can be mapped into Nembra."
        } catch { lastMessage = "JSON encoding failed: \(error.localizedDescription)" }
    }

    func finishCaptureAndPrepareJSON() {
        if isScanning { stopScanningIfNeeded() }
        locationManager.stopUpdatingLocation()
        rssiTask?.cancel(); rssiTask = nil
        record(kind: "operator_capture_finished", peripheral: activePeripheral)
        prepareJSON()
    }

    func reset() {
        stopScanningIfNeeded(recordStop: false)
        rssiTask?.cancel(); rssiTask = nil
        locationManager.stopUpdatingLocation()
        if let activePeripheral, activePeripheral.state != .disconnected { central.cancelPeripheralConnection(activePeripheral) }
        activePeripheral = nil; isConnecting = false; isConnected = false; connectedAt = nil; selectedPeripheralID = nil; selectedPeripheralName = nil; discoveryStage = .idle
        peripheralByID.removeAll(); candidateByID.removeAll(); baselinePeripheralIDs.removeAll(); candidates.removeAll(); pendingReads.removeAll(); subscribeAfterRead.removeAll(); events.removeAll(keepingCapacity: true)
        nextEventID = 1; eventCount = 0; exportData = nil; activeScenarioID = nil; activeScenarioStartedAt = nil; activeScenarioStartedUptimeNanoseconds = nil; activeScenarioRunID = nil; activeScenarioStartEventID = nil; currentScenarioIndex = 0; scenarioRuns.removeAll(); latestReferenceSpeedMPH = nil; latestReferenceHorizontalAccuracy = nil
        observedServices.removeAll(); observedCharacteristics.removeAll(); readableCharacteristics.removeAll(); notifyingCharacteristics.removeAll(); observedDescriptors.removeAll(); advertisementCount = 0; characteristicValueEventCount = 0; descriptorValueEventCount = 0; locationReferenceSampleCount = 0; droppedEventCount = 0
        lastMessage = "Reset complete. Start with the scooter OFF for the cleanest device identification."
    }

    func elapsedSecondsForActiveScenario(nowUptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Double {
        guard let start = activeScenarioStartedUptimeNanoseconds, nowUptimeNanoseconds >= start else { return 0 }
        return Double(nowUptimeNanoseconds - start) / 1_000_000_000
    }

    private func clearActiveScenario() { activeScenarioID = nil; activeScenarioStartedAt = nil; activeScenarioStartedUptimeNanoseconds = nil; activeScenarioRunID = nil; activeScenarioStartEventID = nil }
    private func advancePastScenario(_ id: String) { guard let index = Self.scenarios.firstIndex(where: { $0.id == id }) else { return }; currentScenarioIndex = min(index + 1, Self.scenarios.count) }
    private func stopScanningIfNeeded(recordStop: Bool = true) { guard isScanning else { return }; central.stopScan(); isScanning = false; if recordStop { record(kind: "scan_stopped") } }

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

    private func startReferenceLocation() {
        guard CLLocationManager.locationServicesEnabled() else { locationAuthorizationText = "Location Services disabled"; record(kind: "location_reference_unavailable", details: ["reason": "services_disabled"]); return }
        switch locationManager.authorizationStatus { case .authorizedAlways, .authorizedWhenInUse: locationManager.startUpdatingLocation(); record(kind: "location_reference_started"); default: break }
    }

    private func refreshLocationAuthorizationText() {
        switch locationManager.authorizationStatus { case .notDetermined: locationAuthorizationText = "Not requested"; case .restricted: locationAuthorizationText = "Restricted"; case .denied: locationAuthorizationText = "Denied"; case .authorizedAlways: locationAuthorizationText = "Authorized always"; case .authorizedWhenInUse: locationAuthorizationText = "Authorized while using app"; @unknown default: locationAuthorizationText = "Future authorization state" }
    }

    private func normalizedBundleString(_ key: String) -> String? { guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }; let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }; return trimmed }
    private func normalizedOptional(_ value: String?) -> String? { guard let value else { return nil }; let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines); return trimmed.isEmpty ? nil : trimmed }

    private func record(kind: String, peripheral: CBPeripheral? = nil, service: CBService? = nil, characteristic: CBCharacteristic? = nil, descriptor: CBDescriptor? = nil, origin: String? = nil, value: Data? = nil, rssi: Int? = nil, scenario: ScenarioDefinition? = nil, details: [String: String] = [:], error: Error? = nil) {
        guard events.count < maximumInMemoryEvents else { droppedEventCount += 1; return }
        let activeScenario = scenario ?? activeScenarioID.flatMap { id in Self.scenarios.first(where: { $0.id == id }) }
        let event = Event(id: nextEventID, wallClock: Date(), monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds, kind: kind, peripheralID: peripheral?.identifier.uuidString, serviceUUID: service?.uuid.uuidString.uppercased() ?? characteristic?.service?.uuid.uuidString.uppercased() ?? descriptor?.characteristic?.service?.uuid.uuidString.uppercased(), characteristicUUID: characteristic?.uuid.uuidString.uppercased() ?? descriptor?.characteristic?.uuid.uuidString.uppercased(), descriptorUUID: descriptor?.uuid.uuidString.uppercased(), origin: origin, valueBase64: value?.base64EncodedString(), valueHex: value.map(Self.hex), rssi: rssi, scenarioID: activeScenario?.id, scenarioTitle: activeScenario?.title, details: details, error: error.map(Self.errorRecord))
        events.append(event); nextEventID += 1; eventCount = events.count
    }

    private static func errorRecord(_ error: Error) -> ErrorRecord { let ns = error as NSError; return ErrorRecord(domain: ns.domain, code: ns.code, description: ns.localizedDescription) }
    private static func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined() }
    private static func characteristicProperties(_ properties: CBCharacteristicProperties) -> String { var names: [String] = []; if properties.contains(.broadcast) { names.append("broadcast") }; if properties.contains(.read) { names.append("read") }; if properties.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }; if properties.contains(.write) { names.append("write") }; if properties.contains(.notify) { names.append("notify") }; if properties.contains(.indicate) { names.append("indicate") }; if properties.contains(.authenticatedSignedWrites) { names.append("authenticatedSignedWrites") }; if properties.contains(.extendedProperties) { names.append("extendedProperties") }; if properties.contains(.notifyEncryptionRequired) { names.append("notifyEncryptionRequired") }; if properties.contains(.indicateEncryptionRequired) { names.append("indicateEncryptionRequired") }; return names.joined(separator: ",") }

    private static func describeDescriptorValue(_ value: Any?) -> [String: String] {
        guard let value else { return ["valueType": "nil"] }
        if let data = value as? Data { return ["valueType": "Data", "valueBase64": data.base64EncodedString(), "valueHex": hex(data)] }
        if let string = value as? String { return ["valueType": "String", "value": string] }
        if let number = value as? NSNumber { return ["valueType": "NSNumber", "value": number.stringValue] }
        return ["valueType": String(describing: type(of: value)), "value": String(describing: value)]
    }

    private static func advertisementDetails(_ advertisementData: [String: Any], rssi: NSNumber) -> [String: String] {
        var details: [String: String] = [:]
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String { details["localName"] = name }
        if let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber { details["isConnectable"] = connectable.boolValue ? "true" : "false" }
        if let tx = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber { details["txPower"] = tx.stringValue }
        if let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data { details["manufacturerDataBase64"] = manufacturer.base64EncodedString(); details["manufacturerDataHex"] = hex(manufacturer) }
        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] { details["serviceUUIDs"] = uuids.map { $0.uuidString.uppercased() }.joined(separator: ",") }
        if let uuids = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] { details["overflowServiceUUIDs"] = uuids.map { $0.uuidString.uppercased() }.joined(separator: ",") }
        if let uuids = advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] { details["solicitedServiceUUIDs"] = uuids.map { $0.uuidString.uppercased() }.joined(separator: ",") }
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] { for (uuid, data) in serviceData { let key = uuid.uuidString.uppercased(); details["serviceData.\(key).base64"] = data.base64EncodedString(); details["serviceData.\(key).hex"] = hex(data) } }
        details["rssiRaw"] = rssi.stringValue; details["advertisementKeys"] = advertisementData.keys.sorted().joined(separator: ",")
        for key in advertisementData.keys.sorted() where details["raw.\(key)"] == nil { let value = advertisementData[key]; if let data = value as? Data { details["raw.\(key).base64"] = data.base64EncodedString(); details["raw.\(key).hex"] = hex(data) } else { details["raw.\(key)"] = String(describing: value ?? "nil") } }
        return details
    }

    private static func centralStateName(_ state: CBManagerState) -> String { switch state { case .unknown: return "unknown"; case .resetting: return "resetting"; case .unsupported: return "unsupported"; case .unauthorized: return "unauthorized"; case .poweredOff: return "poweredOff"; case .poweredOn: return "poweredOn"; @unknown default: return "future" } }
}

extension ES80GuidedBluetoothCapture: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) { bluetoothState = central.state; record(kind: "central_state", details: ["state": Self.centralStateName(central.state)]); if central.state != .poweredOn, isScanning { isScanning = false; lastMessage = "Bluetooth became unavailable." } }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let normalizedRSSI = RSSI.intValue == 127 ? nil : RSSI.intValue
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let connectable = (advertisementData[CBAdvertisementDataIsConnectableKey] as? NSNumber)?.boolValue
        peripheralByID[peripheral.identifier] = peripheral
        if discoveryStage == .baselineScanning { baselinePeripheralIDs.insert(peripheral.identifier) }
        let existing = candidateByID[peripheral.identifier]
        let candidate = Candidate(id: peripheral.identifier, name: localName ?? existing?.name, rssi: normalizedRSSI, connectable: connectable ?? existing?.connectable, firstSeen: existing?.firstSeen ?? Date(), lastSeen: Date(), advertisementCount: (existing?.advertisementCount ?? 0) + 1, appearedAfterPowerOn: discoveryStage == .poweredOnScanning && !baselinePeripheralIDs.contains(peripheral.identifier))
        candidateByID[peripheral.identifier] = candidate
        candidates = candidateByID.values.sorted { if $0.appearedAfterPowerOn != $1.appearedAfterPowerOn { return $0.appearedAfterPowerOn && !$1.appearedAfterPowerOn }; switch ($0.rssi, $1.rssi) { case let (.some(left), .some(right)) where left != right: return left > right; case (.some, .none): return true; case (.none, .some): return false; default: return $0.id.uuidString < $1.id.uuidString } }
        advertisementCount += 1
        record(kind: "advertisement", peripheral: peripheral, rssi: normalizedRSSI, details: Self.advertisementDetails(advertisementData, rssi: RSSI).merging(["appearedAfterPowerOn": candidate.appearedAfterPowerOn ? "true" : "false"], uniquingKeysWith: { current, _ in current }))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { isConnecting = false; isConnected = true; discoveryStage = .connected; connectedAt = Date(); activePeripheral = peripheral; peripheral.delegate = self; selectedPeripheralName = peripheral.name ?? selectedPeripheralName; record(kind: "connected", peripheral: peripheral, details: ["peripheralName": peripheral.name ?? ""]); lastMessage = "Connected. Nembra is dumping all discoverable/readable/notifying GATT data. Start the guided calibration steps."; peripheral.discoverServices(nil); peripheral.readRSSI(); startRSSIPolling(); requestReferenceLocationIfNeeded() }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { isConnecting = false; isConnected = false; discoveryStage = baselinePeripheralIDs.isEmpty ? .idle : .waitingForPowerOn; record(kind: "connect_failed", peripheral: peripheral, error: error); lastMessage = "Connection failed. Scan again and retry the candidate." }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) { rssiTask?.cancel(); rssiTask = nil; locationManager.stopUpdatingLocation(); isConnecting = false; isConnected = false; record(kind: "disconnected", peripheral: peripheral, error: error); if exportData == nil { lastMessage = "Disconnected. The data already captured is still available; reconnect or export it." } }
}

extension ES80GuidedBluetoothCapture: @preconcurrency CBPeripheralDelegate {
    func peripheralDidUpdateName(_ peripheral: CBPeripheral) { selectedPeripheralName = peripheral.name ?? selectedPeripheralName; record(kind: "peripheral_name_updated", peripheral: peripheral, details: ["name": peripheral.name ?? ""]) }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) { record(kind: "services_invalidated", peripheral: peripheral, details: ["serviceUUIDs": invalidatedServices.map { $0.uuid.uuidString.uppercased() }.joined(separator: ",")]); peripheral.discoverServices(nil) }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        record(kind: "services_discovered", peripheral: peripheral, error: error); guard error == nil, let services = peripheral.services else { return }
        for service in services { let uuid = service.uuid.uuidString.uppercased(); observedServices.insert(uuid); record(kind: "service", peripheral: peripheral, service: service, details: ["isPrimary": service.isPrimary ? "true" : "false"]); peripheral.discoverIncludedServices(nil, for: service); peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        record(kind: "included_services_discovered", peripheral: peripheral, service: service, error: error); guard error == nil else { return }
        for included in service.includedServices ?? [] { let includedUUID = included.uuid.uuidString.uppercased(); observedServices.insert(includedUUID); record(kind: "included_service", peripheral: peripheral, service: service, details: ["includedServiceUUID": includedUUID, "includedServiceIsPrimary": included.isPrimary ? "true" : "false"]); peripheral.discoverCharacteristics(nil, for: included) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        record(kind: "characteristics_discovered", peripheral: peripheral, service: service, error: error); guard error == nil else { return }
        for characteristic in service.characteristics ?? [] {
            let characteristicUUID = characteristic.uuid.uuidString.uppercased(); observedCharacteristics.insert(characteristicUUID)
            let properties = Self.characteristicProperties(characteristic.properties); let canRead = characteristic.properties.contains(.read); let canNotify = characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
            if canRead { readableCharacteristics.insert(characteristicUUID) }; if canNotify { notifyingCharacteristics.insert(characteristicUUID) }
            record(kind: "characteristic", peripheral: peripheral, characteristic: characteristic, details: ["properties": properties, "isNotifyingAtDiscovery": characteristic.isNotifying ? "true" : "false"])
            peripheral.discoverDescriptors(for: characteristic)
            let key = ObjectIdentifier(characteristic)
            if canRead { pendingReads.insert(key); if canNotify { subscribeAfterRead.insert(key) }; record(kind: "characteristic_read_requested", peripheral: peripheral, characteristic: characteristic); peripheral.readValue(for: characteristic) } else if canNotify { record(kind: "subscription_requested", peripheral: peripheral, characteristic: characteristic); peripheral.setNotifyValue(true, for: characteristic) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) { record(kind: "descriptors_discovered", peripheral: peripheral, characteristic: characteristic, error: error); guard error == nil else { return }; for descriptor in characteristic.descriptors ?? [] { observedDescriptors.insert(descriptor.uuid.uuidString.uppercased()); record(kind: "descriptor", peripheral: peripheral, descriptor: descriptor); record(kind: "descriptor_read_requested", peripheral: peripheral, descriptor: descriptor); peripheral.readValue(for: descriptor) } }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let key = ObjectIdentifier(characteristic); let wasPendingRead = pendingReads.remove(key) != nil; let shouldSubscribeNow = wasPendingRead && subscribeAfterRead.remove(key) != nil; let origin = wasPendingRead ? "read" : (characteristic.isNotifying ? "notify_or_indicate" : "unsolicited_callback")
        if let error { record(kind: "characteristic_value_error", peripheral: peripheral, characteristic: characteristic, origin: origin, error: error) } else { characteristicValueEventCount += 1; record(kind: "characteristic_value", peripheral: peripheral, characteristic: characteristic, origin: origin, value: characteristic.value, details: ["byteCount": String(characteristic.value?.count ?? 0), "isNotifying": characteristic.isNotifying ? "true" : "false"]) }
        if shouldSubscribeNow { record(kind: "subscription_requested_after_read", peripheral: peripheral, characteristic: characteristic); peripheral.setNotifyValue(true, for: characteristic) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) { record(kind: "subscription_state", peripheral: peripheral, characteristic: characteristic, details: ["isNotifying": characteristic.isNotifying ? "true" : "false"], error: error) }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) { var details = Self.describeDescriptorValue(descriptor.value); details["descriptorUUID"] = descriptor.uuid.uuidString.uppercased(); if error == nil { descriptorValueEventCount += 1 }; record(kind: error == nil ? "descriptor_value" : "descriptor_value_error", peripheral: peripheral, descriptor: descriptor, details: details, error: error) }
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) { let normalizedRSSI = RSSI.intValue == 127 ? nil : RSSI.intValue; record(kind: "rssi", peripheral: peripheral, rssi: normalizedRSSI, details: ["raw": RSSI.stringValue], error: error) }
}

extension ES80GuidedBluetoothCapture: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { refreshLocationAuthorizationText(); record(kind: "location_authorization", details: ["authorization": locationAuthorizationText]); if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { startReferenceLocation() } }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { guard isConnected else { return }; for location in locations { guard location.horizontalAccuracy >= 0 else { continue }; let speedMetersPerSecond = location.speed >= 0 ? location.speed : 0; let speedMPH = speedMetersPerSecond * 2.2369362920544; latestReferenceSpeedMPH = speedMPH; latestReferenceHorizontalAccuracy = location.horizontalAccuracy; locationReferenceSampleCount += 1; record(kind: "location_reference", peripheral: activePeripheral, details: ["speedMetersPerSecond": String(format: "%.4f", speedMetersPerSecond), "speedMPH": String(format: "%.4f", speedMPH), "horizontalAccuracyMeters": String(format: "%.3f", location.horizontalAccuracy), "verticalAccuracyMeters": String(format: "%.3f", location.verticalAccuracy), "courseDegrees": location.course >= 0 ? String(format: "%.3f", location.course) : "", "courseAccuracyDegrees": location.courseAccuracy >= 0 ? String(format: "%.3f", location.courseAccuracy) : "", "altitudeMeters": String(format: "%.3f", location.altitude)]) } }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { record(kind: "location_reference_error", error: error) }
}

private struct GuidedCaptureTransfer: Transferable {
    let data: Data
    let filename: String
    static var transferRepresentation: some TransferRepresentation { DataRepresentation(exportedContentType: .json) { transfer in transfer.data }.suggestedFileName { transfer in transfer.filename } }
}

@MainActor
struct ES80OneTimeBluetoothDumpView: View {
    @StateObject private var capture = ES80GuidedBluetoothCapture()
    @State private var customAction = ""
    @State private var referenceLabel = ""
    @State private var referenceValue = ""
    @State private var scenarioNote = ""
    @State private var showingAdvanced = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header; statusCard
                        if !capture.isConnected { discoveryCard } else { connectedScooterCard; calibrationCard; referenceCard; captureHealthCard; finishCard }
                        if let data = capture.exportData { shareCard(data: data) }
                        advancedDisclosure
                    }
                    .frame(maxWidth: 760).padding(.horizontal, 18).padding(.vertical, 20).frame(maxWidth: .infinity)
                }
                .background(Color.black.ignoresSafeArea())
            }
            .navigationTitle("Nembra Capture").navigationBarTitleDisplayMode(.inline).preferredColorScheme(.dark)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }

    private var header: some View { VStack(alignment: .leading, spacing: 8) { Text("SCOOTER LEARNING").font(.caption.monospaced().weight(.bold)).tracking(1.3).foregroundStyle(.secondary); Text("Teach Nembra your scooter.").font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(.white); Text("Nembra will find the scooter, record every passive Bluetooth value iOS exposes, and guide you through the actions that make those values change.").font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true); Label("READ / NOTIFY ONLY · NO SCOOTER COMMAND WRITES", systemImage: "shield.checkered").font(.caption.monospaced().weight(.bold)).foregroundStyle(.green) } }

    private var statusCard: some View { HStack(alignment: .top, spacing: 12) { Image(systemName: capture.isConnected ? "antenna.radiowaves.left.and.right.circle.fill" : "wave.3.right").font(.title2).foregroundStyle(capture.isConnected ? .green : .white).accessibilityHidden(true); VStack(alignment: .leading, spacing: 5) { Text(capture.isConnected ? "Scooter connected" : bluetoothStateTitle).font(.headline).foregroundStyle(.white); Text(capture.lastMessage).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }; Spacer(minLength: 8); Text("\(capture.eventCount)").font(.headline.monospacedDigit()).foregroundStyle(.white).accessibilityLabel("\(capture.eventCount) captured events") }.padding(16).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous)) }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("1 · FIND THE SCOOTER", systemImage: "scope").font(.headline).foregroundStyle(.white)
            switch capture.discoveryStage {
            case .idle:
                Text("Best method: leave the scooter OFF, scan the room for 8–10 seconds, save that baseline, then power the scooter ON. Nembra will mark Bluetooth devices that newly appeared.").font(.subheadline).foregroundStyle(.secondary)
                Button("Start scooter-OFF baseline") { capture.beginBaselineScan() }.buttonStyle(.borderedProminent).disabled(capture.bluetoothState != .poweredOn)
                Button("I already know the device · quick scan") { capture.beginQuickScan() }.buttonStyle(.bordered).disabled(capture.bluetoothState != .poweredOn)
            case .baselineScanning:
                Text("Keep the scooter OFF. Let this run for about 8–10 seconds.").foregroundStyle(.secondary); Button("Baseline done") { capture.finishBaseline() }.buttonStyle(.borderedProminent)
            case .waitingForPowerOn:
                Text("Now turn the scooter ON. Wait a moment, then start the second scan.").foregroundStyle(.secondary); Button("Scan after power-on") { capture.beginPoweredOnScan() }.buttonStyle(.borderedProminent)
            case .poweredOnScanning, .quickScanning:
                Text(capture.discoveryStage == .poweredOnScanning ? "Tap the likely scooter. NEW means the device was not present while the scooter was OFF." : "Tap the scooter only when you are confident which device it is.").foregroundStyle(.secondary); Button("Stop scan") { capture.stopScan() }.buttonStyle(.bordered)
            case .connecting: ProgressView("Connecting…").tint(.white)
            case .connected: EmptyView()
            }
            if !capture.candidates.isEmpty {
                VStack(spacing: 10) {
                    ForEach(capture.candidates) { candidate in
                        Button { capture.connect(to: candidate) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 7) { Text(candidate.displayName).font(.headline).foregroundStyle(.white); if candidate.appearedAfterPowerOn { Text("NEW").font(.caption2.monospaced().weight(.bold)).foregroundStyle(.black).padding(.horizontal, 7).padding(.vertical, 3).background(.green, in: Capsule()) } }
                                    Text(candidate.id.uuidString).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                    Text("\(candidate.rssiText) · \(candidate.advertisementCount) ads").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(14).background(candidate.appearedAfterPowerOn ? .green.opacity(0.10) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain).disabled(candidate.connectable == false || capture.isConnecting)
                    }
                }
            }
        }.padding(18).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var connectedScooterCard: some View { VStack(alignment: .leading, spacing: 10) { Label("2 · LIVE BLUETOOTH DUMP", systemImage: "dot.radiowaves.left.and.right").font(.headline).foregroundStyle(.white); LabeledContent("Device", value: capture.selectedPeripheralName ?? "Unnamed"); LabeledContent("UUID", value: capture.selectedPeripheralID?.uuidString ?? "Unknown"); LabeledContent("Reference speed", value: referenceSpeedText); LabeledContent("Location reference", value: capture.locationAuthorizationText); Text("Every scenario marker below is written into the same timeline as the raw Bluetooth callbacks. That lets us compare exactly which bytes changed when you changed a mode, brake, light, wheel speed, or ride state.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }.padding(18).background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous)) }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label("3 · GUIDED CALIBRATION", systemImage: "list.bullet.clipboard").font(.headline).foregroundStyle(.white); Spacer(); Text("\(min(capture.currentScenarioIndex, ES80GuidedBluetoothCapture.scenarios.count))/\(ES80GuidedBluetoothCapture.scenarios.count)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary) }
            ProgressView(value: capture.scenarioProgressFraction).tint(.green)
            if let scenario = capture.currentScenario { scenarioCard(scenario) } else { Label("Guided sequence complete", systemImage: "checkmark.seal.fill").font(.title3.weight(.semibold)).foregroundStyle(.green); Text("You can still add custom capability/reference markers below, then prepare the final JSON.").foregroundStyle(.secondary) }
            if capture.completedScenarioCount > 0 || capture.skippedScenarioCount > 0 { Text("\(capture.completedScenarioCount) completed · \(capture.skippedScenarioCount) skipped").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }.padding(18).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func scenarioCard(_ scenario: ES80GuidedBluetoothCapture.ScenarioDefinition) -> some View {
        let isActive = capture.activeScenarioID == scenario.id; let elapsed = isActive ? capture.elapsedSecondsForActiveScenario() : 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) { VStack(alignment: .leading, spacing: 4) { Text(scenario.phase.uppercased()).font(.caption2.monospaced().weight(.bold)).foregroundStyle(.secondary); Text(scenario.title).font(.title3.weight(.semibold)).foregroundStyle(.white) }; Spacer(); if scenario.optional { Text("OPTIONAL").font(.caption2.monospaced().weight(.bold)).foregroundStyle(.secondary) } }
            Text(scenario.instruction).font(.body).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            if let caution = scenario.caution { Label(caution, systemImage: "exclamationmark.triangle.fill").font(.footnote.weight(.semibold)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Text(scenario.completionHint).font(.footnote).foregroundStyle(.secondary)
            if isActive {
                HStack { Label("RECORDING", systemImage: "record.circle.fill").font(.caption.monospaced().weight(.bold)).foregroundStyle(.red); Spacer(); Text(timeText(elapsed)).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(.white) }
                if scenario.recommendedSeconds > 0 { ProgressView(value: min(1, elapsed / Double(scenario.recommendedSeconds))).tint(elapsed >= Double(scenario.recommendedSeconds) ? .green : .white) }
                TextField("Optional note about what happened", text: $scenarioNote, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
                Button(scenario.motionClass == .moving ? "I am fully stopped · complete step" : "Complete step") { capture.completeActiveScenario(note: scenarioNote); scenarioNote = "" }.buttonStyle(.borderedProminent)
            } else {
                Button(startButtonTitle(for: scenario)) { scenarioNote = ""; capture.beginScenario(scenario) }.buttonStyle(.borderedProminent)
                if scenario.optional { Button("Skip — scooter doesn't have this / not safe here") { capture.skipScenario(scenario) }.buttonStyle(.bordered) }
            }
        }.padding(16).background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var referenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("EXTRA CAPABILITIES + REFERENCE VALUES", systemImage: "plus.circle").font(.headline).foregroundStyle(.white)
            Text("Use these while stopped for anything the guided list does not cover. Examples: horn, cruise, lock state, units, zero-start, speed limit, a dashboard battery %, or a display reading.").font(.footnote).foregroundStyle(.secondary)
            TextField("Action you just triggered (example: horn pressed)", text: $customAction).textFieldStyle(.roundedBorder)
            Button("Mark custom action now") { capture.recordCustomAction(customAction); customAction = "" }.buttonStyle(.bordered).disabled(customAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Divider().overlay(.white.opacity(0.12))
            TextField("Reference label (example: dashboard battery)", text: $referenceLabel).textFieldStyle(.roundedBorder)
            TextField("Reference value (example: 73%)", text: $referenceValue).textFieldStyle(.roundedBorder)
            Button("Record reference value") { capture.recordReference(label: referenceLabel, value: referenceValue); referenceLabel = ""; referenceValue = "" }.buttonStyle(.bordered).disabled(referenceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || referenceValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(18).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var captureHealthCard: some View { VStack(alignment: .leading, spacing: 10) { Label("CAPTURE HEALTH", systemImage: "waveform.path.ecg").font(.headline).foregroundStyle(.white); LabeledContent("Raw events", value: "\(capture.eventCount)"); LabeledContent("Completed steps", value: "\(capture.completedScenarioCount)"); LabeledContent("Skipped steps", value: "\(capture.skippedScenarioCount)"); LabeledContent("GPS reference", value: referenceSpeedText); if capture.droppedEventCount > 0 { Label("\(capture.droppedEventCount) events exceeded the in-memory safety ceiling", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange) }; Text("Keep the stock scooter app closed while Nembra owns the Bluetooth connection. If there is an extra scooter-local control we did not list, mark it above while stopped.").font(.footnote).foregroundStyle(.secondary) }.padding(18).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous)) }

    private var finishCard: some View { VStack(alignment: .leading, spacing: 12) { Label("4 · FINISH + SHARE", systemImage: "square.and.arrow.up").font(.headline).foregroundStyle(.white); Text("When you have finished the guided steps, prepare one JSON. It contains the complete event timeline plus scenario boundaries so we can map the real scooter protocol.").font(.subheadline).foregroundStyle(.secondary); Button("Finish capture & prepare JSON") { capture.finishCaptureAndPrepareJSON() }.buttonStyle(.borderedProminent); Button("Prepare a snapshot without ending capture") { capture.prepareJSON() }.buttonStyle(.bordered) }.padding(18).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous)) }

    private func shareCard(data: Data) -> some View { VStack(alignment: .leading, spacing: 12) { Label("DATASET READY", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green); Text(capture.exportFilename).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled); Text("Share this exact JSON back into ChatGPT. That is the evidence used to identify services, characteristics, modes, speed, battery, power, brake/throttle state, lights, and other repeatable capabilities.").font(.subheadline).foregroundStyle(.secondary); ShareLink(item: GuidedCaptureTransfer(data: data, filename: capture.exportFilename), preview: SharePreview(capture.exportFilename)) { Label("Share learning dataset", systemImage: "square.and.arrow.up.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent) }.padding(18).background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous)) }

    private var advancedDisclosure: some View { DisclosureGroup("Advanced / reset", isExpanded: $showingAdvanced) { VStack(alignment: .leading, spacing: 12) { Text("This tool intentionally does not decode or control the scooter yet. It gathers evidence first. Future universal-scooter support can reuse this same guided scenario model to learn a new scooter before enabling only capabilities that are actually verified.").font(.footnote).foregroundStyle(.secondary); Button("Reset entire capture", role: .destructive) { capture.reset(); customAction = ""; referenceLabel = ""; referenceValue = ""; scenarioNote = "" } }.padding(.top, 10) }.foregroundStyle(.secondary) }

    private var bluetoothStateTitle: String { switch capture.bluetoothState { case .unknown: return "Bluetooth starting…"; case .resetting: return "Bluetooth resetting…"; case .unsupported: return "Bluetooth unsupported"; case .unauthorized: return "Bluetooth permission required"; case .poweredOff: return "Turn Bluetooth on"; case .poweredOn: return "Ready to find scooter"; @unknown default: return "Bluetooth state changed" } }
    private var referenceSpeedText: String { guard let speed = capture.latestReferenceSpeedMPH else { return "Waiting / unavailable" }; if let accuracy = capture.latestReferenceHorizontalAccuracy { return String(format: "%.1f mph · ±%.0f m", speed, accuracy) }; return String(format: "%.1f mph", speed) }
    private func startButtonTitle(for scenario: ES80GuidedBluetoothCapture.ScenarioDefinition) -> String { switch scenario.motionClass { case .stationary: return "Start \(scenario.title)"; case .walking: return "Start while stopped · then walk scooter"; case .moving: return "Start while stopped · then secure phone"; case .elevatedWheel: return "Start optional bench step" } }
    private func timeText(_ seconds: Double) -> String { let total = max(0, Int(seconds)); return String(format: "%d:%02d", total / 60, total % 60) }
}
