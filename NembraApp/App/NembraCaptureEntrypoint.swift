@preconcurrency import CoreBluetooth
import CoreTransferable
import Foundation
import NembraBluetoothCapture
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
                    Text("The next physical run is stationary. It verifies exact SDK-account scooter membership, supported Tuya authentication, observed local-BLE survival beyond 45 seconds, and genuine application updates. The old 17-step ride sequence stays disabled until this passes.").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Read-only control boundary", systemImage: "shield.checkered").font(.headline)
                        Text("Account linking is used for ownership/device identity. Nembra does not turn local_key into a BLE login key, synthesize Tuya authentication frames, or open a second CoreBluetooth connection after the official SDK takes ownership.").foregroundStyle(.secondary)
                        Text("No unbind, reset, lock, speed, light, mode, throttle, brake, firmware, or other DP command is sent.").font(.footnote.bold()).foregroundStyle(.green)
                    }.card()
                    accountCard
                    if tuya.isLinked { deviceCard }
                }
                .frame(maxWidth: 760)
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Nembra Capture")
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("1 · Identify your bound Tuya device", systemImage: "person.badge.key").font(.headline)
            Text(tuya.statusMessage).font(.footnote).foregroundStyle(.secondary)
            if !tuya.isLinked {
                TextField("Tuya Smart User Code", text: $tuya.userCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                Button("Create approval QR") { tuya.requestApproval() }
                    .buttonStyle(.borderedProminent)
                    .disabled(tuya.phase == .requestingApproval)
            }
            if let data = tuya.qrPNGData, let image = UIImage(data: data), !tuya.isLinked {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 230)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
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
                }
                .padding(12)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Only Tuya device ID, device UUID and product ID enter the supported secure-link controller. local_key does not.").font(.footnote).foregroundStyle(.secondary)
        }.card()
    }
}

@MainActor
private final class SecureLinkController: NSObject, ObservableObject {
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
        var likely: Bool { knownID || (fd50 && tuyaCompany) }
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
        let sdkDeviceMembershipAuthorized: Bool
        let secureSessionEstablished: Bool
        let secureSessionAgeSeconds: Double?
        let sdkLocalBLEOnline: Bool
        let connectionGeneration: UInt64
        let canonicalPreflightVerdict: String
        let applicationUpdateCount: Int
        let applicationValueRepresentation: String
        let rawFD50BytesCaptured: Bool
        let secretsRedacted: Bool
        let dpCommandsSent: Bool
        let candidates: [Candidate]
        let events: [Event]
    }

    static let knownPeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    static let fd50 = CBUUID(string: "FD50")
    static let localBLEAcquireTimeoutNanoseconds: UInt64 = 15_000_000_000

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Start with the scooter OFF. This test only identifies it and proves Tuya's supported secure session."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var applicationUpdateCount = 0
    @Published private(set) var secureSessionEstablished = false
    @Published private(set) var sdkLocalBLEOnline = false
    @Published private(set) var sdkDeviceMembershipAuthorized = false
    @Published private(set) var sdkDeviceMembershipMessage = "Exact SDK-account scooter membership has not been checked yet."
    @Published private(set) var membershipCheckInProgress = false
    @Published private(set) var secureSessionAgeSeconds: Double?
    @Published private(set) var connectionGeneration: UInt64 = 0
    @Published private(set) var canonicalPreflightReady = false
    @Published private(set) var canonicalPreflightReason = "No current authenticated connection generation."
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
    private var membershipProbe: OfficialTuyaMembershipProbe?
    private let sessionLedger = TuyaAuthenticatedReadOnlySessionLedger()
    private var connectionToken: TuyaReadOnlyConnectionToken?
    private var transportSuccessAtUptime: UInt64?
    private var events: [Event] = []
    private var watchdog: Task<Void, Never>?

    init(device: TuyaAccountBridge.LinkedDevice) {
        deviceID = device.id
        deviceName = device.name
        productID = device.productID
        tuyaUUID = device.uuid
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        log("controller_created")
    }

    deinit { watchdog?.cancel() }

    var sdkCompiled: Bool { OfficialTuyaFactory.compiled }
    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var sdkAccountAuthorized: Bool { OfficialTuyaFactory.accountReady }
    var selected: Candidate? { selectedID.flatMap { byID[$0] } }
    var passed: Bool {
        (phase == .observing || phase == .accepted) &&
        sdkDeviceMembershipAuthorized &&
        sdkLocalBLEOnline &&
        canonicalPreflightReady
    }

    func refreshDeviceMembership() {
        guard sdkCompiled, privateConfig, sdkAccountAuthorized else {
            invalidateDeviceMembership("Authorize the official Tuya SDK account before checking scooter membership.")
            return
        }
        runDeviceMembershipProbe(continueToBLE: false)
    }

    func invalidateDeviceMembership(_ reason: String = "SDK account changed; scooter membership must be verified again.") {
        membershipProbe = nil
        membershipCheckInProgress = false
        sdkDeviceMembershipAuthorized = false
        sdkDeviceMembershipMessage = reason
    }

    func startBaseline() {
        guard central.state == .poweredOn else { fail("Bluetooth is not ready.", "bluetooth_unavailable"); return }
        resetDiscovery()
        phase = .baseline
        message = "Keep the scooter OFF for a few seconds."
        log("baseline_started")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func saveBaseline() {
        guard phase == .baseline else { return }
        central.stopScan()
        baseline = Set(byID.keys)
        phase = .powerOn
        message = "Baseline saved. Turn the scooter ON and keep it stationary."
        log("baseline_saved", ["count": String(baseline.count)])
    }

    func scanAfterPowerOn() {
        guard central.state == .poweredOn else { fail("Bluetooth is not ready.", "bluetooth_unavailable"); return }
        phase = .scanning
        message = "Looking for the prior physical UUID or corroborating FD50 + Tuya company evidence. Name and RSSI remain descriptive only."
        log("power_on_scan_started")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        central.stopScan()
        if selectedID == nil, let first = candidates.first(where: { $0.likely }) { choose(first) }
        if selectedID == nil { message = "No candidate has enough deterministic scooter/Tuya evidence. Re-scan instead of guessing." }
        log("scan_stopped")
    }

    func choose(_ candidate: Candidate) {
        guard candidate.likely else {
            message = "That candidate lacks deterministic target evidence. Name, RSSI, and ranking score alone cannot authorize it."
            return
        }
        central.stopScan()
        selectedID = candidate.id
        phase = .selected
        message = "Scooter target selected. CoreBluetooth discovery is stopped before Tuya's SDK takes connection ownership."
        log("candidate_selected", ["id": candidate.id.uuidString, "score": String(candidate.score), "evidence": candidate.evidence.joined(separator: ",")])
    }

    func authenticate() {
        guard let candidate = selected, candidate.likely else { fail("A strongly correlated scooter candidate is required.", "candidate_not_confident"); return }
        guard !deviceID.isEmpty, !tuyaUUID.isEmpty, !productID.isEmpty else { fail("Tuya device ID, UUID or product ID is missing.", "tuya_identity_incomplete"); return }
        guard sdkCompiled, privateConfig else { fail("Official Tuya SmartLife SDK/security configuration is not provisioned. Do not run the physical test yet.", "sdk_unavailable"); return }
        guard sdkAccountAuthorized else { fail("The official Tuya SDK has no authorized account session. The metadata QR session cannot substitute for SDK login.", "sdk_account_not_authorized"); return }
        guard !membershipCheckInProgress else { return }

        phase = .authenticating
        message = "Re-verifying that this exact scooter belongs to the current Tuya SDK account before BLE authentication…"
        runDeviceMembershipProbe(continueToBLE: true)
    }

    private func runDeviceMembershipProbe(continueToBLE: Bool) {
        membershipCheckInProgress = true
        sdkDeviceMembershipAuthorized = false
        sdkDeviceMembershipMessage = "Enumerating the current SDK account's Tuya homes and exact device membership…"
        let probe = OfficialTuyaMembershipProbe()
        membershipProbe = probe
        probe.verify(expectedDeviceID: deviceID) { [weak self, weak probe] verdict in
            guard let self, let probe, self.membershipProbe === probe else { return }
            self.membershipProbe = nil
            self.membershipCheckInProgress = false
            switch verdict {
            case .authorized:
                self.sdkDeviceMembershipAuthorized = true
                self.sdkDeviceMembershipMessage = "Exact scooter device ID is visible in the current Tuya SDK account's owned/shared home membership."
                self.log("sdk_device_membership_authorized", ["deviceID": self.deviceID])
                if continueToBLE { self.beginCanonicalBLEAuthentication() }
            case let .blocked(reason):
                self.sdkDeviceMembershipAuthorized = false
                self.sdkDeviceMembershipMessage = reason
                self.log("sdk_device_membership_blocked", ["reason": reason])
                if continueToBLE { self.fail("SDK scooter membership is not authorized: \(reason)", "sdk_device_membership_blocked") }
            }
        }
    }

    private func beginCanonicalBLEAuthentication() {
        guard phase == .authenticating,
              sdkDeviceMembershipAuthorized,
              let newDriver = OfficialTuyaFactory.make() else {
            fail("Official Tuya provider is unavailable after scooter-membership verification.", "sdk_provider_unavailable")
            return
        }

        central.stopScan()
        driver = newDriver
        secureSessionEstablished = false
        sdkLocalBLEOnline = false
        transportSuccessAtUptime = nil
        canonicalPreflightReady = false
        canonicalPreflightReason = "Beginning a fresh authenticated connection generation."

        Task { @MainActor [weak self, weak newDriver] in
            guard let self, let newDriver, self.phase == .authenticating else { return }
            do {
                let token = try await self.sessionLedger.beginConnection()
                try await self.sessionLedger.markAuthenticationStarted(for: token)
                self.connectionToken = token
                await self.refreshCanonicalState()
                self.message = "Tuya's SDK is establishing the supported secure BLE session. Nembra sends no DP command."
                self.log("official_connect_requested", [
                    "generation": String(token.diagnosticGeneration),
                    "tuyaDeviceID": self.deviceID,
                    "tuyaUUID": self.tuyaUUID,
                    "productID": self.productID
                ])
                newDriver.connect(
                    deviceID: self.deviceID,
                    uuid: self.tuyaUUID,
                    productID: self.productID,
                    onApplicationUpdate: { [weak self] update in
                        Task { @MainActor in await self?.receivedApplicationUpdate(update, token: token) }
                    },
                    success: { [weak self] in
                        Task { @MainActor in await self?.connectCallbackSucceeded(token: token) }
                    },
                    failure: { [weak self] error in
                        Task { @MainActor in await self?.transportFailed(error, token: token) }
                    }
                )
            } catch {
                self.fail("Could not begin canonical Tuya connection chronology: \(error)", "session_ledger_begin_failed")
            }
        }
    }

    private func connectCallbackSucceeded(token: TuyaReadOnlyConnectionToken) async {
        guard phase == .authenticating, connectionToken == token else {
            log("stale_connect_success_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        secureSessionEstablished = true
        transportSuccessAtUptime = DispatchTime.now().uptimeNanoseconds
        phase = .observing
        message = "Official connect callback returned. Waiting for Tuya to report this same generation locally online before authentication authority begins."
        log("official_connect_success_callback", ["generation": String(token.diagnosticGeneration)])
        await refreshLocalBLEObservation(token: token)
        if phase != .failed { startWatchdog(token: token) }
    }

    private func transportFailed(_ error: String, token: TuyaReadOnlyConnectionToken) async {
        guard connectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        try? await sessionLedger.markAuthenticationFailed(for: token)
        await refreshCanonicalState()
        fail(error, "official_connect_failed")
    }

    private func refreshLocalBLEObservation(token: TuyaReadOnlyConnectionToken) async {
        guard connectionToken == token, let driver else { return }
        let online = driver.isLocallyConnected(uuid: tuyaUUID)

        if online && !sdkLocalBLEOnline {
            do {
                try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                sdkLocalBLEOnline = true
                log("sdk_local_ble_online_observed", ["generation": String(token.diagnosticGeneration)])
                message = "Tuya local BLE is observed online. Canonical authentication chronology starts now; waiting for current-generation application data and the 45-second stability window."
            } catch {
                fail("Canonical authentication transition was rejected: \(error)", "session_ledger_auth_transition_failed")
                return
            }
        } else if online && sdkLocalBLEOnline {
            do {
                try await sessionLedger.observeCurrentConnection(for: token)
            } catch {
                fail("Canonical local-BLE liveness chronology was rejected: \(error)", "session_ledger_observation_failed")
                return
            }
        } else if !online && sdkLocalBLEOnline {
            sdkLocalBLEOnline = false
            try? await sessionLedger.endConnection(for: token)
            canonicalPreflightReady = false
            canonicalPreflightReason = "Tuya local BLE was observed offline before acceptance."
            fail("Tuya local BLE was observed offline before acceptance. Export diagnostics; do not repeat the outdoor ride capture.", "sdk_local_ble_offline_observed")
            return
        }

        await refreshCanonicalState()
    }

    private func receivedApplicationUpdate(_ update: [String: String], token: TuyaReadOnlyConnectionToken) async {
        guard connectionToken == token else {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard phase == .observing || phase == .accepted else {
            log("late_application_update_ignored", ["phase": phase.rawValue, "generation": String(token.diagnosticGeneration)])
            return
        }

        await refreshLocalBLEObservation(token: token)
        guard phase != .failed, sdkLocalBLEOnline else {
            log("application_update_before_local_ble_gate", ["generation": String(token.diagnosticGeneration)])
            return
        }

        guard JSONSerialization.isValidJSONObject(update),
              let payloadWitness = try? JSONSerialization.data(withJSONObject: update, options: [.sortedKeys]),
              !payloadWitness.isEmpty else {
            fail("Tuya delivered an application callback that could not form a non-empty application-level evidence witness.", "application_update_witness_failed")
            return
        }

        do {
            try await sessionLedger.recordApplicationPayload(payloadWitness, for: token)
            log("tuya_application_update", update.merging(["generation": String(token.diagnosticGeneration)]) { current, _ in current })
            await refreshCanonicalState()
            if passed {
                acceptIfReady()
            } else {
                message = "Receiving current-generation scooter application data · \(applicationUpdateCount) update(s). Keep it stationary until the canonical 45-second gate passes."
            }
        } catch {
            fail("Canonical application chronology rejected this callback: \(error)", "session_ledger_payload_rejected")
        }
    }

    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.connectionToken == token, self.secureSessionEstablished, self.phase == .observing || self.phase == .accepted else { return }
                await self.refreshLocalBLEObservation(token: token)
                if self.phase == .failed { return }
                if self.passed {
                    self.acceptIfReady()
                    return
                }

                let now = DispatchTime.now().uptimeNanoseconds
                if !self.sdkLocalBLEOnline,
                   let transport = self.transportSuccessAtUptime,
                   now >= transport,
                   now - transport >= Self.localBLEAcquireTimeoutNanoseconds {
                    try? await self.sessionLedger.markAuthenticationFailed(for: token)
                    await self.refreshCanonicalState()
                    self.fail("Tuya returned a connect callback, but local BLE was never observed online within 15 seconds. Export diagnostics; do not proceed to mapping.", "sdk_local_ble_not_acquired")
                    return
                }

                if let age = self.secureSessionAgeSeconds,
                   age >= 60,
                   self.applicationUpdateCount == 0 {
                    try? await self.sessionLedger.endConnection(for: token)
                    self.canonicalPreflightReady = false
                    self.canonicalPreflightReason = "No current-generation application payload arrived in the stationary observation window."
                    self.fail("Tuya local BLE remained observed online for 60 seconds, but no current-generation application update arrived.", "no_current_generation_application_updates")
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshCanonicalState() async {
        let snapshot = await sessionLedger.currentPreflightSnapshot()
        connectionGeneration = snapshot.connectionGeneration
        applicationUpdateCount = snapshot.applicationPayloadCount
        if let authenticatedAt = snapshot.authenticatedAtUptimeNanoseconds,
           let latest = snapshot.latestObservedUptimeNanoseconds,
           latest >= authenticatedAt {
            secureSessionAgeSeconds = Double(latest - authenticatedAt) / 1_000_000_000
        } else {
            secureSessionAgeSeconds = nil
        }

        switch TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) {
        case .readyForStationaryMapping:
            canonicalPreflightReady = true
            canonicalPreflightReason = "Canonical authenticated-session chronology is ready for the next stationary mapping step."
        case let .blocked(reason):
            canonicalPreflightReady = false
            canonicalPreflightReason = reason
        }
    }

    private func acceptIfReady() {
        guard passed, phase != .accepted else { return }
        phase = .accepted
        message = "Secure scooter link passed. Exact SDK membership is verified and canonical authenticated-session chronology survived beyond 45 seconds with current-generation application data."
        log("acceptance_passed", [
            "generation": String(connectionGeneration),
            "applicationUpdates": String(applicationUpdateCount)
        ])
    }

    func prepareExport() {
        let envelope = Export(
            schemaVersion: 4,
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
            sdkDeviceMembershipAuthorized: sdkDeviceMembershipAuthorized,
            secureSessionEstablished: secureSessionEstablished,
            secureSessionAgeSeconds: secureSessionAgeSeconds,
            sdkLocalBLEOnline: sdkLocalBLEOnline,
            connectionGeneration: connectionGeneration,
            canonicalPreflightVerdict: canonicalPreflightReady ? "readyForStationaryMapping" : canonicalPreflightReason,
            applicationUpdateCount: applicationUpdateCount,
            applicationValueRepresentation: "ThingSmartDeviceDelegate dpsUpdate values projected with String(describing:); application-level SDK data, not byte-exact or raw FD50 transport",
            rawFD50BytesCaptured: false,
            secretsRedacted: true,
            dpCommandsSent: false,
            candidates: candidates,
            events: events
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            exportData = try encoder.encode(envelope)
            exportName = "Nembra-Secure-Link-\(deviceID.prefix(8))-Diagnostics.json"
            message = "Sanitized diagnostics ready. SDK application values remain string projections, not raw FD50 bytes. Verification codes, account tokens, local_key and AppSecret are excluded."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    private func resetDiscovery() {
        central.stopScan()
        watchdog?.cancel()
        watchdog = nil
        membershipProbe = nil
        driver = nil
        if let token = connectionToken {
            Task { [sessionLedger] in try? await sessionLedger.endConnection(for: token) }
        }
        connectionToken = nil
        byID.removeAll()
        candidates.removeAll()
        baseline.removeAll()
        selectedID = nil
        secureSessionEstablished = false
        sdkLocalBLEOnline = false
        transportSuccessAtUptime = nil
        secureSessionAgeSeconds = nil
        connectionGeneration = 0
        canonicalPreflightReady = false
        canonicalPreflightReason = "No current authenticated connection generation."
        applicationUpdateCount = 0
        exportData = nil
    }

    private func fail(_ text: String, _ kind: String) {
        watchdog?.cancel()
        watchdog = nil
        canonicalPreflightReady = false
        phase = .failed
        message = text
        log(kind, ["message": sanitize(text)])
    }

    private func log(_ kind: String, _ details: [String: String] = [:]) {
        events.append(Event(at: Date(), kind: kind, details: details.mapValues(sanitize)))
    }

    private func sanitize(_ text: String) -> String {
        var result = text
        for key in ["NEMBRA_TUYA_APP_KEY", "NEMBRA_TUYA_APP_SECRET"] {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                result = result.replacingOccurrences(of: value, with: "<redacted>")
            }
        }
        return result
    }

    private static func hasTuyaCompanyID(_ data: Data?) -> Bool {
        guard let data, data.count >= 2 else { return false }
        return (UInt16(data[data.startIndex]) | UInt16(data[data.index(after: data.startIndex)]) << 8) == 0x07D0
    }

    private func updateCandidate(_ peripheral: CBPeripheral, advertisement: [String: Any], rssi number: NSNumber) {
        let id = peripheral.identifier
        if phase == .baseline { baseline.insert(id) }
        let old = byID[id]
        let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? old?.name
        let rssi = number.intValue == 127 ? old?.rssi : number.intValue
        let serviceUUIDs = ((advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? [])
            + ((advertisement[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? [])
            + ((advertisement[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID]) ?? [])
        let serviceData = advertisement[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let fd50 = serviceUUIDs.contains(Self.fd50) || serviceData?.keys.contains(Self.fd50) == true || old?.fd50 == true
        let tuyaCompany = Self.hasTuyaCompanyID(advertisement[CBAdvertisementDataManufacturerDataKey] as? Data) || old?.tuyaCompany == true
        let knownID = id == Self.knownPeripheral
        let newAfterPowerOn = (phase == .scanning && !baseline.contains(id)) || old?.newAfterPowerOn == true
        let expectedName = name?.localizedCaseInsensitiveContains("demo") == true || name?.localizedCaseInsensitiveContains("tuya") == true || old?.expectedName == true

        var score = 0
        var evidence: [String] = []
        if knownID { score += 1000; evidence.append("prior physical CoreBluetooth UUID") }
        if fd50 { score += 500; evidence.append("FD50") }
        if tuyaCompany { score += 350; evidence.append("Tuya company 0x07D0") }
        if newAfterPowerOn { score += 180; evidence.append("appeared after power-on") }
        if expectedName { score += 100; evidence.append("name hint (descriptive only)") }
        if let rssi {
            if rssi >= -50 { score += 80; evidence.append("very close RSSI (descriptive only)") }
            else if rssi >= -65 { score += 50; evidence.append("nearby RSSI (descriptive only)") }
            else if rssi >= -80 { score += 20 }
        }

        byID[id] = Candidate(
            id: id,
            name: name,
            rssi: rssi,
            advertisements: (old?.advertisements ?? 0) + 1,
            newAfterPowerOn: newAfterPowerOn,
            fd50: fd50,
            tuyaCompany: tuyaCompany,
            knownID: knownID,
            expectedName: expectedName,
            score: score,
            evidence: evidence
        )
        candidates = byID.values.sorted { $0.score == $1.score ? (($0.rssi ?? -999) > ($1.rssi ?? -999)) : $0.score > $1.score }
    }
}

extension SecureLinkController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) { log("central_state", ["raw": String(central.state.rawValue)]) }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard [.baseline, .scanning].contains(phase) else { return }
        updateCandidate(peripheral, advertisement: advertisementData, rssi: RSSI)
    }
}

@MainActor
private protocol OfficialTuyaDriver: AnyObject {
    func connect(deviceID: String, uuid: String, productID: String, onApplicationUpdate: @escaping ([String: String]) -> Void, success: @escaping () -> Void, failure: @escaping (String) -> Void)
    func isLocallyConnected(uuid: String) -> Bool
}

@MainActor
private enum OfficialTuyaFactory {
    private static var didBootstrap = false

    static var compiled: Bool {
#if canImport(ThingSmartHomeKit)
        true
#else
        false
#endif
    }

    static var configured: Bool {
        compiled && !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_KEY"] ?? "").isEmpty && !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_SECRET"] ?? "").isEmpty
    }

    @discardableResult static func bootstrap() -> Bool {
#if canImport(ThingSmartHomeKit)
        guard configured else { return false }
        if didBootstrap { return true }
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["NEMBRA_TUYA_APP_KEY"], !key.isEmpty,
              let secret = environment["NEMBRA_TUYA_APP_SECRET"], !secret.isEmpty else { return false }
        ThingSmartSDK.sharedInstance()?.start(withAppKey: key, secretKey: secret)
        didBootstrap = true
        return true
#else
        false
#endif
    }

    static var accountReady: Bool {
#if canImport(ThingSmartHomeKit)
        guard bootstrap() else { return false }
        return ThingSmartUser.sharedInstance()?.isLogin == true
#else
        return false
#endif
    }

    static func make() -> OfficialTuyaDriver? {
#if canImport(ThingSmartHomeKit)
        guard bootstrap(), accountReady else { return nil }
        return SmartLifeDriver()
#else
        return nil
#endif
    }
}

@MainActor
private final class OfficialTuyaMembershipProbe {
    typealias Verdict = TuyaSDKAccountDeviceMembershipGate.Verdict
#if canImport(ThingSmartHomeKit)
    private var homeManager: ThingSmartHomeManager?
    private var activeHomes: [ThingSmartHome] = []
#endif

    func verify(expectedDeviceID: String, completion: @escaping (Verdict) -> Void) {
        guard OfficialTuyaFactory.bootstrap(), OfficialTuyaFactory.accountReady else {
            completion(.blocked(reason: "Tuya SDK account session is not logged in."))
            return
        }
#if canImport(ThingSmartHomeKit)
        let manager = ThingSmartHomeManager()
        homeManager = manager
        manager.getHomeList(success: { [weak self] homes in
            Task { @MainActor in
                guard let self else { return }
                self.loadHomes(
                    homes,
                    expectedDeviceID: expectedDeviceID,
                    completion: completion
                )
            }
        }, failure: { error in
            Task { @MainActor in
                let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
                    isLoggedIn: OfficialTuyaFactory.accountReady,
                    homeEnumerationCompleted: false,
                    loadedHomeCount: 0,
                    ownedDeviceIDs: [],
                    sharedDeviceIDs: [],
                    homeLoadFailureCount: 1
                )
                let verdict = TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: expectedDeviceID, snapshot: snapshot)
                _ = error
                completion(verdict)
            }
        })
#else
        completion(.blocked(reason: "Official Tuya SmartLife SDK is not compiled into this build."))
#endif
    }

#if canImport(ThingSmartHomeKit)
    private func loadHomes(_ models: [ThingSmartHomeModel], expectedDeviceID: String, completion: @escaping (Verdict) -> Void) {
        activeHomes.removeAll(keepingCapacity: true)
        guard !models.isEmpty else {
            finishMembership(
                expectedDeviceID: expectedDeviceID,
                loadedHomeCount: 0,
                ownedDeviceIDs: [],
                sharedDeviceIDs: [],
                homeLoadFailureCount: 0,
                completion: completion
            )
            return
        }

        var loadedHomeCount = 0
        var homeLoadFailureCount = 0
        var ownedDeviceIDs = Set<String>()
        var sharedDeviceIDs = Set<String>()

        func load(index: Int) {
            guard index < models.count else {
                finishMembership(
                    expectedDeviceID: expectedDeviceID,
                    loadedHomeCount: loadedHomeCount,
                    ownedDeviceIDs: ownedDeviceIDs,
                    sharedDeviceIDs: sharedDeviceIDs,
                    homeLoadFailureCount: homeLoadFailureCount,
                    completion: completion
                )
                return
            }

            let model = models[index]
            guard let home = ThingSmartHome(homeId: model.homeId) else {
                homeLoadFailureCount += 1
                load(index: index + 1)
                return
            }
            activeHomes.append(home)
            home.getDataWithSuccess({ _ in
                Task { @MainActor in
                    loadedHomeCount += 1
                    for device in home.deviceList ?? [] {
                        if let id = device.devId, !id.isEmpty { ownedDeviceIDs.insert(id) }
                    }
                    for device in home.sharedDeviceList ?? [] {
                        if let id = device.devId, !id.isEmpty { sharedDeviceIDs.insert(id) }
                    }
                    load(index: index + 1)
                }
            }, failure: { _ in
                Task { @MainActor in
                    homeLoadFailureCount += 1
                    load(index: index + 1)
                }
            })
        }

        load(index: 0)
    }

    private func finishMembership(
        expectedDeviceID: String,
        loadedHomeCount: Int,
        ownedDeviceIDs: Set<String>,
        sharedDeviceIDs: Set<String>,
        homeLoadFailureCount: Int,
        completion: @escaping (Verdict) -> Void
    ) {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: OfficialTuyaFactory.accountReady,
            homeEnumerationCompleted: true,
            loadedHomeCount: loadedHomeCount,
            ownedDeviceIDs: ownedDeviceIDs,
            sharedDeviceIDs: sharedDeviceIDs,
            homeLoadFailureCount: homeLoadFailureCount
        )
        completion(TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: expectedDeviceID, snapshot: snapshot))
    }
#endif
}

#if canImport(ThingSmartHomeKit)
@MainActor
private final class SmartLifeDriver: NSObject, OfficialTuyaDriver, ThingSmartDeviceDelegate {
    private var device: ThingSmartDevice?
    private var onApplicationUpdate: (([String: String]) -> Void)?

    func connect(deviceID: String, uuid: String, productID: String, onApplicationUpdate: @escaping ([String: String]) -> Void, success: @escaping () -> Void, failure: @escaping (String) -> Void) {
        guard OfficialTuyaFactory.bootstrap() else { failure("Private Tuya SDK credentials are missing."); return }
        self.onApplicationUpdate = onApplicationUpdate
        device = ThingSmartDevice(deviceId: deviceID)
        device?.delegate = self
        ThingSmartBLEManager.sharedInstance().connectBLE(
            withUUID: uuid,
            productKey: productID,
            success: success,
            failure: { failure("Tuya SmartLife SDK did not establish the BLE session.") }
        )
    }

    func isLocallyConnected(uuid: String) -> Bool {
        ThingSmartBLEManager.sharedInstance().deviceStatue(withUUID: uuid)
    }

    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps { sanitized[String(describing: key)] = String(describing: value) }
        onApplicationUpdate?(sanitized)
    }
}
#endif

@MainActor
private final class OfficialTuyaAccountAuthorizer: ObservableObject {
    enum LoginMethod: String, CaseIterable, Identifiable {
        case email = "Email"
        case phone = "Phone"
        var id: String { rawValue }
    }

    @Published var method: LoginMethod = .email
    @Published var countryCode = "1"
    @Published var account = ""
    @Published var verificationCode = ""
    @Published private(set) var status = "Initialize the official Tuya SDK to authorize this Capture build."
    @Published private(set) var codeSent = false
    @Published private(set) var busy = false
    @Published private(set) var authorized = false

    func bootstrap() {
        guard OfficialTuyaFactory.compiled else { status = "Official Tuya SmartLife SDK is not compiled into this build."; authorized = false; return }
        guard OfficialTuyaFactory.configured else { status = "Private Tuya AppKey/AppSecret are not provisioned for this build."; authorized = false; return }
        guard OfficialTuyaFactory.bootstrap() else { status = "Tuya SDK initialization failed closed."; authorized = false; return }
        authorized = OfficialTuyaFactory.accountReady
        status = authorized ? "Official Tuya SDK account session is authorized." : "SDK initialized. Sign in with a verification code; the metadata QR session does not count as BLE authentication authority."
    }

    func sendCode() {
        bootstrap()
        guard !authorized else { return }
        let identity = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty, !country.isEmpty else { status = "Enter the Tuya account and country code first."; return }
#if canImport(ThingSmartHomeKit)
        busy = true
        codeSent = false
        status = "Requesting a Tuya login verification code…"
        let user = ThingSmartUser.sharedInstance()
        switch method {
        case .email:
            user?.sendVerifyCode(
                withUserName: identity,
                countryCode: country,
                type: 2,
                success: { [weak self] in Task { @MainActor in self?.busy = false; self?.codeSent = true; self?.status = "Verification code sent by Tuya. Enter it below to authorize the SDK session." } },
                failure: { [weak self] error in Task { @MainActor in self?.busy = false; self?.status = "Tuya could not send the verification code: \(error?.localizedDescription ?? "unknown error")" } }
            )
        case .phone:
            let region = user?.getDefaultRegionWithCountryCode(country) ?? ""
            user?.sendVerifyCode(
                withUserName: identity,
                region: region,
                countryCode: country,
                type: 2,
                success: { [weak self] in Task { @MainActor in self?.busy = false; self?.codeSent = true; self?.status = "Verification code sent by Tuya. Enter it below to authorize the SDK session." } },
                failure: { [weak self] error in Task { @MainActor in self?.busy = false; self?.status = "Tuya could not send the verification code: \(error?.localizedDescription ?? "unknown error")" } }
            )
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    func login() {
        bootstrap()
        guard !authorized else { return }
        let identity = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty, !country.isEmpty, !code.isEmpty else { status = "Enter the account, country code, and Tuya verification code."; return }
#if canImport(ThingSmartHomeKit)
        busy = true
        status = "Authorizing the official Tuya SDK account session…"
        switch method {
        case .email:
            ThingSmartUser.sharedInstance()?.login(
                withEmail: identity,
                countryCode: country,
                code: code,
                success: { [weak self] in Task { @MainActor in self?.finishLoginSuccess() } },
                failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error) } }
            )
        case .phone:
            ThingSmartUser.sharedInstance()?.login(
                withMobile: identity,
                countryCode: country,
                code: code,
                success: { [weak self] in Task { @MainActor in self?.finishLoginSuccess() } },
                failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error) } }
            )
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    private func finishLoginSuccess() {
        busy = false
        verificationCode = ""
        authorized = true
        status = "Official Tuya SDK account authorized. Verify exact scooter membership next."
    }

    private func finishLoginFailure(_ error: Error?) {
        busy = false
        verificationCode = ""
        authorized = false
        status = "Tuya SDK login failed: \(error?.localizedDescription ?? "unknown error")"
    }
}

@MainActor
private struct SecureLinkView: View {
    @StateObject private var test: SecureLinkController
    @StateObject private var sdkAccount: OfficialTuyaAccountAuthorizer

    init(device: TuyaAccountBridge.LinkedDevice) {
        _test = StateObject(wrappedValue: SecureLinkController(device: device))
        _sdkAccount = StateObject(wrappedValue: OfficialTuyaAccountAuthorizer())
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SMALLEST INDOOR TEST").font(.caption.monospaced().bold()).foregroundStyle(.green)
                    Text("Authenticate. Wait. Capture.").font(.largeTitle.bold())
                    Text("Keep the scooter stationary. Do not run the old 17-step sequence.").foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(test.passed ? "Secure scooter link established" : test.phase == .failed ? "Secure-link test stopped" : "Authentication preflight").font(.headline)
                            Spacer()
                            Text("G\(test.connectionGeneration) · \(test.applicationUpdateCount)").monospacedDigit()
                        }
                        Text(test.message).font(.footnote).foregroundStyle(.secondary)
                        if let age = test.secureSessionAgeSeconds {
                            LabeledContent("Canonical authenticated age", value: String(format: "%.1f s", age))
                            ProgressView(value: min(age / 45, 1))
                        }
                        LabeledContent("Tuya local BLE", value: test.sdkLocalBLEOnline ? "Observed online" : "Not proven")
                        LabeledContent("Current-generation app updates", value: String(test.applicationUpdateCount))
                        Text(test.canonicalPreflightReason).font(.caption).foregroundStyle(.secondary)
                    }.card()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Official Tuya authority", systemImage: "checkmark.shield").font(.headline)
                        LabeledContent("SDK compiled in", value: test.sdkCompiled ? "Yes" : "No")
                        LabeledContent("Private app config", value: test.privateConfig ? "Yes" : "No")
                        LabeledContent("SDK account authorized", value: test.sdkAccountAuthorized ? "Yes" : "No")
                        LabeledContent("Exact scooter membership", value: test.sdkDeviceMembershipAuthorized ? "Verified" : "Not verified")
                        Text(test.sdkDeviceMembershipMessage).font(.footnote).foregroundStyle(.secondary)
                        if test.sdkCompiled && test.privateConfig && test.sdkAccountAuthorized && !test.sdkDeviceMembershipAuthorized {
                            Button(test.membershipCheckInProgress ? "Checking Tuya homes…" : "Verify scooter membership") { test.refreshDeviceMembership() }
                                .buttonStyle(.bordered)
                                .disabled(test.membershipCheckInProgress)
                        }
                        if !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized || !test.sdkDeviceMembershipAuthorized {
                            Text("NO PHYSICAL TEST YET: official SDK/security provisioning, an authorized SDK account, and exact selected-scooter membership must all be proven before BLE authentication.").font(.footnote.bold()).foregroundStyle(.orange)
                        }
                    }.card()

                    if test.sdkCompiled && test.privateConfig && !test.sdkAccountAuthorized { sdkAuthorizationCard }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Find the known scooter", systemImage: "scope").font(.headline)
                        switch test.phase {
                        case .idle, .failed:
                            Button("Start scooter-OFF baseline") { test.startBaseline() }.buttonStyle(.borderedProminent)
                        case .baseline:
                            Button("Save OFF baseline") { test.saveBaseline() }.buttonStyle(.borderedProminent)
                        case .powerOn:
                            Text("Turn scooter ON, keep it still.").foregroundStyle(.secondary)
                            Button("Scan after power-on") { test.scanAfterPowerOn() }.buttonStyle(.borderedProminent)
                        case .scanning:
                            Button("Stop scan / use strongest deterministic match") { test.stopScan() }.buttonStyle(.bordered)
                        default:
                            EmptyView()
                        }

                        ForEach(test.candidates.prefix(8)) { candidate in
                            Button { test.choose(candidate) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(candidate.title).bold()
                                        if candidate.likely {
                                            Text("STRONG MATCH").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.green, in: Capsule()).foregroundStyle(.black)
                                        }
                                        Spacer()
                                        Text("\(candidate.score)").monospacedDigit()
                                    }
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
                            Button("Start secure read-only test") { test.authenticate() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!candidate.likely || !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized || !test.sdkDeviceMembershipAuthorized || test.membershipCheckInProgress || [.authenticating, .observing, .accepted].contains(test.phase))
                        }.card()
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Acceptance", systemImage: test.passed ? "checkmark.seal.fill" : "hourglass").font(.headline).foregroundStyle(test.passed ? .green : .white)
                        Text("Pass requires exact SDK-account membership plus the canonical Tuya session ledger/preflight: current-generation SmartLife SDK authentication, at least one genuine post-auth application update, and at least 45 seconds of monotonic authenticated chronology advanced only while Tuya reports local BLE online. This remains application-level SDK evidence, not raw FD50 bytes or DP meaning.").font(.footnote).foregroundStyle(.secondary)
                        if test.passed {
                            Text("SECURE LINK ACCEPTED\nREADY FOR THE NEXT SMALLEST STATIONARY MAPPING STEP").font(.caption.monospaced().bold()).foregroundStyle(.green)
                        }
                    }.card()

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Prepare sanitized diagnostic JSON") { test.prepareExport() }.buttonStyle(.bordered)
                        if let data = test.exportData {
                            ShareLink(item: SecureTransfer(data: data, name: test.exportName), preview: SharePreview(test.exportName)) {
                                Label("Share diagnostic JSON", systemImage: "square.and.arrow.up")
                            }.buttonStyle(.borderedProminent)
                        }
                        Text("Export includes deterministic target evidence, exact SDK membership verdict, canonical connection generation/chronology state, failures, and opaque application-update values as a string projection. It explicitly does not claim raw FD50 bytes and excludes passwords, verification codes, account tokens, local_key and AppSecret.").font(.footnote).foregroundStyle(.secondary)
                    }.card()
                }
                .frame(maxWidth: 760)
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
        }
        .navigationTitle("Secure Link")
        .task {
            sdkAccount.bootstrap()
            if sdkAccount.authorized { test.refreshDeviceMembership() }
        }
        .onChange(of: sdkAccount.authorized) { _, authorized in
            if authorized { test.refreshDeviceMembership() }
            else { test.invalidateDeviceMembership() }
        }
    }

    private var sdkAuthorizationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Authorize the official SDK session", systemImage: "person.crop.circle.badge.checkmark").font(.headline)
            Text(sdkAccount.status).font(.footnote).foregroundStyle(.secondary)
            Picker("Login method", selection: $sdkAccount.method) {
                ForEach(OfficialTuyaAccountAuthorizer.LoginMethod.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            TextField("Country code (for example 1)", text: $sdkAccount.countryCode)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            TextField(sdkAccount.method == .email ? "Tuya account email" : "Tuya account phone number", text: $sdkAccount.account)
                .keyboardType(sdkAccount.method == .email ? .emailAddress : .phonePad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .padding(10)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            Button(sdkAccount.busy ? "Contacting Tuya…" : "Send login code") { sdkAccount.sendCode() }
                .buttonStyle(.bordered)
                .disabled(sdkAccount.busy)
            if sdkAccount.codeSent {
                SecureField("Verification code", text: $sdkAccount.verificationCode)
                    .keyboardType(.numberPad)
                    .privacySensitive()
                    .padding(10)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                Button("Authorize SDK account") { sdkAccount.login() }
                    .buttonStyle(.borderedProminent)
                    .disabled(sdkAccount.busy || sdkAccount.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Nembra does not ask for or persist the Tuya account password here. Verification codes stay in memory and are cleared after the login attempt.").font(.caption).foregroundStyle(.secondary)
        }.card()
    }
}

private struct SecureTransfer: Transferable {
    let data: Data
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }.suggestedFileName { $0.name }
    }
}

private extension View {
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}
