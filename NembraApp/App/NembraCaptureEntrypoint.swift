@preconcurrency import CoreBluetooth
import CoreTransferable
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
#if canImport(ThingSmartHomeKit)
import ThingSmartHomeKit
#endif

let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable

@main @MainActor
struct NembraCaptureApp: App {
    var body: some Scene { WindowGroup { CaptureP0Root().preferredColorScheme(.dark) } }
}

@MainActor
private struct CaptureP0Root: View {
    @StateObject private var tuya = TuyaAccountBridge()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("P0 · TUYA AUTHENTICATION").font(.caption.monospaced().bold()).foregroundStyle(.green)
                    Text("Prove the secure scooter link first.").font(.largeTitle.bold())
                    Text("The next physical run is stationary. It proves supported Tuya authentication, at least 45 s continuity, and real application updates through Tuya's own SDK. The old 17-step ride sequence stays disabled until this passes.").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Read-only control boundary", systemImage: "shield.checkered").font(.headline)
                        Text("Account linking is used for ownership/device identity. Nembra does not turn local_key into a BLE login key, synthesize Tuya authentication frames, or open a second CoreBluetooth connection after the official SDK takes ownership.").foregroundStyle(.secondary)
                        Text("No unbind, reset, lock, speed, light, mode, throttle, brake, firmware, or other DP command is sent.").font(.footnote.bold()).foregroundStyle(.green)
                    }.card()
                    accountCard
                    if tuya.isLinked { deviceCard }
                }.frame(maxWidth: 760).padding(18).frame(maxWidth: .infinity)
            }.background(Color.black.ignoresSafeArea()).navigationTitle("Nembra Capture")
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("1 · Identify your bound Tuya device", systemImage: "person.badge.key").font(.headline)
            Text(tuya.statusMessage).font(.footnote).foregroundStyle(.secondary)
            if !tuya.isLinked {
                TextField("Tuya Smart User Code", text: $tuya.userCode).textInputAutocapitalization(.never).autocorrectionDisabled().padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                Button("Create approval QR") { tuya.requestApproval() }.buttonStyle(.borderedProminent).disabled(tuya.phase == .requestingApproval)
            }
            if let data = tuya.qrPNGData, let image = UIImage(data: data), !tuya.isLinked {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 230).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 14))
                Button("I approved it · check now") { tuya.checkApprovalNow() }.buttonStyle(.bordered)
            }
            if tuya.phase == .failed { Button("Reset account link") { tuya.resetLink() }.buttonStyle(.bordered) }
        }.card()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2 · Choose the scooter", systemImage: "bicycle").font(.headline)
            if tuya.devices.isEmpty { Button("Refresh Tuya devices") { tuya.refreshDevices() }.buttonStyle(.bordered) }
            ForEach(tuya.devices) { device in
                VStack(alignment: .leading, spacing: 7) {
                    Text(device.name.isEmpty ? "Unnamed Tuya device" : device.name).font(.headline)
                    Text([device.productName, device.category].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(tuya.selectedDeviceID == device.id ? "Refresh metadata" : "Use this device") { tuya.selectDevice(device) }.buttonStyle(.bordered)
                        if tuya.selectedDeviceID == device.id, tuya.phase == .ready, !device.productID.isEmpty, !device.uuid.isEmpty {
                            NavigationLink("Secure link test") { SecureLinkView(device: device) }.buttonStyle(.borderedProminent)
                        }
                    }
                }.padding(12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Only Tuya device ID, device UUID and product ID enter the supported secure-link controller. local_key does not.").font(.footnote).foregroundStyle(.secondary)
        }.card()
    }
}

@MainActor
private final class SecureLinkController: NSObject, ObservableObject, TuyaReadOnlyAuthenticationSessionProvider {
    struct Candidate: Identifiable, Codable, Equatable {
        let id: UUID
        var name: String?
        var rssi: Int?
        var advertisements: Int
        var newAfterPowerOn: Bool
        var fd50: Bool
        var tuyaCompany: Bool
        var knownID: Bool
        var expectedName: Bool
        var score: Int
        var evidence: [String]
        var title: String { name?.isEmpty == false ? name! : "Unnamed peripheral" }
        var likely: Bool { knownID || (fd50 && tuyaCompany) || score >= 600 }
    }
    enum Phase: String, Codable { case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed }
    struct Event: Codable { let at: Date; let kind: String; let details: [String: String] }
    struct Export: Codable {
        let schemaVersion: Int
        let purpose: String
        let exportedAt: Date
        let tuyaDeviceID: String
        let tuyaUUID: String
        let productID: String
        let selectedPeripheralID: String?
        let phase: Phase
        let sdkCompiled: Bool
        let privateConfigPresent: Bool
        let sdkAccountAuthorized: Bool
        let secureSessionEstablished: Bool
        let secureSessionAgeSeconds: Double?
        let sdkLocalBLEOnline: Bool
        let applicationUpdateCount: Int
        let connectionGeneration: UInt64
        let connectionStartedAtUptimeNanoseconds: UInt64?
        let authenticatedAtUptimeNanoseconds: UInt64?
        let latestObservedUptimeNanoseconds: UInt64?
        let latestApplicationPayloadUptimeNanoseconds: UInt64?
        let authoritativePreflightDecision: String
        let secretsRedacted: Bool
        let dpCommandsSent: Bool
        let candidates: [Candidate]
        let events: [Event]
    }

    static let knownPeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    static let fd50 = CBUUID(string: "FD50")
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Start with the scooter OFF. This test only identifies it and proves Tuya's supported secure session."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var applicationUpdateCount = 0
    @Published private(set) var secureSessionEstablished = false
    @Published private(set) var sdkLocalBLEOnline = false
    @Published private(set) var preflightVerdict: TuyaAuthenticatedReadOnlyPreflight.Verdict = .blocked(reason: "Tuya authentication required.")
    @Published private(set) var exportData: Data?
    @Published private(set) var exportName = "Nembra-Secure-Link-Diagnostics.json"
    let deviceID: String
    let deviceName: String
    let productID: String
    let tuyaUUID: String
    private var central: CBCentralManager!
    private var byID: [UUID: Candidate] = [:]
    private var baseline = Set<UUID>()
    private var driver: OfficialTuyaDriver?
    private var connectionGeneration: UInt64 = 0
    private var connectionStartedAtUptime: UInt64?
    private var authenticatedAtUptime: UInt64?
    private var latestObservedAtUptime: UInt64?
    private var latestApplicationPayloadAtUptime: UInt64?
    private var events: [Event] = []
    private var watchdog: Task<Void, Never>?

    init(device: TuyaAccountBridge.LinkedDevice) {
        deviceID = device.id; deviceName = device.name; productID = device.productID; tuyaUUID = device.uuid
        super.init(); central = CBCentralManager(delegate: self, queue: .main); log("controller_created")
    }
    deinit { watchdog?.cancel() }
    var sdkCompiled: Bool { OfficialTuyaFactory.compiled }
    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var sdkAccountAuthorized: Bool { OfficialTuyaFactory.accountReady }
    var selected: Candidate? { selectedID.flatMap { byID[$0] } }
    var secureSessionAgeSeconds: Double? {
        guard let start = authenticatedAtUptime, let latest = latestObservedAtUptime, latest >= start else { return nil }
        return Double(latest - start) / 1_000_000_000
    }
    var passed: Bool { preflightVerdict == .readyForStationaryMapping }

    func currentPreflightSnapshot() async -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        makePreflightSnapshot()
    }

    func startBaseline() {
        guard central.state == .poweredOn else { fail("Bluetooth is not ready.", "bluetooth_unavailable"); return }
        resetDiscovery(); phase = .baseline; message = "Keep the scooter OFF for a few seconds."; log("baseline_started")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    func saveBaseline() {
        guard phase == .baseline else { return }
        central.stopScan(); baseline = Set(byID.keys); phase = .powerOn; message = "Baseline saved. Turn the scooter ON and keep it stationary."; log("baseline_saved", ["count": String(baseline.count)])
    }
    func scanAfterPowerOn() {
        guard central.state == .poweredOn else { fail("Bluetooth is not ready.", "bluetooth_unavailable"); return }
        phase = .scanning; message = "Ranking OFF→ON delta, known peripheral, FD50, Tuya company ID, name and RSSI."; log("power_on_scan_started")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    func stopScan() {
        central.stopScan()
        if selectedID == nil, let first = candidates.first, first.likely { choose(first) }
        if selectedID == nil { message = "No candidate has enough scooter/Tuya evidence. Re-scan instead of guessing." }
        log("scan_stopped")
    }
    func choose(_ candidate: Candidate) {
        guard candidate.likely else { message = "Candidate confidence is too low. Re-scan instead of guessing."; return }
        central.stopScan(); selectedID = candidate.id; phase = .selected
        message = "Likely scooter selected. CoreBluetooth discovery is stopped before Tuya's SDK takes connection ownership."
        log("candidate_selected", ["id": candidate.id.uuidString, "score": String(candidate.score), "evidence": candidate.evidence.joined(separator: ",")])
    }
    func authenticate() {
        guard let candidate = selected, candidate.likely else { fail("A strongly matched scooter candidate is required.", "candidate_not_confident"); return }
        guard !deviceID.isEmpty, !tuyaUUID.isEmpty, !productID.isEmpty else { fail("Tuya device ID, UUID or product ID is missing.", "tuya_identity_incomplete"); return }
        guard sdkCompiled, privateConfig else { fail("Official Tuya SmartLife SDK/security configuration is not provisioned. Do not run the physical test yet.", "sdk_unavailable"); return }
        guard sdkAccountAuthorized else { fail("The official Tuya SDK has no authorized account session. The metadata QR session cannot substitute for SDK login.", "sdk_account_not_authorized"); return }
        guard let newDriver = OfficialTuyaFactory.make() else { fail("Official Tuya provider is unavailable.", "sdk_provider_unavailable"); return }
        guard connectionGeneration < UInt64.max else { fail("Connection generation exhausted. Restart Nembra Capture before another secure-link attempt.", "connection_generation_exhausted"); return }
        connectionGeneration += 1
        let activeGeneration = connectionGeneration
        let now = DispatchTime.now().uptimeNanoseconds
        connectionStartedAtUptime = now
        authenticatedAtUptime = nil
        latestObservedAtUptime = now
        latestApplicationPayloadAtUptime = nil
        applicationUpdateCount = 0
        secureSessionEstablished = false
        sdkLocalBLEOnline = false
        preflightVerdict = .blocked(reason: "Tuya authentication is still in progress.")
        central.stopScan(); driver = newDriver; phase = .authenticating; message = "Tuya's SDK is establishing the supported secure BLE session. Nembra sends no DP command."
        log("official_connect_requested", ["coreBluetoothID": candidate.id.uuidString, "tuyaDeviceID": deviceID, "tuyaUUID": tuyaUUID, "productID": productID, "connectionGeneration": String(activeGeneration)])
        newDriver.connect(
            deviceID: deviceID,
            uuid: tuyaUUID,
            productID: productID,
            onApplicationUpdate: { [weak self] update in
                Task { @MainActor in self?.receivedApplicationUpdate(update, generation: activeGeneration) }
            },
            success: { [weak self] in
                Task { @MainActor in self?.officialConnectReturnedSuccess(generation: activeGeneration) }
            },
            failure: { [weak self] error in
                Task { @MainActor in self?.officialConnectFailed(error, generation: activeGeneration) }
            }
        )
    }
    private func officialConnectReturnedSuccess(generation: UInt64) {
        guard generation == connectionGeneration, phase == .authenticating, driver != nil else {
            log("stale_official_connect_success_ignored", ["callbackGeneration": String(generation), "currentGeneration": String(connectionGeneration)])
            return
        }
        phase = .observing
        log("official_connect_success_callback", ["connectionGeneration": String(generation)])
        refreshLocalConnectionEvidence()
        if sdkLocalBLEOnline {
            message = "Tuya's local BLE session is current. Waiting for application updates and the 45-second authenticated stability gate…"
        } else {
            message = "Tuya accepted the connection request. Waiting for its SDK to prove the local BLE session is current…"
        }
        startWatchdog()
    }
    private func officialConnectFailed(_ text: String, generation: UInt64) {
        guard generation == connectionGeneration, [.authenticating, .observing].contains(phase) else {
            log("stale_official_connect_failure_ignored", ["callbackGeneration": String(generation), "currentGeneration": String(connectionGeneration)])
            return
        }
        fail(text, "official_connect_failed")
    }
    private func receivedApplicationUpdate(_ update: [String: String], generation: UInt64) {
        guard generation == connectionGeneration else {
            log("stale_application_update_ignored", ["callbackGeneration": String(generation), "currentGeneration": String(connectionGeneration), "entries": String(update.count)])
            return
        }
        guard secureSessionEstablished, sdkLocalBLEOnline, authenticatedAtUptime != nil else {
            log("application_update_ignored_before_current_auth", ["entries": String(update.count), "connectionGeneration": String(generation)])
            return
        }
        let now = DispatchTime.now().uptimeNanoseconds
        applicationUpdateCount += 1
        latestApplicationPayloadAtUptime = now
        latestObservedAtUptime = now
        log("tuya_application_update", update.merging(["connectionGeneration": String(generation)]) { current, _ in current })
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshAuthoritativeVerdict()
            self.updateAcceptedPresentationIfNeeded()
        }
        message = "Receiving scooter application data · \(applicationUpdateCount) update(s). Keep it stationary until the canonical 45-second gate passes."
    }
    private func startWatchdog() {
        watchdog?.cancel(); watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let driver = self.driver, [.authenticating, .observing, .accepted].contains(self.phase) else { return }
                let wasLocallyOnline = self.sdkLocalBLEOnline
                let isLocallyOnline = driver.isLocallyConnected(uuid: self.tuyaUUID)
                let now = DispatchTime.now().uptimeNanoseconds
                self.sdkLocalBLEOnline = isLocallyOnline
                if isLocallyOnline {
                    if !wasLocallyOnline || self.authenticatedAtUptime == nil {
                        self.secureSessionEstablished = true
                        self.authenticatedAtUptime = now
                        self.latestObservedAtUptime = now
                        self.log("sdk_local_ble_authenticated", ["connectionGeneration": String(self.connectionGeneration)])
                    } else {
                        self.latestObservedAtUptime = now
                    }
                } else if self.authenticatedAtUptime != nil {
                    self.secureSessionEstablished = false
                    self.fail("Tuya's local BLE session dropped before acceptance. Export diagnostics; do not repeat the outdoor ride capture.", "sdk_local_ble_dropped")
                    return
                }
                await self.refreshAuthoritativeVerdict()
                if self.passed {
                    self.phase = .accepted
                    self.message = "Secure scooter link passed. Tuya delivered real application data and the canonical preflight accepted at least 45 seconds of current authenticated continuity."
                    self.log("acceptance_passed", ["applicationUpdates": String(self.applicationUpdateCount), "connectionGeneration": String(self.connectionGeneration)])
                    return
                }
                if let age = self.secureSessionAgeSeconds, age > 60, self.applicationUpdateCount == 0 {
                    self.fail("The authenticated session survived, but Tuya delivered no application update within 60 seconds.", "no_application_updates")
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func prepareExport() {
        let envelope = Export(
            schemaVersion: 3,
            purpose: "Sanitized Tuya authenticated read-only preflight",
            exportedAt: Date(),
            tuyaDeviceID: deviceID,
            tuyaUUID: tuyaUUID,
            productID: productID,
            selectedPeripheralID: selectedID?.uuidString,
            phase: phase,
            sdkCompiled: sdkCompiled,
            privateConfigPresent: privateConfig,
            sdkAccountAuthorized: sdkAccountAuthorized,
            secureSessionEstablished: secureSessionEstablished,
            secureSessionAgeSeconds: secureSessionAgeSeconds,
            sdkLocalBLEOnline: sdkLocalBLEOnline,
            applicationUpdateCount: applicationUpdateCount,
            connectionGeneration: connectionGeneration,
            connectionStartedAtUptimeNanoseconds: connectionStartedAtUptime,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptime,
            latestObservedUptimeNanoseconds: latestObservedAtUptime,
            latestApplicationPayloadUptimeNanoseconds: latestApplicationPayloadAtUptime,
            authoritativePreflightDecision: authoritativeDecisionText,
            secretsRedacted: true,
            dpCommandsSent: false,
            candidates: candidates,
            events: events
        )
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .iso8601; exportData = try encoder.encode(envelope); exportName = "Nembra-Secure-Link-\(deviceID.prefix(8))-Diagnostics.json"; message = "Sanitized diagnostics ready. Passwords, account tokens, local_key and AppSecret are excluded." } catch { message = "Diagnostic export failed: \(error.localizedDescription)" }
    }
    private func makePreflightSnapshot() -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        let hasCurrentAuthenticatedSession = secureSessionEstablished && sdkLocalBLEOnline && authenticatedAtUptime != nil
        let authenticationState: TuyaAuthenticatedReadOnlyPreflightSnapshot.AuthenticationState
        switch phase {
        case .failed:
            authenticationState = .failed(reason: message)
        case .authenticating:
            authenticationState = .authenticating
        case .observing, .accepted:
            authenticationState = hasCurrentAuthenticatedSession ? .authenticated : .authenticating
        default:
            if !sdkCompiled || !privateConfig {
                authenticationState = .unavailable(reason: "Official Tuya SmartLife SDK/security configuration is not provisioned.")
            } else {
                authenticationState = .waitingForAuthentication
            }
        }
        return TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: authenticationState,
            authenticationMethod: hasCurrentAuthenticatedSession ? .smartLifeAppSDK : nil,
            connectionStartedAtUptimeNanoseconds: connectionStartedAtUptime,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptime,
            latestObservedUptimeNanoseconds: latestObservedAtUptime,
            applicationPayloadCount: applicationUpdateCount,
            latestApplicationPayloadUptimeNanoseconds: latestApplicationPayloadAtUptime,
            connectionGeneration: connectionGeneration
        )
    }
    private func refreshAuthoritativeVerdict() async {
        let provider: any TuyaReadOnlyAuthenticationSessionProvider = self
        let snapshot = await provider.currentPreflightSnapshot()
        preflightVerdict = TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot)
    }
    private func refreshLocalConnectionEvidence() {
        guard let driver else { return }
        let isLocallyOnline = driver.isLocallyConnected(uuid: tuyaUUID)
        sdkLocalBLEOnline = isLocallyOnline
        guard isLocallyOnline else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        secureSessionEstablished = true
        if authenticatedAtUptime == nil {
            authenticatedAtUptime = now
            log("sdk_local_ble_authenticated", ["connectionGeneration": String(connectionGeneration)])
        }
        latestObservedAtUptime = now
    }
    private func updateAcceptedPresentationIfNeeded() {
        guard passed else { return }
        phase = .accepted
        message = "Secure scooter link passed. Tuya delivered real application data and the canonical preflight accepted at least 45 seconds of current authenticated continuity."
    }
    private var authoritativeDecisionText: String {
        switch preflightVerdict {
        case .readyForStationaryMapping:
            return "ready-for-stationary-mapping"
        case let .blocked(reason):
            return "blocked: \(sanitize(reason))"
        }
    }
    private func resetDiscovery() {
        central.stopScan(); watchdog?.cancel(); watchdog = nil; driver = nil; byID.removeAll(); candidates.removeAll(); baseline.removeAll(); selectedID = nil
        secureSessionEstablished = false; sdkLocalBLEOnline = false; connectionStartedAtUptime = nil; authenticatedAtUptime = nil; latestObservedAtUptime = nil; latestApplicationPayloadAtUptime = nil; applicationUpdateCount = 0
        preflightVerdict = .blocked(reason: "Tuya authentication required."); exportData = nil
    }
    private func fail(_ text: String, _ kind: String) {
        watchdog?.cancel(); watchdog = nil; secureSessionEstablished = false; sdkLocalBLEOnline = false; phase = .failed; message = text; preflightVerdict = .blocked(reason: text); log(kind, ["message": sanitize(text)])
    }
    private func log(_ kind: String, _ details: [String: String] = [:]) { events.append(Event(at: Date(), kind: kind, details: details.mapValues(sanitize))) }
    private func sanitize(_ text: String) -> String { var result = text; for key in ["NEMBRA_TUYA_APP_KEY", "NEMBRA_TUYA_APP_SECRET"] { if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty { result = result.replacingOccurrences(of: value, with: "<redacted>") } }; return result }
    private static func hasTuyaCompanyID(_ data: Data?) -> Bool { guard let data, data.count >= 2 else { return false }; return (UInt16(data[data.startIndex]) | UInt16(data[data.index(after: data.startIndex)]) << 8) == 0x07D0 }
    private func updateCandidate(_ peripheral: CBPeripheral, advertisement: [String: Any], rssi number: NSNumber) {
        let id = peripheral.identifier; if phase == .baseline { baseline.insert(id) }
        let old = byID[id]; let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? old?.name; let rssi = number.intValue == 127 ? old?.rssi : number.intValue
        let serviceUUIDs = ((advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []) + ((advertisement[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []) + ((advertisement[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID]) ?? [])
        let serviceData = advertisement[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let fd50 = serviceUUIDs.contains(Self.fd50) || serviceData?.keys.contains(Self.fd50) == true || old?.fd50 == true
        let tuyaCompany = Self.hasTuyaCompanyID(advertisement[CBAdvertisementDataManufacturerDataKey] as? Data) || old?.tuyaCompany == true
        let knownID = id == Self.knownPeripheral; let newAfterPowerOn = (phase == .scanning && !baseline.contains(id)) || old?.newAfterPowerOn == true; let expectedName = name?.localizedCaseInsensitiveContains("demo") == true || name?.localizedCaseInsensitiveContains("tuya") == true || old?.expectedName == true
        var score = 0; var evidence: [String] = []
        if knownID { score += 1000; evidence.append("known previous UUID") }; if fd50 { score += 500; evidence.append("FD50") }; if tuyaCompany { score += 350; evidence.append("Tuya company 0x07D0") }; if newAfterPowerOn { score += 180; evidence.append("appeared after power-on") }; if expectedName { score += 100; evidence.append("expected name") }
        if let rssi { if rssi >= -50 { score += 80; evidence.append("very close RSSI") } else if rssi >= -65 { score += 50; evidence.append("nearby RSSI") } else if rssi >= -80 { score += 20 } }
        byID[id] = Candidate(id: id, name: name, rssi: rssi, advertisements: (old?.advertisements ?? 0) + 1, newAfterPowerOn: newAfterPowerOn, fd50: fd50, tuyaCompany: tuyaCompany, knownID: knownID, expectedName: expectedName, score: score, evidence: evidence)
        candidates = byID.values.sorted { $0.score == $1.score ? (($0.rssi ?? -999) > ($1.rssi ?? -999)) : $0.score > $1.score }
    }
}

extension SecureLinkController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) { log("central_state", ["raw": String(central.state.rawValue)]) }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) { guard [.baseline, .scanning].contains(phase) else { return }; updateCandidate(peripheral, advertisement: advertisementData, rssi: RSSI) }
}

@MainActor
private protocol OfficialTuyaDriver: AnyObject {
    func connect(deviceID: String, uuid: String, productID: String, onApplicationUpdate: @escaping ([String: String]) -> Void, success: @escaping () -> Void, failure: @escaping (String) -> Void)
    func isLocallyConnected(uuid: String) -> Bool
}

@MainActor
private enum OfficialTuyaFactory {
    static var compiled: Bool {
#if canImport(ThingSmartHomeKit)
        true
#else
        false
#endif
    }
    static var configured: Bool { compiled && !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_KEY"] ?? "").isEmpty && !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_SECRET"] ?? "").isEmpty }
    static var accountReady: Bool {
#if canImport(ThingSmartHomeKit)
        ThingSmartUser.sharedInstance()?.isLogin == true
#else
        false
#endif
    }
    static func make() -> OfficialTuyaDriver? {
#if canImport(ThingSmartHomeKit)
        guard configured, accountReady else { return nil }; return SmartLifeDriver()
#else
        return nil
#endif
    }
}

#if canImport(ThingSmartHomeKit)
@MainActor
private final class SmartLifeDriver: NSObject, OfficialTuyaDriver, ThingSmartDeviceDelegate {
    private var device: ThingSmartDevice?
    private var onApplicationUpdate: (([String: String]) -> Void)?
    func connect(deviceID: String, uuid: String, productID: String, onApplicationUpdate: @escaping ([String: String]) -> Void, success: @escaping () -> Void, failure: @escaping (String) -> Void) {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["NEMBRA_TUYA_APP_KEY"], !key.isEmpty, let secret = environment["NEMBRA_TUYA_APP_SECRET"], !secret.isEmpty else { failure("Private Tuya SDK credentials are missing."); return }
        self.onApplicationUpdate = onApplicationUpdate; ThingSmartSDK.sharedInstance()?.start(withAppKey: key, secretKey: secret)
        device = ThingSmartDevice(deviceId: deviceID); device?.delegate = self
        ThingSmartBLEManager.sharedInstance().connectBLE(withUUID: uuid, productKey: productID, success: success, failure: { error in failure("Tuya SmartLife SDK did not establish the BLE session: \(error?.localizedDescription ?? "unknown error")") })
    }
    func isLocallyConnected(uuid: String) -> Bool { ThingSmartBLEManager.sharedInstance().deviceStatue(withUUID: uuid) }
    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps { sanitized[String(describing: key)] = String(describing: value) }
        onApplicationUpdate?(sanitized)
    }
}
#endif

@MainActor
private struct SecureLinkView: View {
    @StateObject private var test: SecureLinkController
    init(device: TuyaAccountBridge.LinkedDevice) { _test = StateObject(wrappedValue: SecureLinkController(device: device)) }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SMALLEST INDOOR TEST").font(.caption.monospaced().bold()).foregroundStyle(.green)
                    Text("Authenticate. Wait. Capture.").font(.largeTitle.bold())
                    Text("Keep the scooter stationary. Do not run the old 17-step sequence.").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(test.passed ? "Secure scooter link established" : test.phase == .failed ? "Secure-link test stopped" : "Authentication preflight").font(.headline); Spacer(); Text("\(test.applicationUpdateCount)").monospacedDigit() }
                        Text(test.message).font(.footnote).foregroundStyle(.secondary)
                        if let age = test.secureSessionAgeSeconds { LabeledContent("Canonical authenticated age", value: String(format: "%.1f s", age)); ProgressView(value: min(age / 45, 1)) }
                        LabeledContent("Tuya local BLE", value: test.sdkLocalBLEOnline ? "Online" : "Not proven")
                        LabeledContent("Application updates", value: String(test.applicationUpdateCount))
                        LabeledContent("Package preflight", value: test.passed ? "Accepted" : "Blocked")
                    }.card()
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Official Tuya gate", systemImage: "checkmark.shield").font(.headline)
                        LabeledContent("SDK compiled in", value: test.sdkCompiled ? "Yes" : "No")
                        LabeledContent("Private app config", value: test.privateConfig ? "Yes" : "No")
                        LabeledContent("SDK account authorized", value: test.sdkAccountAuthorized ? "Yes" : "No")
                        if !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized { Text("NO PHYSICAL TEST YET: Tuya's official SDK/security component, matching private app credentials, and an authorized SDK account session must all be ready. Metadata QR approval alone is not BLE authentication.").font(.footnote.bold()).foregroundStyle(.orange) }
                    }.card()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Find the known scooter", systemImage: "scope").font(.headline)
                        switch test.phase { case .idle, .failed: Button("Start scooter-OFF baseline") { test.startBaseline() }.buttonStyle(.borderedProminent); case .baseline: Button("Save OFF baseline") { test.saveBaseline() }.buttonStyle(.borderedProminent); case .powerOn: Text("Turn scooter ON, keep it still.").foregroundStyle(.secondary); Button("Scan after power-on") { test.scanAfterPowerOn() }.buttonStyle(.borderedProminent); case .scanning: Button("Stop scan / use best evidence") { test.stopScan() }.buttonStyle(.bordered); default: EmptyView() }
                        ForEach(test.candidates.prefix(8)) { candidate in
                            Button { test.choose(candidate) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(candidate.title).bold(); if candidate.likely { Text("LIKELY SCOOTER").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.green, in: Capsule()).foregroundStyle(.black) }; Spacer(); Text("\(candidate.score)").monospacedDigit() }
                                    Text("\(candidate.rssi.map { String($0) + " dBm" } ?? "RSSI ?") · \(candidate.id.uuidString)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    Text(candidate.evidence.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }.card()
                    if let candidate = test.selected {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Authentication gate", systemImage: "key.horizontal").font(.headline)
                            Text(candidate.evidence.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                            Button("Start secure read-only test") { test.authenticate() }.buttonStyle(.borderedProminent).disabled(!candidate.likely || !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized || [.authenticating, .observing, .accepted].contains(test.phase))
                        }.card()
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Acceptance", systemImage: test.passed ? "checkmark.seal.fill" : "hourglass").font(.headline).foregroundStyle(test.passed ? .green : .white)
                        Text("Pass only when the authoritative TuyaAuthenticatedReadOnlyPreflight accepts the current connection generation: official SmartLife authentication provenance, current local BLE, at least one current post-auth application update, valid monotonic chronology, and at least 45 seconds after authentication. Nembra still assigns no DP meaning here.").font(.footnote).foregroundStyle(.secondary)
                        if test.passed { Text("Secure scooter link established\nReceiving scooter data").font(.title3.bold()).foregroundStyle(.green) }
                    }.card()
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Prepare sanitized diagnostic JSON") { test.prepareExport() }.buttonStyle(.bordered)
                        if let data = test.exportData { ShareLink(item: SecureTransfer(data: data, name: test.exportName), preview: SharePreview(test.exportName)) { Label("Share diagnostic JSON", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent) }
                        Text("Export includes candidate evidence, connection generation, canonical monotonic chronology, SDK-local status, failures and opaque application-update values. It excludes passwords, account tokens, local_key and AppSecret.").font(.footnote).foregroundStyle(.secondary)
                    }.card()
                }.frame(maxWidth: 760).padding(18).frame(maxWidth: .infinity)
            }.background(Color.black.ignoresSafeArea())
        }.navigationTitle("Secure Link")
    }
}

private struct SecureTransfer: Transferable {
    let data: Data; let name: String
    static var transferRepresentation: some TransferRepresentation { DataRepresentation(exportedContentType: .json) { $0.data }.suggestedFileName { $0.name } }
}
private extension View { func card() -> some View { padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20)) } }
