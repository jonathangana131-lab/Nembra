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
                    Text("P0 · TUYA AUTHENTICATION")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.green)
                    Text("Prove the secure scooter link first.")
                        .font(.largeTitle.bold())
                    Text("The next physical run is stationary. It proves supported Tuya authentication, exact scooter account membership, at least 45 seconds of continuous local BLE observation, and genuine application updates through Tuya's own SDK. The old 17-step ride sequence stays disabled until this passes.")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Read-only control boundary", systemImage: "shield.checkered")
                            .font(.headline)
                        Text("Account linking is used for ownership/device identity. Nembra does not turn local_key into a BLE login key, synthesize Tuya authentication frames, or open a second CoreBluetooth connection after the official SDK takes ownership.")
                            .foregroundStyle(.secondary)
                        Text("No unbind, reset, lock, speed, light, mode, throttle, brake, firmware, or other DP command is sent.")
                            .font(.footnote.bold())
                            .foregroundStyle(.green)
                    }
                    .card()
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
            Label("1 · Identify your bound Tuya device", systemImage: "person.badge.key")
                .font(.headline)
            Text(tuya.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
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
            if let data = tuya.qrPNGData,
               let image = UIImage(data: data),
               !tuya.isLinked {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 230)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                Button("I approved it · check now") { tuya.checkApprovalNow() }
                    .buttonStyle(.bordered)
            }
            if tuya.phase == .failed {
                Button("Reset account link") { tuya.resetLink() }
                    .buttonStyle(.bordered)
            }
        }
        .card()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2 · Choose the scooter", systemImage: "bicycle")
                .font(.headline)
            if tuya.devices.isEmpty {
                Button("Refresh Tuya devices") { tuya.refreshDevices() }
                    .buttonStyle(.bordered)
            }
            ForEach(tuya.devices) { device in
                VStack(alignment: .leading, spacing: 7) {
                    Text(device.name.isEmpty ? "Unnamed Tuya device" : device.name)
                        .font(.headline)
                    Text([device.productName, device.category].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(tuya.selectedDeviceID == device.id ? "Refresh metadata" : "Use this device") {
                            tuya.selectDevice(device)
                        }
                        .buttonStyle(.bordered)
                        if tuya.selectedDeviceID == device.id,
                           tuya.phase == .ready,
                           !device.productID.isEmpty,
                           !device.uuid.isEmpty {
                            NavigationLink("Secure link test") { SecureLinkView(device: device) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(12)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Only Tuya device ID, device UUID and product ID enter the supported secure-link controller. local_key does not.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
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

    enum Phase: String, Codable {
        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed
    }

    struct Event: Codable {
        let at: Date
        let kind: String
        let details: [String: String]
    }

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
        let sdkAccountLoggedIn: Bool
        let sdkDeviceMembershipVerified: Bool
        let secureSessionEstablished: Bool
        let secureSessionAgeSeconds: Double?
        let sdkLocalBLEOnline: Bool
        let applicationUpdateCount: Int
        let connectionGeneration: UInt64
        let authenticationMethod: String?
        let preflightVerdict: String
        let applicationValueRepresentation: String
        let rawFD50BytesCaptured: Bool
        let secretsRedacted: Bool
        let dpCommandsSent: Bool
        let candidates: [Candidate]
        let events: [Event]
    }

    static let knownPeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    static let fd50 = CBUUID(string: "FD50")
    static let maximumObservationPollGapNanoseconds: UInt64 = 5_000_000_000

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Start with the scooter OFF. This test only identifies it and proves Tuya's supported secure session."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var sdkLocalBLEOnline = false
    @Published private(set) var sdkDeviceMembershipVerified = false
    @Published private(set) var membershipStatus = "Exact scooter membership has not been checked in the official SDK account yet."
    @Published private(set) var membershipBusy = false
    @Published private(set) var ledgerSnapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
        authenticationState: .unavailable(reason: "No active Bluetooth connection."),
        connectionStartedAtUptimeNanoseconds: nil,
        authenticatedAtUptimeNanoseconds: nil,
        latestObservedUptimeNanoseconds: nil,
        applicationPayloadCount: 0,
        connectionGeneration: 0
    )
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
    private var events: [Event] = []
    private var watchdog: Task<Void, Never>?
    private let sessionLedger = TuyaAuthenticatedReadOnlySessionLedger()
    private var currentConnectionToken: TuyaReadOnlyConnectionToken?
    private var lastObservationPollUptimeNanoseconds: UInt64?
#if canImport(ThingSmartHomeKit)
    private var membershipProbe: OfficialTuyaMembershipProbe?
#endif
    private var membershipRequestID = UUID()

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
    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }
    var selected: Candidate? { selectedID.flatMap { byID[$0] } }
    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }
    var secureSessionEstablished: Bool {
        if case .authenticated = ledgerSnapshot.authenticationState { return true }
        return false
    }
    var secureSessionAgeSeconds: Double? {
        guard let start = ledgerSnapshot.authenticatedAtUptimeNanoseconds,
              let latest = ledgerSnapshot.latestObservedUptimeNanoseconds,
              latest >= start else { return nil }
        return Double(latest - start) / 1_000_000_000
    }
    var preflightVerdict: TuyaAuthenticatedReadOnlyPreflight.Verdict {
        TuyaAuthenticatedReadOnlyPreflight.verdict(for: ledgerSnapshot)
    }
    var preflightVerdictText: String {
        switch preflightVerdict {
        case .readyForStationaryMapping:
            return "ready-for-stationary-mapping"
        case let .blocked(reason):
            return "blocked: \(reason)"
        }
    }
    var passed: Bool {
        guard sdkDeviceMembershipVerified, sdkLocalBLEOnline else { return false }
        guard phase == .observing || phase == .accepted else { return false }
        if case .readyForStationaryMapping = preflightVerdict { return true }
        return false
    }

    func startBaseline() {
        guard central.state == .poweredOn else {
            fail("Bluetooth is not ready.", "bluetooth_unavailable")
            return
        }
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
        guard central.state == .poweredOn else {
            fail("Bluetooth is not ready.", "bluetooth_unavailable")
            return
        }
        phase = .scanning
        message = "Ranking the OFF→ON delta against the previously observed CoreBluetooth identity and Tuya/FD50 evidence. Name and RSSI are descriptive only."
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
            message = "Candidate lacks deterministic target evidence. Name, RSSI, and ranking score alone cannot authorize it."
            return
        }
        central.stopScan()
        selectedID = candidate.id
        phase = .selected
        message = "Scooter target selected from deterministic evidence. CoreBluetooth discovery is stopped before Tuya's SDK takes connection ownership."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "score": String(candidate.score),
            "evidence": candidate.evidence.joined(separator: ",")
        ])
    }

    func invalidateSDKMembership() {
        membershipRequestID = UUID()
        membershipBusy = false
        sdkDeviceMembershipVerified = false
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        log("sdk_membership_invalidated")
    }

    func verifySDKMembership(completion: ((Bool) -> Void)? = nil) {
        guard sdkCompiled, privateConfig else {
            sdkDeviceMembershipVerified = false
            membershipStatus = "Official Tuya SmartLife SDK/security configuration is not provisioned."
            completion?(false)
            return
        }
        guard sdkAccountLoggedIn else {
            sdkDeviceMembershipVerified = false
            membershipStatus = "The official Tuya SDK account is not logged in."
            completion?(false)
            return
        }
        let expected = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty else {
            sdkDeviceMembershipVerified = false
            membershipStatus = "Expected Tuya scooter device ID is unavailable."
            completion?(false)
            return
        }
#if canImport(ThingSmartHomeKit)
        let requestID = UUID()
        membershipRequestID = requestID
        membershipBusy = true
        sdkDeviceMembershipVerified = false
        membershipStatus = "Checking the logged-in SDK account's homes for the exact scooter device ID…"
        let probe = OfficialTuyaMembershipProbe(expectedDeviceID: expected) { [weak self] result in
            Task { @MainActor in
                guard let self, self.membershipRequestID == requestID else { return }
                self.membershipBusy = false
                self.membershipProbe = nil
                switch result.verdict {
                case .authorized:
                    self.sdkDeviceMembershipVerified = true
                    self.membershipStatus = "Exact scooter membership verified in the official Tuya SDK account."
                    self.log("sdk_device_membership_verified", [
                        "loadedHomes": String(result.loadedHomeCount),
                        "ownedDevices": String(result.ownedDeviceCount),
                        "sharedDevices": String(result.sharedDeviceCount)
                    ])
                    completion?(true)
                case let .blocked(reason):
                    self.sdkDeviceMembershipVerified = false
                    self.membershipStatus = reason
                    self.log("sdk_device_membership_blocked", [
                        "reason": reason,
                        "loadedHomes": String(result.loadedHomeCount),
                        "failedHomes": String(result.homeLoadFailureCount)
                    ])
                    completion?(false)
                }
            }
        }
        membershipProbe = probe
        probe.start()
#else
        sdkDeviceMembershipVerified = false
        membershipStatus = "Official Tuya SmartLife SDK is not compiled into this build."
        completion?(false)
#endif
    }

    func authenticate() {
        guard let candidate = selected, candidate.likely else {
            fail("A strongly matched scooter candidate is required.", "candidate_not_confident")
            return
        }
        guard !deviceID.isEmpty, !tuyaUUID.isEmpty, !productID.isEmpty else {
            fail("Tuya device ID, UUID or product ID is missing.", "tuya_identity_incomplete")
            return
        }
        guard sdkCompiled, privateConfig else {
            fail("Official Tuya SmartLife SDK/security configuration is not provisioned. Do not run the physical test yet.", "sdk_unavailable")
            return
        }
        guard sdkAccountLoggedIn else {
            fail("The official Tuya SDK has no logged-in account session. The metadata QR session cannot substitute for SDK login.", "sdk_account_not_logged_in")
            return
        }
        guard sdkDeviceMembershipVerified else {
            fail("The logged-in Tuya SDK account has not proven exact membership of this scooter. Verify scooter membership before BLE authentication.", "sdk_device_membership_not_verified")
            return
        }

        verifySDKMembership { [weak self] stillAuthorized in
            guard let self else { return }
            guard stillAuthorized else {
                self.fail("Exact scooter membership could not be re-verified. Do not start the physical test.", "sdk_device_membership_recheck_failed")
                return
            }
            self.beginOfficialConnection(candidate: candidate)
        }
    }

    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected || phase == .failed else { return }
        guard sdkDeviceMembershipVerified, sdkAccountLoggedIn else {
            fail("Tuya account/device authority changed before connection start.", "sdk_authority_changed")
            return
        }
        guard let newDriver = OfficialTuyaFactory.make() else {
            fail("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

        central.stopScan()
        driver = newDriver
        watchdog?.cancel()
        watchdog = nil
        sdkLocalBLEOnline = false
        lastObservationPollUptimeNanoseconds = nil
        phase = .authenticating
        message = "Tuya's SDK is establishing the supported secure BLE session. Nembra sends no DP command."

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = try await self.sessionLedger.beginConnection()
                try await self.sessionLedger.markAuthenticationStarted(for: token)
                self.currentConnectionToken = token
                await self.refreshLedgerSnapshot()
                self.log("official_connect_requested", [
                    "generation": String(token.diagnosticGeneration),
                    "coreBluetoothID": candidate.id.uuidString,
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
                        Task { @MainActor in await self?.authenticated(token: token) }
                    },
                    failure: { [weak self] in
                        Task { @MainActor in await self?.authenticationFailed(token: token) }
                    }
                )
            } catch {
                self.fail("Could not create a fresh authenticated-session generation: \(error.localizedDescription)", "session_generation_failed")
            }
        }
    }

    private func authenticated(token: TuyaReadOnlyConnectionToken) async {
        guard phase == .authenticating,
              currentConnectionToken == token,
              let driver else { return }
        let localOnline = driver.isLocallyConnected(uuid: tuyaUUID)
        guard localOnline else {
            try? await sessionLedger.markAuthenticationFailed(for: token)
            await refreshLedgerSnapshot()
            fail("Tuya reported connection success without proving the scooter locally BLE-connected. Stop and export diagnostics.", "sdk_local_ble_not_online_at_auth")
            return
        }
        do {
            try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
            sdkLocalBLEOnline = true
            lastObservationPollUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
            await refreshLedgerSnapshot()
            phase = .observing
            message = "Secure Tuya session established for generation \(token.diagnosticGeneration). Waiting for genuine application updates while the SDK remains the only BLE owner…"
            log("official_session_ready", [
                "generation": String(token.diagnosticGeneration),
                "localBLEOnline": "true"
            ])
            startWatchdog(token: token)
        } catch {
            fail("Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)", "session_auth_callback_rejected")
        }
    }

    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        try? await sessionLedger.markAuthenticationFailed(for: token)
        await refreshLedgerSnapshot()
        fail("Tuya SmartLife SDK did not establish the BLE session.", "official_connect_failed")
    }

    private func receivedApplicationUpdate(_ update: [String: String], token: TuyaReadOnlyConnectionToken) async {
        guard !update.isEmpty else { return }
        guard phase == .observing || phase == .accepted else {
            log("application_update_outside_observation_ignored", [
                "generation": String(token.diagnosticGeneration),
                "phase": phase.rawValue
            ])
            return
        }
        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: true, for: token)
            await refreshLedgerSnapshot()
            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
            if passed {
                phase = .accepted
                message = "Secure scooter link passed. Exact SDK membership, same-generation application data, and at least 45 seconds of observed local BLE continuity are all proven."
            } else {
                message = "Receiving same-generation scooter application data · \(applicationUpdateCount) update(s). Keep it stationary until the canonical 45-second gate passes."
            }
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch {
            fail("Application evidence was rejected by authenticated-session chronology: \(error.localizedDescription)", "application_update_rejected")
        }
    }

    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self,
                      self.currentConnectionToken == token,
                      self.secureSessionEstablished,
                      let driver = self.driver else { return }

                let pollNow = DispatchTime.now().uptimeNanoseconds
                if let priorPoll = self.lastObservationPollUptimeNanoseconds {
                    guard pollNow >= priorPoll else {
                        try? await self.sessionLedger.endConnection(for: token)
                        await self.refreshLedgerSnapshot()
                        self.currentConnectionToken = nil
                        self.lastObservationPollUptimeNanoseconds = nil
                        self.fail("Monotonic observation time regressed. The authenticated continuity window is invalid.", "observation_continuity_clock_regressed")
                        return
                    }
                    if pollNow - priorPoll > Self.maximumObservationPollGapNanoseconds {
                        try? await self.sessionLedger.endConnection(for: token)
                        await self.refreshLedgerSnapshot()
                        self.currentConnectionToken = nil
                        self.lastObservationPollUptimeNanoseconds = nil
                        self.fail("The app could not observe local BLE continuously enough to trust the 45-second window. Keep Nembra Capture foreground and retry this stationary test.", "observation_continuity_gap")
                        return
                    }
                }
                self.lastObservationPollUptimeNanoseconds = pollNow

                let locallyOnline = driver.isLocallyConnected(uuid: self.tuyaUUID)
                self.sdkLocalBLEOnline = locallyOnline
                if !locallyOnline {
                    try? await self.sessionLedger.endConnection(for: token)
                    await self.refreshLedgerSnapshot()
                    self.currentConnectionToken = nil
                    self.lastObservationPollUptimeNanoseconds = nil
                    self.fail("Tuya's local BLE session dropped before acceptance. Export diagnostics; do not repeat the outdoor ride capture.", "sdk_local_ble_dropped")
                    return
                }

                do {
                    try await self.sessionLedger.observeCurrentConnection(for: token)
                    await self.refreshLedgerSnapshot()
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
                    self.log("stale_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    self.fail("Authenticated-session liveness chronology failed closed: \(error.localizedDescription)", "session_liveness_rejected")
                    return
                }

                if self.passed {
                    self.phase = .accepted
                    self.message = "Secure scooter link passed. Exact membership, genuine same-generation application data, and at least 45 seconds of observed local BLE continuity are proven."
                    self.log("acceptance_passed", [
                        "generation": String(token.diagnosticGeneration),
                        "applicationUpdates": String(self.applicationUpdateCount)
                    ])
                    return
                }

                if (self.secureSessionAgeSeconds ?? 0) > 60,
                   self.applicationUpdateCount == 0 {
                    self.fail("The secure session survived, but Tuya delivered no same-generation application update within 60 seconds.", "no_application_updates")
                    return
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshLedgerSnapshot() async {
        ledgerSnapshot = await sessionLedger.currentPreflightSnapshot()
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
            sdkAccountLoggedIn: sdkAccountLoggedIn,
            sdkDeviceMembershipVerified: sdkDeviceMembershipVerified,
            secureSessionEstablished: secureSessionEstablished,
            secureSessionAgeSeconds: secureSessionAgeSeconds,
            sdkLocalBLEOnline: sdkLocalBLEOnline,
            applicationUpdateCount: applicationUpdateCount,
            connectionGeneration: ledgerSnapshot.connectionGeneration,
            authenticationMethod: ledgerSnapshot.authenticationMethod?.rawValue,
            preflightVerdict: preflightVerdictText,
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
            message = "Sanitized diagnostics ready. The export includes exact membership and canonical connection-generation authority. SDK application values are string projections, not raw FD50 bytes. Passwords, account tokens, local_key and AppSecret are excluded."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    private func resetDiscovery() {
        central.stopScan()
        watchdog?.cancel()
        watchdog = nil
        driver = nil
        byID.removeAll()
        candidates.removeAll()
        baseline.removeAll()
        selectedID = nil
        sdkLocalBLEOnline = false
        lastObservationPollUptimeNanoseconds = nil
        exportData = nil
        if let token = currentConnectionToken {
            currentConnectionToken = nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await self.sessionLedger.endConnection(for: token)
                await self.refreshLedgerSnapshot()
            }
        }
    }

    private func fail(_ text: String, _ kind: String) {
        watchdog?.cancel()
        watchdog = nil
        lastObservationPollUptimeNanoseconds = nil
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
        candidates = byID.values.sorted {
            $0.score == $1.score ? (($0.rssi ?? -999) > ($1.rssi ?? -999)) : $0.score > $1.score
        }
    }
}

extension SecureLinkController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("central_state", ["raw": String(central.state.rawValue)])
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard [.baseline, .scanning].contains(phase) else { return }
        updateCandidate(peripheral, advertisement: advertisementData, rssi: RSSI)
    }
}

@MainActor
private protocol OfficialTuyaDriver: AnyObject {
    func connect(
        deviceID: String,
        uuid: String,
        productID: String,
        onApplicationUpdate: @escaping ([String: String]) -> Void,
        success: @escaping () -> Void,
        failure: @escaping () -> Void
    )
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
        compiled
            && !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_KEY"] ?? "").isEmpty
            && !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_SECRET"] ?? "").isEmpty
    }

    @discardableResult
    static func bootstrap() -> Bool {
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

    static var accountLoggedIn: Bool {
#if canImport(ThingSmartHomeKit)
        guard bootstrap() else { return false }
        return ThingSmartUser.sharedInstance()?.isLogin == true
#else
        return false
#endif
    }

    static func make() -> OfficialTuyaDriver? {
#if canImport(ThingSmartHomeKit)
        guard bootstrap(), accountLoggedIn else { return nil }
        return SmartLifeDriver()
#else
        return nil
#endif
    }
}

#if canImport(ThingSmartHomeKit)
@MainActor
private final class OfficialTuyaMembershipProbe {
    struct Result {
        let verdict: TuyaSDKAccountDeviceMembershipGate.Verdict
        let loadedHomeCount: Int
        let ownedDeviceCount: Int
        let sharedDeviceCount: Int
        let homeLoadFailureCount: Int
    }

    private let expectedDeviceID: String
    private let completion: (Result) -> Void
    private let homeManager = ThingSmartHomeManager()
    private var homes: [ThingSmartHomeModel] = []
    private var index = 0
    private var loadedHomeCount = 0
    private var homeLoadFailureCount = 0
    private var ownedDeviceIDs = Set<String>()
    private var sharedDeviceIDs = Set<String>()
    private var activeHome: ThingSmartHome?

    init(expectedDeviceID: String, completion: @escaping (Result) -> Void) {
        self.expectedDeviceID = expectedDeviceID
        self.completion = completion
    }

    func start() {
        guard OfficialTuyaFactory.bootstrap(), OfficialTuyaFactory.accountLoggedIn else {
            finish(enumerationCompleted: false)
            return
        }
        homeManager.getHomeList(success: { [weak self] homes in
            Task { @MainActor in
                guard let self else { return }
                self.homes = homes ?? []
                self.loadNextHome()
            }
        }, failure: { [weak self] _ in
            Task { @MainActor in self?.finish(enumerationCompleted: false) }
        })
    }

    private func loadNextHome() {
        guard index < homes.count else {
            finish(enumerationCompleted: true)
            return
        }
        let model = homes[index]
        index += 1
        guard let home = ThingSmartHome(homeId: model.homeId) else {
            homeLoadFailureCount += 1
            loadNextHome()
            return
        }
        activeHome = home
        home.getDataWithSuccess({ [weak self, weak home] _ in
            Task { @MainActor in
                guard let self, let home else { return }
                self.loadedHomeCount += 1
                for device in home.deviceList ?? [] {
                    if let id = device.devId, !id.isEmpty { self.ownedDeviceIDs.insert(id) }
                }
                for device in home.sharedDeviceList ?? [] {
                    if let id = device.devId, !id.isEmpty { self.sharedDeviceIDs.insert(id) }
                }
                self.activeHome = nil
                self.loadNextHome()
            }
        }, failure: { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.homeLoadFailureCount += 1
                self.activeHome = nil
                self.loadNextHome()
            }
        })
    }

    private func finish(enumerationCompleted: Bool) {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: OfficialTuyaFactory.accountLoggedIn,
            homeEnumerationCompleted: enumerationCompleted,
            loadedHomeCount: loadedHomeCount,
            ownedDeviceIDs: ownedDeviceIDs,
            sharedDeviceIDs: sharedDeviceIDs,
            homeLoadFailureCount: homeLoadFailureCount
        )
        completion(Result(
            verdict: TuyaSDKAccountDeviceMembershipGate.verdict(
                expectedDeviceID: expectedDeviceID,
                snapshot: snapshot
            ),
            loadedHomeCount: loadedHomeCount,
            ownedDeviceCount: ownedDeviceIDs.count,
            sharedDeviceCount: sharedDeviceIDs.count,
            homeLoadFailureCount: homeLoadFailureCount
        ))
    }
}

@MainActor
private final class SmartLifeDriver: NSObject, OfficialTuyaDriver, ThingSmartDeviceDelegate {
    private var device: ThingSmartDevice?
    private var onApplicationUpdate: (([String: String]) -> Void)?

    func connect(
        deviceID: String,
        uuid: String,
        productID: String,
        onApplicationUpdate: @escaping ([String: String]) -> Void,
        success: @escaping () -> Void,
        failure: @escaping () -> Void
    ) {
        guard OfficialTuyaFactory.bootstrap() else {
            failure()
            return
        }
        self.onApplicationUpdate = onApplicationUpdate
        device = ThingSmartDevice(deviceId: deviceID)
        device?.delegate = self
        ThingSmartBLEManager.sharedInstance().connectBLE(
            withUUID: uuid,
            productKey: productID,
            success: success,
            failure: failure
        )
    }

    func isLocallyConnected(uuid: String) -> Bool {
        ThingSmartBLEManager.sharedInstance().deviceStatue(withUUID: uuid)
    }

    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            sanitized[String(describing: key)] = String(describing: value)
        }
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
    @Published private(set) var status = "Initialize the official Tuya SDK to log in this Capture build."
    @Published private(set) var codeSent = false
    @Published private(set) var busy = false
    @Published private(set) var loggedIn = false

    func bootstrap() {
        guard OfficialTuyaFactory.compiled else {
            status = "Official Tuya SmartLife SDK is not compiled into this build."
            loggedIn = false
            return
        }
        guard OfficialTuyaFactory.configured else {
            status = "Private Tuya AppKey/AppSecret are not provisioned for this build."
            loggedIn = false
            return
        }
        guard OfficialTuyaFactory.bootstrap() else {
            status = "Tuya SDK initialization failed closed."
            loggedIn = false
            return
        }
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = loggedIn
            ? "Official Tuya SDK account is logged in. Exact scooter membership must still be verified before BLE authentication."
            : "SDK initialized. Sign in with a verification code; metadata QR approval does not count as SDK device authority."
    }

    func sendCode() {
        bootstrap()
        guard !loggedIn else { return }
        let identity = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty, !country.isEmpty else {
            status = "Enter the Tuya account and country code first."
            return
        }
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
                success: { [weak self] in
                    Task { @MainActor in
                        self?.busy = false
                        self?.codeSent = true
                        self?.status = "Verification code sent by Tuya. Enter it below to log in the SDK account."
                    }
                },
                failure: { [weak self] error in
                    Task { @MainActor in
                        self?.busy = false
                        self?.status = "Tuya could not send the verification code: \(error?.localizedDescription ?? "unknown error")"
                    }
                }
            )
        case .phone:
            let region = user?.getDefaultRegionWithCountryCode(country) ?? ""
            user?.sendVerifyCode(
                withUserName: identity,
                region: region,
                countryCode: country,
                type: 2,
                success: { [weak self] in
                    Task { @MainActor in
                        self?.busy = false
                        self?.codeSent = true
                        self?.status = "Verification code sent by Tuya. Enter it below to log in the SDK account."
                    }
                },
                failure: { [weak self] error in
                    Task { @MainActor in
                        self?.busy = false
                        self?.status = "Tuya could not send the verification code: \(error?.localizedDescription ?? "unknown error")"
                    }
                }
            )
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    func login() {
        bootstrap()
        guard !loggedIn else { return }
        let identity = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty, !country.isEmpty, !code.isEmpty else {
            status = "Enter the account, country code, and Tuya verification code."
            return
        }
#if canImport(ThingSmartHomeKit)
        busy = true
        status = "Logging in the official Tuya SDK account session…"
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
        loggedIn = true
        status = "Official Tuya SDK account logged in. Nembra must now verify that this exact scooter is present in the account's owned/shared home devices."
    }

    private func finishLoginFailure(_ error: Error?) {
        busy = false
        verificationCode = ""
        loggedIn = false
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
                    Text("SMALLEST INDOOR TEST")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.green)
                    Text("Authenticate. Wait. Capture.")
                        .font(.largeTitle.bold())
                    Text("Keep the scooter stationary. Do not run the old 17-step sequence.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(test.passed ? "Secure scooter link established" : test.phase == .failed ? "Secure-link test stopped" : "Authentication preflight")
                                .font(.headline)
                            Spacer()
                            Text("\(test.applicationUpdateCount)")
                                .monospacedDigit()
                        }
                        Text(test.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let age = test.secureSessionAgeSeconds {
                            LabeledContent("Canonical session age", value: String(format: "%.1f s", age))
                            ProgressView(value: min(age / 45, 1))
                        }
                        LabeledContent("Connection generation", value: String(test.ledgerSnapshot.connectionGeneration))
                        LabeledContent("Tuya local BLE", value: test.sdkLocalBLEOnline ? "Online" : "Not proven")
                        LabeledContent("Same-generation updates", value: String(test.applicationUpdateCount))
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Official Tuya authority", systemImage: "checkmark.shield")
                            .font(.headline)
                        LabeledContent("SDK compiled in", value: test.sdkCompiled ? "Yes" : "No")
                        LabeledContent("Private app config", value: test.privateConfig ? "Yes" : "No")
                        LabeledContent("SDK account logged in", value: test.sdkAccountLoggedIn ? "Yes" : "No")
                        LabeledContent("Exact scooter membership", value: test.sdkDeviceMembershipVerified ? "Verified" : "Not verified")
                        Text(test.membershipStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if test.sdkAccountLoggedIn && !test.sdkDeviceMembershipVerified {
                            Button(test.membershipBusy ? "Checking scooter membership…" : "Verify scooter in SDK account") {
                                test.verifySDKMembership()
                            }
                            .buttonStyle(.bordered)
                            .disabled(test.membershipBusy)
                        }
                        if !test.sdkCompiled || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified {
                            Text("NO PHYSICAL TEST YET: the official SDK/security component, matching private app credentials, a logged-in SDK account, and exact membership of this scooter must all be proven. Metadata QR approval or SDK login alone is not BLE authority.")
                                .font(.footnote.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                    .card()

                    if test.sdkCompiled && test.privateConfig && !sdkAccount.loggedIn {
                        sdkAuthorizationCard
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Find the known scooter", systemImage: "scope")
                            .font(.headline)
                        switch test.phase {
                        case .idle, .failed:
                            Button("Start scooter-OFF baseline") { test.startBaseline() }
                                .buttonStyle(.borderedProminent)
                        case .baseline:
                            Button("Save OFF baseline") { test.saveBaseline() }
                                .buttonStyle(.borderedProminent)
                        case .powerOn:
                            Text("Turn scooter ON, keep it still.")
                                .foregroundStyle(.secondary)
                            Button("Scan after power-on") { test.scanAfterPowerOn() }
                                .buttonStyle(.borderedProminent)
                        case .scanning:
                            Button("Stop scan / use deterministic evidence") { test.stopScan() }
                                .buttonStyle(.bordered)
                        default:
                            EmptyView()
                        }
                        ForEach(test.candidates.prefix(8)) { candidate in
                            Button { test.choose(candidate) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(candidate.title).bold()
                                        if candidate.likely {
                                            Text("STRONG MATCH")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.green, in: Capsule())
                                                .foregroundStyle(.black)
                                        }
                                        Spacer()
                                        Text("\(candidate.score)").monospacedDigit()
                                    }
                                    Text("\(candidate.rssi.map { String($0) + " dBm" } ?? "RSSI ?") · \(candidate.id.uuidString)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(candidate.evidence.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card()

                    if let candidate = test.selected {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Authentication gate", systemImage: "key.horizontal")
                                .font(.headline)
                            Text(candidate.evidence.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Start secure read-only test") { test.authenticate() }
                                .buttonStyle(.borderedProminent)
                                .disabled(
                                    !candidate.likely
                                        || !test.sdkCompiled
                                        || !test.privateConfig
                                        || !test.sdkAccountLoggedIn
                                        || !test.sdkDeviceMembershipVerified
                                        || test.membershipBusy
                                        || [.authenticating, .observing, .accepted].contains(test.phase)
                                )
                        }
                        .card()
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Acceptance", systemImage: test.passed ? "checkmark.seal.fill" : "hourglass")
                            .font(.headline)
                            .foregroundStyle(test.passed ? .green : .white)
                        Text("Pass only when the exact scooter is visible in the logged-in SDK account, Tuya's SDK establishes the local BLE session, the canonical same-generation ledger observes at least one genuine dpsUpdate after authentication, and local BLE remains observed for at least 45 seconds. Nembra still assigns no DP meaning here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(test.preflightVerdictText)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        if test.passed {
                            Text("Secure scooter link established\nReceiving scooter data")
                                .font(.title3.bold())
                                .foregroundStyle(.green)
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Prepare sanitized diagnostic JSON") { test.prepareExport() }
                            .buttonStyle(.bordered)
                        if let data = test.exportData {
                            ShareLink(
                                item: SecureTransfer(data: data, name: test.exportName),
                                preview: SharePreview(test.exportName)
                            ) {
                                Label("Share diagnostic JSON", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Text("Export includes exact SDK device-membership authority, canonical connection generation/chronology, local-BLE status, failures, and opaque application-update values as a string projection. It explicitly does not claim raw FD50 bytes and excludes passwords, account tokens, local_key and AppSecret.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .card()
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
            if sdkAccount.loggedIn { test.verifySDKMembership() }
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
            if loggedIn { test.verifySDKMembership() }
            else { test.invalidateSDKMembership() }
        }
    }

    private var sdkAuthorizationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Log in the official SDK account", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            Text(sdkAccount.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Login method", selection: $sdkAccount.method) {
                ForEach(OfficialTuyaAccountAuthorizer.LoginMethod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("Country code (for example 1)", text: $sdkAccount.countryCode)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            TextField(
                sdkAccount.method == .email ? "Tuya account email" : "Tuya account phone number",
                text: $sdkAccount.account
            )
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
                Button("Log in SDK account") { sdkAccount.login() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        sdkAccount.busy
                            || sdkAccount.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
            Text("Nembra does not ask for or persist the Tuya account password here. Verification codes stay in memory and are cleared after the login attempt. A successful login still cannot start BLE until the exact scooter device ID is found in the account's owned/shared home membership.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

private struct SecureTransfer: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.name }
    }
}

private extension View {
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}
