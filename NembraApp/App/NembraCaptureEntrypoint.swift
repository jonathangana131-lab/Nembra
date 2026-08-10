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

@main
@MainActor
struct NembraCaptureApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureP0Root()
                .preferredColorScheme(.dark)
        }
    }
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
                    Text("The next physical run is stationary. It proves supported Tuya authentication, exact SDK-account scooter membership, current local-BLE survival, and genuine application updates. The old ride sequence stays disabled until this passes.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Read-only control boundary", systemImage: "shield.checkered")
                            .font(.headline)
                        Text("Account linking is used only for ownership/device identity. Nembra does not turn local_key into a BLE login key, synthesize Tuya authentication frames, or open a second CoreBluetooth connection after the official SDK takes ownership.")
                            .foregroundStyle(.secondary)
                        Text("No unbind, reset, activation, lock, speed, light, mode, throttle, brake, firmware, DP query, or DP control command is sent.")
                            .font(.footnote.bold())
                            .foregroundStyle(.green)
                    }
                    .card()

                    accountCard
                    if tuya.isLinked {
                        deviceCard
                    }
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
                Button("Create metadata approval QR") {
                    tuya.requestApproval()
                }
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
                Button("I approved it · check now") {
                    tuya.checkApprovalNow()
                }
                .buttonStyle(.bordered)
            }

            if tuya.phase == .failed {
                Button("Reset metadata account link") {
                    tuya.resetLink()
                }
                .buttonStyle(.bordered)
            }

            Text("This QR is metadata/ownership discovery only. It cannot satisfy the official SDK authentication or scooter-membership gates.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2 · Choose the already-bound scooter", systemImage: "bicycle")
                .font(.headline)
            if tuya.devices.isEmpty {
                Button("Refresh Tuya devices") {
                    tuya.refreshDevices()
                }
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
                            NavigationLink("Secure stationary test") {
                                SecureLinkView(device: device)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(12)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }

            Text("Only the exact Tuya device ID, device UUID, and product ID enter the supported secure-link controller. local_key does not.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

@MainActor
private final class OfficialTuyaMembershipVerifier: ObservableObject {
    @Published private(set) var verdict: TuyaSDKAccountDeviceMembershipGate.Verdict =
        .blocked(reason: "Tuya SDK scooter membership has not been verified yet.")
    @Published private(set) var status = "Authorize the official SDK account, then verify the exact scooter device ID in its home membership."
    @Published private(set) var busy = false
    @Published private(set) var loadedHomeCount = 0
    @Published private(set) var ownedDeviceCount = 0
    @Published private(set) var sharedDeviceCount = 0

    let expectedDeviceID: String

#if canImport(ThingSmartHomeKit)
    private let homeManager = ThingSmartHomeManager()
    private var activeHomes: [ThingSmartHome] = []
#endif

    init(expectedDeviceID: String) {
        self.expectedDeviceID = expectedDeviceID
    }

    var authorized: Bool {
        if case .authorized = verdict { return true }
        return false
    }

    func verify() {
        guard !busy else { return }
        guard OfficialTuyaFactory.accountReady else {
            apply(snapshot: .init(
                isLoggedIn: false,
                homeEnumerationCompleted: false,
                loadedHomeCount: 0,
                ownedDeviceIDs: [],
                sharedDeviceIDs: [],
                homeLoadFailureCount: 0
            ))
            status = "The official Tuya SDK account is not authorized. Scooter membership cannot be trusted yet."
            return
        }

#if canImport(ThingSmartHomeKit)
        busy = true
        loadedHomeCount = 0
        ownedDeviceCount = 0
        sharedDeviceCount = 0
        activeHomes.removeAll()
        status = "Enumerating Tuya homes and exact device membership…"

        homeManager.getHomeList(success: { [weak self] homes in
            Task { @MainActor in
                self?.consumeHomeList(homes ?? [])
            }
        }, failure: { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.apply(snapshot: .init(
                    isLoggedIn: OfficialTuyaFactory.accountReady,
                    homeEnumerationCompleted: false,
                    loadedHomeCount: 0,
                    ownedDeviceIDs: [],
                    sharedDeviceIDs: [],
                    homeLoadFailureCount: 1
                ))
                self.status = "Tuya home enumeration failed closed: \(error?.localizedDescription ?? "unknown error")"
            }
        })
#else
        busy = false
        apply(snapshot: .init(
            isLoggedIn: false,
            homeEnumerationCompleted: false,
            loadedHomeCount: 0,
            ownedDeviceIDs: [],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 0
        ))
        status = "Official Tuya SmartLife SDK is not compiled into this field build."
#endif
    }

#if canImport(ThingSmartHomeKit)
    private func consumeHomeList(_ homes: [ThingSmartHomeModel]) {
        guard OfficialTuyaFactory.accountReady else {
            busy = false
            apply(snapshot: .init(
                isLoggedIn: false,
                homeEnumerationCompleted: false,
                loadedHomeCount: 0,
                ownedDeviceIDs: [],
                sharedDeviceIDs: [],
                homeLoadFailureCount: 0
            ))
            status = "The Tuya SDK account session ended while membership was being checked."
            return
        }

        guard !homes.isEmpty else {
            busy = false
            apply(snapshot: .init(
                isLoggedIn: true,
                homeEnumerationCompleted: true,
                loadedHomeCount: 0,
                ownedDeviceIDs: [],
                sharedDeviceIDs: [],
                homeLoadFailureCount: 0
            ))
            status = "The logged-in Tuya SDK account has no homes, so it cannot authorize the selected scooter."
            return
        }

        var owned = Set<String>()
        var shared = Set<String>()
        var loaded = 0
        var failures = 0
        var remaining = homes.count

        func finishOne() {
            remaining -= 1
            guard remaining == 0 else { return }
            self.busy = false
            self.loadedHomeCount = loaded
            self.ownedDeviceCount = owned.count
            self.sharedDeviceCount = shared.count
            self.apply(snapshot: .init(
                isLoggedIn: OfficialTuyaFactory.accountReady,
                homeEnumerationCompleted: true,
                loadedHomeCount: loaded,
                ownedDeviceIDs: owned,
                sharedDeviceIDs: shared,
                homeLoadFailureCount: failures
            ))
            switch self.verdict {
            case .authorized:
                self.status = "Exact scooter membership verified in the official Tuya SDK account."
            case .blocked(let reason):
                self.status = reason
            }
            self.activeHomes.removeAll()
        }

        for model in homes {
            guard let home = ThingSmartHome(homeId: model.homeId) else {
                failures += 1
                finishOne()
                continue
            }
            activeHomes.append(home)
            home.getDataWithSuccess({ _ in
                Task { @MainActor in
                    loaded += 1
                    for device in home.deviceList ?? [] {
                        if let devID = device.devId, !devID.isEmpty {
                            owned.insert(devID)
                        }
                    }
                    for device in home.sharedDeviceList ?? [] {
                        if let devID = device.devId, !devID.isEmpty {
                            shared.insert(devID)
                        }
                    }
                    finishOne()
                }
            }, failure: { _ in
                Task { @MainActor in
                    failures += 1
                    finishOne()
                }
            })
        }
    }
#endif

    private func apply(snapshot: TuyaSDKAccountDeviceMembershipGate.Snapshot) {
        verdict = TuyaSDKAccountDeviceMembershipGate.verdict(
            expectedDeviceID: expectedDeviceID,
            snapshot: snapshot
        )
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

        var title: String {
            name?.isEmpty == false ? name! : "Unnamed peripheral"
        }

        /// Only deterministic physical identity or corroborating FD50+Tuya-company
        /// evidence may authorize selection. Name/RSSI/power-cycle hints rank only.
        var likely: Bool {
            knownID || (fd50 && tuyaCompany)
        }
    }

    enum Phase: String, Codable {
        case idle
        case baseline
        case powerOn
        case scanning
        case selected
        case authenticating
        case observing
        case accepted
        case failed
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
        let sdkAccountAuthorized: Bool
        let sdkDeviceMembershipAuthorized: Bool
        let connectionGeneration: UInt64?
        let authenticationMethod: String?
        let authenticatedDurationSeconds: Double?
        let sdkLocalBLEOnline: Bool
        let applicationUpdateCount: Int
        let canonicalPreflightVerdict: String
        let applicationValueRepresentation: String
        let rawFD50BytesCaptured: Bool
        let secretsRedacted: Bool
        let dpCommandsSent: Bool
        let candidates: [Candidate]
        let events: [Event]
    }

    static let knownPeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    static let fd50 = CBUUID(string: "FD50")

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Start with the scooter OFF. This test identifies it, then proves Tuya's supported secure session."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var applicationUpdateCount = 0
    @Published private(set) var sdkLocalBLEOnline = false
    @Published private(set) var authenticatedDurationSeconds: Double?
    @Published private(set) var canonicalPreflightVerdict = "Blocked · Tuya authentication required."
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
    private let sessionLedger = TuyaAuthenticatedReadOnlySessionLedger()
    private var currentToken: TuyaReadOnlyConnectionToken?
    private var authenticationRecorded = false
    private var connectionRequestedAtUptime: UInt64?
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

    deinit {
        watchdog?.cancel()
    }

    var sdkCompiled: Bool { OfficialTuyaFactory.compiled }
    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var sdkAccountAuthorized: Bool { OfficialTuyaFactory.accountReady }
    var selected: Candidate? { selectedID.flatMap { byID[$0] } }
    var accepted: Bool { phase == .accepted }
    var connectionGeneration: UInt64? { currentToken?.diagnosticGeneration }

    func startBaseline() {
        guard central.state == .poweredOn else {
            fail("Bluetooth is not ready.", "bluetooth_unavailable")
            return
        }
        resetDiscovery()
        phase = .baseline
        message = "Keep the scooter OFF for a few seconds."
        log("baseline_started")
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
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
        message = "Ranking OFF→ON delta, exact prior UUID, FD50, Tuya company ID, name, and RSSI. Only exact prior identity or FD50+Tuya corroboration can authorize selection."
        log("power_on_scan_started")
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        central.stopScan()
        if selectedID == nil,
           let first = candidates.first,
           first.likely {
            choose(first)
        }
        if selectedID == nil {
            message = "No candidate has authoritative scooter/Tuya evidence. Re-scan instead of guessing."
        }
        log("scan_stopped")
    }

    func choose(_ candidate: Candidate) {
        guard candidate.likely else {
            message = "Name, RSSI, and power-cycle timing are ranking hints only. This candidate lacks authoritative exact-UUID or FD50+Tuya evidence."
            return
        }
        central.stopScan()
        selectedID = candidate.id
        phase = .selected
        message = "Correlated scooter target selected. CoreBluetooth discovery is stopped before Tuya's SDK takes authenticated BLE ownership."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "score": String(candidate.score),
            "evidence": candidate.evidence.joined(separator: ",")
        ])
    }

    func authenticate(membershipVerdict: TuyaSDKAccountDeviceMembershipGate.Verdict) {
        guard let candidate = selected, candidate.likely else {
            fail("A strongly correlated scooter target is required.", "candidate_not_authoritative")
            return
        }
        guard case .authorized = membershipVerdict else {
            fail("The official Tuya SDK account has not proven exact membership for the selected scooter device ID.", "sdk_device_membership_not_authorized")
            return
        }
        guard !deviceID.isEmpty, !tuyaUUID.isEmpty, !productID.isEmpty else {
            fail("Tuya device ID, UUID, or product ID is missing.", "tuya_identity_incomplete")
            return
        }
        guard sdkCompiled, privateConfig else {
            fail("Official Tuya SmartLife SDK/security configuration is not provisioned. Do not run the physical test yet.", "sdk_unavailable")
            return
        }
        guard sdkAccountAuthorized else {
            fail("The official Tuya SDK has no authorized account session. Metadata QR approval cannot substitute for SDK login.", "sdk_account_not_authorized")
            return
        }
        guard let newDriver = OfficialTuyaFactory.make() else {
            fail("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

        central.stopScan()
        watchdog?.cancel()
        watchdog = nil
        driver = newDriver
        authenticationRecorded = false
        sdkLocalBLEOnline = false
        applicationUpdateCount = 0
        authenticatedDurationSeconds = nil
        canonicalPreflightVerdict = "Blocked · Tuya authentication is starting."
        phase = .authenticating
        message = "Tuya's SDK is establishing the supported secure BLE session. Nembra sends no DP command."

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = try await sessionLedger.beginConnection()
                try await sessionLedger.markAuthenticationStarted(for: token)
                guard self.phase == .authenticating else {
                    try? await self.sessionLedger.endConnection(for: token)
                    return
                }
                self.currentToken = token
                self.connectionRequestedAtUptime = DispatchTime.now().uptimeNanoseconds
                self.log("official_connect_requested", [
                    "coreBluetoothID": candidate.id.uuidString,
                    "tuyaDeviceID": self.deviceID,
                    "tuyaUUID": self.tuyaUUID,
                    "productID": self.productID,
                    "generation": String(token.diagnosticGeneration)
                ])
                await self.refreshCanonicalState(for: token)

                newDriver.connect(
                    deviceID: self.deviceID,
                    uuid: self.tuyaUUID,
                    productID: self.productID,
                    onApplicationUpdate: { [weak self] update in
                        Task { @MainActor in
                            await self?.receivedApplicationUpdate(update, token: token)
                        }
                    },
                    success: { [weak self] in
                        Task { @MainActor in
                            await self?.officialConnectReturnedSuccess(token: token)
                        }
                    },
                    failure: { [weak self] reason in
                        Task { @MainActor in
                            await self?.failCurrentConnection(reason, kind: "official_connect_failed", token: token)
                        }
                    }
                )
            } catch {
                self.fail("Unable to start a fresh authenticated-session generation: \(error)", "ledger_begin_failed")
            }
        }
    }

    private func officialConnectReturnedSuccess(token: TuyaReadOnlyConnectionToken) async {
        guard token == currentToken, phase == .authenticating else { return }
        phase = .observing
        message = "Official connect callback returned. It is not physical acceptance. Waiting for Tuya's own current local-BLE status before starting authenticated chronology."
        log("official_connect_success_callback", ["generation": String(token.diagnosticGeneration)])
        await sampleCurrentLocalBLE(token: token)
        if phase != .failed {
            startWatchdog(token: token)
        }
    }

    private func sampleCurrentLocalBLE(token: TuyaReadOnlyConnectionToken) async {
        guard token == currentToken,
              [.authenticating, .observing, .accepted].contains(phase),
              let driver else { return }

        let connected = driver.isLocallyConnected(uuid: tuyaUUID)
        if connected {
            sdkLocalBLEOnline = true
            do {
                if !authenticationRecorded {
                    try await sessionLedger.markAuthenticated(
                        for: token,
                        method: .smartLifeAppSDK
                    )
                    authenticationRecorded = true
                    log("sdk_local_ble_authenticated", [
                        "generation": String(token.diagnosticGeneration)
                    ])
                    message = "Tuya's current local BLE authority is online. Waiting for at least one genuine application callback while the canonical stability clock advances."
                } else {
                    try await sessionLedger.observeCurrentConnection(for: token)
                }
            } catch {
                await failCurrentConnection("Authenticated-session ledger rejected the current local-BLE observation: \(error)", kind: "ledger_local_observation_rejected", token: token)
                return
            }
            await refreshCanonicalState(for: token)
            return
        }

        sdkLocalBLEOnline = false
        if authenticationRecorded {
            await failCurrentConnection(
                "Tuya's local BLE status dropped after authentication. This generation cannot satisfy the stability gate.",
                kind: "sdk_local_ble_dropped",
                token: token
            )
        }
    }

    private func receivedApplicationUpdate(
        _ update: [String: String],
        token: TuyaReadOnlyConnectionToken
    ) async {
        guard token == currentToken,
              [.authenticating, .observing, .accepted].contains(phase),
              let driver else {
            log("stale_application_update_ignored")
            return
        }

        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await failCurrentConnection(
                "A Tuya application callback arrived without current local-BLE authority, so it was rejected from physical evidence.",
                kind: "application_update_without_current_ble",
                token: token
            )
            return
        }

        guard authenticationRecorded else {
            log("application_update_before_authenticated_ledger_state_ignored", [
                "generation": String(token.diagnosticGeneration)
            ])
            return
        }

        guard let payloadEvidence = try? JSONSerialization.data(
            withJSONObject: update,
            options: [.sortedKeys]
        ), !payloadEvidence.isEmpty else {
            await failCurrentConnection(
                "Tuya delivered an application callback that could not be represented as non-empty opaque application evidence.",
                kind: "application_update_encoding_failed",
                token: token
            )
            return
        }

        do {
            try await sessionLedger.recordApplicationPayload(payloadEvidence, for: token)
            log("tuya_application_update", update)
            await refreshCanonicalState(for: token)
        } catch {
            await failCurrentConnection(
                "Authenticated-session ledger rejected an application callback: \(error)",
                kind: "ledger_application_update_rejected",
                token: token
            )
        }
    }

    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self,
                      token == self.currentToken,
                      [.authenticating, .observing, .accepted].contains(self.phase) else { return }

                await self.sampleCurrentLocalBLE(token: token)
                if self.phase == .failed || token != self.currentToken { return }

                if !self.authenticationRecorded,
                   let requestedAt = self.connectionRequestedAtUptime {
                    let now = DispatchTime.now().uptimeNanoseconds
                    if now >= requestedAt,
                       now - requestedAt >= 15_000_000_000 {
                        await self.failCurrentConnection(
                            "The Tuya connect callback did not become a current local-BLE authenticated session within 15 seconds.",
                            kind: "sdk_local_ble_never_current",
                            token: token
                        )
                        return
                    }
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshCanonicalState(for token: TuyaReadOnlyConnectionToken) async {
        guard token == currentToken else { return }
        let snapshot = await sessionLedger.currentPreflightSnapshot()
        guard token == currentToken,
              snapshot.connectionGeneration == token.diagnosticGeneration else { return }

        applicationUpdateCount = snapshot.applicationPayloadCount
        if let authenticatedAt = snapshot.authenticatedAtUptimeNanoseconds,
           let latest = snapshot.latestObservedUptimeNanoseconds,
           latest >= authenticatedAt {
            authenticatedDurationSeconds = Double(latest - authenticatedAt) / 1_000_000_000
        } else {
            authenticatedDurationSeconds = nil
        }

        let verdict = TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot)
        switch verdict {
        case .blocked(let reason):
            canonicalPreflightVerdict = "Blocked · \(reason)"
            if phase == .observing, applicationUpdateCount > 0 {
                message = "Receiving genuine Tuya application data · \(applicationUpdateCount) callback(s). Keep the scooter stationary until the canonical 45-second gate passes."
            }
        case .readyForStationaryMapping:
            guard sdkLocalBLEOnline,
                  authenticationRecorded,
                  phase == .observing else { return }
            canonicalPreflightVerdict = "READY · authenticated read-only preflight accepted"
            phase = .accepted
            message = "Secure scooter link accepted. The same current Tuya generation remained locally online beyond the stability window and delivered genuine application data. Only the next stationary mapping experiment may unlock now."
            log("canonical_preflight_accepted", [
                "generation": String(token.diagnosticGeneration),
                "applicationUpdates": String(snapshot.applicationPayloadCount)
            ])
        }
    }

    private func failCurrentConnection(
        _ text: String,
        kind: String,
        token: TuyaReadOnlyConnectionToken
    ) async {
        guard token == currentToken else {
            log("stale_failure_ignored", ["kind": kind])
            return
        }
        try? await sessionLedger.endConnection(for: token)
        currentToken = nil
        authenticationRecorded = false
        sdkLocalBLEOnline = false
        authenticatedDurationSeconds = nil
        canonicalPreflightVerdict = "Blocked · \(text)"
        fail(text, kind)
    }

    func prepareExport(membershipAuthorized: Bool) {
        let envelope = Export(
            schemaVersion: 4,
            purpose: "Sanitized Tuya authenticated read-only canonical preflight",
            exportedAt: Date(),
            tuyaDeviceID: deviceID,
            tuyaUUID: tuyaUUID,
            productID: productID,
            selectedPeripheralID: selectedID?.uuidString,
            phase: phase,
            sdkCompiled: sdkCompiled,
            privateConfigPresent: privateConfig,
            sdkAccountAuthorized: sdkAccountAuthorized,
            sdkDeviceMembershipAuthorized: membershipAuthorized,
            connectionGeneration: connectionGeneration,
            authenticationMethod: authenticationRecorded ? TuyaReadOnlyAuthenticationMethod.smartLifeAppSDK.rawValue : nil,
            authenticatedDurationSeconds: authenticatedDurationSeconds,
            sdkLocalBLEOnline: sdkLocalBLEOnline,
            applicationUpdateCount: applicationUpdateCount,
            canonicalPreflightVerdict: canonicalPreflightVerdict,
            applicationValueRepresentation: "ThingSmartDeviceDelegate dpsUpdate values projected to [String:String] and serialized only as non-empty application-callback evidence for chronology. Not byte-exact and not raw FD50 transport.",
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
            message = "Sanitized diagnostics ready. SDK application values are not exported as raw FD50 bytes. Passwords, verification codes, account tokens, local_key, AppKey, and AppSecret are excluded."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    private func resetDiscovery() {
        central.stopScan()
        watchdog?.cancel()
        watchdog = nil
        let token = currentToken
        currentToken = nil
        if let token {
            Task { [sessionLedger] in
                try? await sessionLedger.endConnection(for: token)
            }
        }
        driver = nil
        byID.removeAll()
        candidates.removeAll()
        baseline.removeAll()
        selectedID = nil
        authenticationRecorded = false
        sdkLocalBLEOnline = false
        connectionRequestedAtUptime = nil
        applicationUpdateCount = 0
        authenticatedDurationSeconds = nil
        canonicalPreflightVerdict = "Blocked · Tuya authentication required."
        exportData = nil
    }

    private func fail(_ text: String, _ kind: String) {
        watchdog?.cancel()
        watchdog = nil
        phase = .failed
        message = text
        log(kind, ["message": sanitize(text)])
    }

    private func log(_ kind: String, _ details: [String: String] = [:]) {
        events.append(Event(
            at: Date(),
            kind: kind,
            details: details.mapValues(sanitize)
        ))
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
        return (UInt16(data[data.startIndex]) |
                UInt16(data[data.index(after: data.startIndex)]) << 8) == 0x07D0
    }

    private func updateCandidate(
        _ peripheral: CBPeripheral,
        advertisement: [String: Any],
        rssi number: NSNumber
    ) {
        let id = peripheral.identifier
        if phase == .baseline { baseline.insert(id) }

        let old = byID[id]
        let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? old?.name
        let rssi = number.intValue == 127 ? old?.rssi : number.intValue
        let serviceUUIDs =
            ((advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []) +
            ((advertisement[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []) +
            ((advertisement[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID]) ?? [])
        let serviceData = advertisement[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let fd50 = serviceUUIDs.contains(Self.fd50) ||
            serviceData?.keys.contains(Self.fd50) == true ||
            old?.fd50 == true
        let tuyaCompany = Self.hasTuyaCompanyID(
            advertisement[CBAdvertisementDataManufacturerDataKey] as? Data
        ) || old?.tuyaCompany == true
        let knownID = id == Self.knownPeripheral
        let newAfterPowerOn =
            (phase == .scanning && !baseline.contains(id)) || old?.newAfterPowerOn == true
        let expectedName =
            name?.localizedCaseInsensitiveContains("demo") == true ||
            name?.localizedCaseInsensitiveContains("tuya") == true ||
            old?.expectedName == true

        var score = 0
        var evidence: [String] = []
        if knownID { score += 1000; evidence.append("exact prior physical UUID") }
        if fd50 { score += 500; evidence.append("FD50") }
        if tuyaCompany { score += 350; evidence.append("Tuya company 0x07D0") }
        if newAfterPowerOn { score += 180; evidence.append("appeared after power-on") }
        if expectedName { score += 100; evidence.append("name hint") }
        if let rssi {
            if rssi >= -50 { score += 80; evidence.append("very close RSSI") }
            else if rssi >= -65 { score += 50; evidence.append("nearby RSSI") }
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
            $0.score == $1.score
                ? (($0.rssi ?? -999) > ($1.rssi ?? -999))
                : $0.score > $1.score
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
        failure: @escaping (String) -> Void
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

    static func privateCredential(named name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            return nil
        }
        return value
    }

    static var configured: Bool {
        compiled &&
        privateCredential(named: "NEMBRA_TUYA_APP_KEY") != nil &&
        privateCredential(named: "NEMBRA_TUYA_APP_SECRET") != nil
    }

    @discardableResult
    static func bootstrap() -> Bool {
#if canImport(ThingSmartHomeKit)
        guard let key = privateCredential(named: "NEMBRA_TUYA_APP_KEY"),
              let secret = privateCredential(named: "NEMBRA_TUYA_APP_SECRET") else {
            return false
        }
        if !didBootstrap {
            ThingSmartSDK.sharedInstance()?.start(withAppKey: key, secretKey: secret)
            didBootstrap = true
        }
        return true
#else
        return false
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

#if canImport(ThingSmartHomeKit)
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
        failure: @escaping (String) -> Void
    ) {
        guard OfficialTuyaFactory.bootstrap(), OfficialTuyaFactory.accountReady else {
            failure("Official Tuya SDK is not initialized with an authorized account session.")
            return
        }
        self.onApplicationUpdate = onApplicationUpdate
        device = ThingSmartDevice(deviceId: deviceID)
        device?.delegate = self
        ThingSmartBLEManager.sharedInstance().connectBLE(
            withUUID: uuid,
            productKey: productID,
            success: success,
            failure: {
                failure("Tuya SmartLife SDK did not establish the BLE session.")
            }
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
    @Published private(set) var status = "Initialize the official Tuya SDK to authorize this Capture build."
    @Published private(set) var codeSent = false
    @Published private(set) var busy = false
    @Published private(set) var authorized = false

    func bootstrap() {
        guard OfficialTuyaFactory.compiled else {
            status = "Official Tuya SmartLife SDK is not compiled into this build."
            authorized = false
            return
        }
        guard OfficialTuyaFactory.configured else {
            status = "Private Tuya AppKey/AppSecret are not provisioned for this build."
            authorized = false
            return
        }
        guard OfficialTuyaFactory.bootstrap() else {
            status = "Tuya SDK initialization failed closed."
            authorized = false
            return
        }
        authorized = OfficialTuyaFactory.accountReady
        status = authorized
            ? "Official Tuya SDK account session is authorized."
            : "SDK initialized. Sign in with a verification code; the metadata QR session does not count as BLE authentication authority."
    }

    func sendCode() {
        bootstrap()
        guard !authorized else { return }
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
                        self?.status = "Verification code sent by Tuya. Enter it below to authorize the SDK session."
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
                        self?.status = "Verification code sent by Tuya. Enter it below to authorize the SDK session."
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
        guard !authorized else { return }
        let identity = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty, !country.isEmpty, !code.isEmpty else {
            status = "Enter the account, country code, and Tuya verification code."
            return
        }

#if canImport(ThingSmartHomeKit)
        busy = true
        status = "Authorizing the official Tuya SDK account session…"
        switch method {
        case .email:
            ThingSmartUser.sharedInstance()?.login(
                withEmail: identity,
                countryCode: country,
                code: code,
                success: { [weak self] in
                    Task { @MainActor in self?.finishLoginSuccess() }
                },
                failure: { [weak self] error in
                    Task { @MainActor in self?.finishLoginFailure(error) }
                }
            )
        case .phone:
            ThingSmartUser.sharedInstance()?.login(
                withMobile: identity,
                countryCode: country,
                code: code,
                success: { [weak self] in
                    Task { @MainActor in self?.finishLoginSuccess() }
                },
                failure: { [weak self] error in
                    Task { @MainActor in self?.finishLoginFailure(error) }
                }
            )
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    private func finishLoginSuccess() {
        busy = false
        verificationCode = ""
        authorized = OfficialTuyaFactory.accountReady
        status = authorized
            ? "Official Tuya SDK account authorized. Verify exact scooter membership next."
            : "Tuya returned login success, but no current SDK account authority is visible."
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
    @StateObject private var membership: OfficialTuyaMembershipVerifier

    init(device: TuyaAccountBridge.LinkedDevice) {
        _test = StateObject(wrappedValue: SecureLinkController(device: device))
        _sdkAccount = StateObject(wrappedValue: OfficialTuyaAccountAuthorizer())
        _membership = StateObject(wrappedValue: OfficialTuyaMembershipVerifier(expectedDeviceID: device.id))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SMALLEST INDOOR TEST")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.green)
                    Text("Authenticate. Wait. Observe.")
                        .font(.largeTitle.bold())
                    Text("Keep the scooter stationary. Do not run the old ride sequence.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(test.accepted ? "Canonical secure-link gate accepted" : test.phase == .failed ? "Secure-link test stopped" : "Authentication preflight")
                                .font(.headline)
                            Spacer()
                            Text("\(test.applicationUpdateCount)")
                                .monospacedDigit()
                        }
                        Text(test.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let age = test.authenticatedDurationSeconds {
                            LabeledContent("Authenticated chronology", value: String(format: "%.1f s", age))
                            ProgressView(value: min(age / 45, 1))
                        }
                        LabeledContent("Tuya local BLE", value: test.sdkLocalBLEOnline ? "Current" : "Not proven")
                        LabeledContent("Application callbacks", value: String(test.applicationUpdateCount))
                        LabeledContent("Ledger generation", value: test.connectionGeneration.map(String.init) ?? "None")
                        Text(test.canonicalPreflightVerdict)
                            .font(.caption.monospaced())
                            .foregroundStyle(test.accepted ? .green : .secondary)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Official Tuya gates", systemImage: "checkmark.shield")
                            .font(.headline)
                        LabeledContent("SDK compiled in", value: test.sdkCompiled ? "Yes" : "No")
                        LabeledContent("Private app config", value: test.privateConfig ? "Yes" : "No")
                        LabeledContent("SDK account", value: test.sdkAccountAuthorized ? "Authorized" : "Not authorized")
                        LabeledContent("Exact scooter membership", value: membership.authorized ? "Verified" : "Not verified")
                        if !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized || !membership.authorized {
                            Text("NO PHYSICAL AUTH TEST YET: the private Tuya SDK/security build, authorized SDK account, and exact selected scooter membership must all be current. Metadata QR approval alone is not BLE authority.")
                                .font(.footnote.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                    .card()

                    if test.sdkCompiled && test.privateConfig && !sdkAccount.authorized {
                        sdkAuthorizationCard
                    }

                    if sdkAccount.authorized {
                        membershipCard
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
                            Button("Stop scan / use best authoritative evidence") { test.stopScan() }
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
                                            Text("AUTHORIZED TARGET EVIDENCE")
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
                            Button("Start secure read-only test") {
                                test.authenticate(membershipVerdict: membership.verdict)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                !candidate.likely ||
                                !test.sdkCompiled ||
                                !test.privateConfig ||
                                !test.sdkAccountAuthorized ||
                                !membership.authorized ||
                                [.authenticating, .observing, .accepted].contains(test.phase)
                            )
                        }
                        .card()
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Acceptance", systemImage: test.accepted ? "checkmark.seal.fill" : "hourglass")
                            .font(.headline)
                            .foregroundStyle(test.accepted ? .green : .white)
                        Text("The UI owns no parallel pass boolean. Only TuyaAuthenticatedReadOnlyPreflight.verdict(for:) can accept the generation after the tokenized session ledger proves supported authentication provenance, valid monotonic chronology, at least one post-auth application callback, and 45 seconds of current local-BLE observation.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if test.accepted {
                            Text("Secure scooter link established\nReady for the next stationary evidence step")
                                .font(.title3.bold())
                                .foregroundStyle(.green)
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Prepare sanitized diagnostic JSON") {
                            test.prepareExport(membershipAuthorized: membership.authorized)
                        }
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
                        Text("Export includes target evidence, exact SDK-membership result, ledger generation, canonical verdict, observed continuity, local-BLE status, and opaque application-callback counts. It explicitly does not claim raw FD50 bytes or DP meanings and excludes passwords, verification codes, account tokens, local_key, AppKey, and AppSecret.")
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
            if sdkAccount.authorized {
                membership.verify()
            }
        }
        .onChange(of: sdkAccount.authorized) { authorized in
            if authorized {
                membership.verify()
            }
        }
    }

    private var sdkAuthorizationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Authorize the official SDK session", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            Text(sdkAccount.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Login method", selection: $sdkAccount.method) {
                ForEach(OfficialTuyaAccountAuthorizer.LoginMethod.allCases) {
                    Text($0.rawValue).tag($0)
                }
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
            Button(sdkAccount.busy ? "Contacting Tuya…" : "Send login code") {
                sdkAccount.sendCode()
            }
            .buttonStyle(.bordered)
            .disabled(sdkAccount.busy)
            if sdkAccount.codeSent {
                SecureField("Verification code", text: $sdkAccount.verificationCode)
                    .keyboardType(.numberPad)
                    .privacySensitive()
                    .padding(10)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                Button("Authorize SDK account") {
                    sdkAccount.login()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    sdkAccount.busy ||
                    sdkAccount.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            Text("Nembra does not ask for or persist the Tuya account password. Verification codes stay in memory and are cleared after the login attempt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Verify exact scooter membership", systemImage: "checkmark.shield")
                .font(.headline)
            Text(membership.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
            LabeledContent("Loaded homes", value: String(membership.loadedHomeCount))
            LabeledContent("Owned devices", value: String(membership.ownedDeviceCount))
            LabeledContent("Shared devices", value: String(membership.sharedDeviceCount))
            Button(membership.busy ? "Checking homes…" : "Verify scooter membership") {
                membership.verify()
            }
            .buttonStyle(.borderedProminent)
            .disabled(membership.busy)
            Text("This is read-only membership inspection. If the exact scooter is absent, Nembra fails closed; it does not pair, activate, reset, unbind, or re-home the scooter to force a pass.")
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
