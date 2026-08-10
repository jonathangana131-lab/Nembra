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
    var body: some Scene {
        WindowGroup {
            CaptureP0Root()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - P0 shell

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

                    Text("The next physical run is stationary. It proves supported Tuya authentication, current SDK-account ownership, more than 45 seconds of observed local BLE continuity, and at least one genuine Tuya application update. The old 17-step ride sequence stays disabled until this gate passes.")
                        .foregroundStyle(.secondary)

                    safetyCard
                    accountMetadataCard
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

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Read-only control boundary", systemImage: "shield.checkered")
                .font(.headline)
            Text("Account metadata is used only to identify the already-bound scooter. Nembra does not turn local_key into BLE authentication material, synthesize Tuya authentication frames, or open a second CoreBluetooth connection after the official SDK takes connection ownership.")
                .foregroundStyle(.secondary)
            Text("No unbind, reset, pair, lock, speed, light, mode, throttle, brake, firmware, or other DP/control command is sent.")
                .font(.footnote.bold())
                .foregroundStyle(.green)
        }
        .captureCard()
    }

    private var accountMetadataCard: some View {
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

                Button("Create approval QR") {
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
                Button("Reset account link") {
                    tuya.resetLink()
                }
                .buttonStyle(.bordered)
            }
        }
        .captureCard()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2 · Choose the scooter", systemImage: "bicycle")
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
                            NavigationLink("Secure link test") {
                                SecureLinkView(device: device)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(12)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }

            Text("Only the Tuya device ID, device UUID, and product ID enter the supported secure-link path. local_key never does.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .captureCard()
    }
}

// MARK: - Canonical secure-link authority

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

        /// Authority is intentionally narrower than ranking.
        /// Name, RSSI and OFF→ON appearance may rank candidates, but cannot authorize a target.
        var authoritativeTarget: Bool {
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
        let sdkConnectCallbackSucceeded: Bool
        let sdkLocalBLEOnline: Bool
        let canonicalConnectionGeneration: UInt64
        let canonicalAuthenticationState: String
        let canonicalAuthenticationMethod: String?
        let canonicalAuthenticatedDurationSeconds: Double?
        let canonicalApplicationPayloadCount: Int
        let canonicalVerdict: String
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
    @Published private(set) var message = "Authorize the official Tuya SDK account before Bluetooth discovery."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var sdkConnectCallbackSucceeded = false
    @Published private(set) var sdkLocalBLEOnline = false
    @Published private(set) var preflightSnapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
        authenticationState: .unavailable(reason: "No active authenticated scooter session."),
        connectionStartedAtUptimeNanoseconds: nil,
        authenticatedAtUptimeNanoseconds: nil,
        latestObservedUptimeNanoseconds: nil,
        applicationPayloadCount: 0,
        connectionGeneration: 0
    )
    @Published private(set) var canonicalVerdict: TuyaAuthenticatedReadOnlyPreflight.Verdict =
        .blocked(reason: "No active authenticated scooter session.")
    @Published private(set) var exportData: Data?
    @Published private(set) var exportName = "Nembra-Secure-Link-Diagnostics.json"

    let deviceID: String
    let deviceName: String
    let productID: String
    let tuyaUUID: String

    private let accountAuthorizer: OfficialTuyaAccountAuthorizer
    private let ledger: TuyaAuthenticatedReadOnlySessionLedger
    private let preflightProvider: any TuyaReadOnlyAuthenticationSessionProvider
    private var connectionToken: TuyaReadOnlyConnectionToken?
    private var didMarkAuthenticated = false
    private var connectRequestedAtUptimeNanoseconds: UInt64?
    private var central: CBCentralManager!
    private var byID: [UUID: Candidate] = [:]
    private var baseline = Set<UUID>()
    private var driver: OfficialTuyaDriver?
    private var events: [Event] = []
    private var watchdog: Task<Void, Never>?

    init(device: TuyaAccountBridge.LinkedDevice, accountAuthorizer: OfficialTuyaAccountAuthorizer) {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        self.ledger = ledger
        self.preflightProvider = ledger
        self.accountAuthorizer = accountAuthorizer
        self.deviceID = device.id
        self.deviceName = device.name
        self.productID = device.productID
        self.tuyaUUID = device.uuid
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        log("controller_created")
    }

    deinit {
        watchdog?.cancel()
    }

    var sdkCompiled: Bool { OfficialTuyaFactory.compiled }
    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var sdkAccountAuthorized: Bool { OfficialTuyaFactory.accountReady && accountAuthorizer.authorized }
    var sdkDeviceMembershipAuthorized: Bool { accountAuthorizer.membershipAuthorized }
    var selected: Candidate? { selectedID.flatMap { byID[$0] } }

    var accepted: Bool {
        if case .readyForStationaryMapping = canonicalVerdict {
            return phase == .accepted
        }
        return false
    }

    var authenticatedDurationSeconds: Double? {
        guard let authenticatedAt = preflightSnapshot.authenticatedAtUptimeNanoseconds,
              let latest = preflightSnapshot.latestObservedUptimeNanoseconds,
              latest >= authenticatedAt else {
            return nil
        }
        return Double(latest - authenticatedAt) / 1_000_000_000
    }

    var canonicalBlockReason: String? {
        if case let .blocked(reason) = canonicalVerdict {
            return reason
        }
        return nil
    }

    func startBaseline() {
        guard sdkAccountAuthorized else {
            fail("Authorize the official Tuya SDK account before Bluetooth discovery.", "sdk_account_not_authorized")
            return
        }
        guard sdkDeviceMembershipAuthorized else {
            fail("The official Tuya SDK account has not proven membership of this exact scooter device ID.", "sdk_device_membership_not_authorized")
            return
        }
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
        guard sdkAccountAuthorized, sdkDeviceMembershipAuthorized else {
            fail("Tuya SDK account/device authority expired before the ON scan.", "sdk_account_authority_lost")
            return
        }
        guard central.state == .poweredOn else {
            fail("Bluetooth is not ready.", "bluetooth_unavailable")
            return
        }
        phase = .scanning
        message = "Ranking OFF→ON evidence. Only the prior physical UUID or FD50 + Tuya company evidence can authorize the target."
        log("power_on_scan_started")
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        central.stopScan()
        if selectedID == nil,
           let first = candidates.first(where: { $0.authoritativeTarget }) {
            choose(first)
        }
        if selectedID == nil {
            message = "No candidate has authoritative scooter evidence. Re-scan instead of guessing from name or RSSI."
        }
        log("scan_stopped")
    }

    func choose(_ candidate: Candidate) {
        guard candidate.authoritativeTarget else {
            message = "That candidate is ranking-only evidence. It cannot authorize the scooter target."
            return
        }
        central.stopScan()
        selectedID = candidate.id
        phase = .selected
        message = "Scooter target correlated. CoreBluetooth discovery is stopped before Tuya's SDK takes connection ownership."
        log(
            "candidate_selected",
            [
                "id": candidate.id.uuidString,
                "score": String(candidate.score),
                "evidence": candidate.evidence.joined(separator: ",")
            ]
        )
    }

    func authenticate() {
        Task { @MainActor [weak self] in
            await self?.beginAuthentication()
        }
    }

    private func beginAuthentication() async {
        guard let candidate = selected, candidate.authoritativeTarget else {
            fail("An authoritatively correlated scooter candidate is required.", "candidate_not_authoritative")
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
        guard sdkAccountAuthorized else {
            fail("The official Tuya SDK account session is not currently authorized.", "sdk_account_not_authorized")
            return
        }
        guard sdkDeviceMembershipAuthorized else {
            fail("The logged-in Tuya SDK account has not proven membership of the selected scooter device ID.", "sdk_device_membership_not_authorized")
            return
        }
        guard let newDriver = OfficialTuyaFactory.make() else {
            fail("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

        do {
            if let oldToken = connectionToken {
                try? await ledger.endConnection(for: oldToken)
            }
            let token = try await ledger.beginConnection()
            connectionToken = token
            try await ledger.markAuthenticationStarted(for: token)
            await refreshCanonicalAuthority()
        } catch {
            fail("Could not mint a fresh authenticated-session generation.", "preflight_generation_failed")
            return
        }

        central.stopScan()
        driver = newDriver
        sdkConnectCallbackSucceeded = false
        sdkLocalBLEOnline = false
        didMarkAuthenticated = false
        connectRequestedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        phase = .authenticating
        message = "Tuya's SDK is establishing the supported secure BLE session. Nembra sends no DP command."
        log(
            "official_connect_requested",
            [
                "coreBluetoothID": candidate.id.uuidString,
                "tuyaDeviceID": deviceID,
                "tuyaUUID": tuyaUUID,
                "productID": productID,
                "generation": String(connectionToken?.diagnosticGeneration ?? 0)
            ]
        )

        newDriver.connect(
            deviceID: deviceID,
            uuid: tuyaUUID,
            productID: productID,
            onApplicationUpdate: { [weak self] update in
                Task { @MainActor in
                    await self?.receivedApplicationUpdate(update)
                }
            },
            success: { [weak self] in
                Task { @MainActor in
                    await self?.officialSDKConnectReturnedSuccess()
                }
            },
            failure: { [weak self] reason in
                Task { @MainActor in
                    await self?.failAndRetire(reason, "official_connect_failed")
                }
            }
        )
    }

    private func officialSDKConnectReturnedSuccess() async {
        guard phase == .authenticating else {
            log("late_connect_success_ignored", ["phase": phase.rawValue])
            return
        }
        sdkConnectCallbackSucceeded = true
        phase = .observing
        message = "Tuya transport callback succeeded. Waiting for the SDK to report the scooter locally BLE-online before authentication chronology begins."
        log("official_connect_callback_succeeded")
        await sampleSDKConnectionAndAuthority()
        startWatchdog()
    }

    private func receivedApplicationUpdate(_ update: [String: String]) async {
        guard !update.isEmpty else { return }
        guard phase == .authenticating || phase == .observing || phase == .accepted else {
            log("late_application_update_ignored", ["phase": phase.rawValue])
            return
        }
        guard let driver, driver.isLocallyConnected(uuid: tuyaUUID) else {
            log("application_update_without_current_local_ble_ignored")
            return
        }
        guard let token = connectionToken else {
            log("application_update_without_generation_ignored")
            return
        }

        do {
            if !didMarkAuthenticated {
                try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                didMarkAuthenticated = true
                log("canonical_authenticated_observed", ["source": "sdk-local-ble-current"])
            }

            // The ledger intentionally does not retain this data. It only rejects empty evidence.
            // The marker is a deterministic encoding of a non-empty SDK DP callback, not raw FD50 bytes.
            let marker = try JSONSerialization.data(withJSONObject: update, options: [.sortedKeys])
            try await ledger.recordApplicationPayload(marker, for: token)
            log("tuya_application_update", update)
            await refreshCanonicalAuthority()
        } catch {
            log("application_update_rejected_by_canonical_ledger", ["error": String(describing: error)])
            return
        }

        applyCanonicalVerdictToProductState()
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.phase == .authenticating || self.phase == .observing else { return }

                await self.sampleSDKConnectionAndAuthority()
                if self.phase == .failed || self.phase == .accepted { return }

                if !self.didMarkAuthenticated,
                   let requestedAt = self.connectRequestedAtUptimeNanoseconds {
                    let now = DispatchTime.now().uptimeNanoseconds
                    if now >= requestedAt,
                       Double(now - requestedAt) / 1_000_000_000 > 15 {
                        await self.failAndRetire(
                            "Tuya's connect callback did not become an observed local BLE session within 15 seconds.",
                            "local_ble_never_became_current"
                        )
                        return
                    }
                }

                if self.didMarkAuthenticated,
                   self.preflightSnapshot.applicationPayloadCount == 0,
                   let age = self.authenticatedDurationSeconds,
                   age > 60 {
                    await self.failAndRetire(
                        "The authenticated local BLE session survived, but Tuya delivered no application update within 60 seconds.",
                        "no_application_updates"
                    )
                    return
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func sampleSDKConnectionAndAuthority() async {
        guard let driver, let token = connectionToken else { return }
        let locallyConnected = driver.isLocallyConnected(uuid: tuyaUUID)
        sdkLocalBLEOnline = locallyConnected

        do {
            if locallyConnected {
                if !didMarkAuthenticated {
                    try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    didMarkAuthenticated = true
                    log("canonical_authenticated_observed", ["source": "sdk-local-ble-current"])
                } else {
                    try await ledger.observeCurrentConnection(for: token)
                }
            } else if didMarkAuthenticated {
                await failAndRetire(
                    "Tuya's observed local BLE session dropped before canonical acceptance. Export diagnostics; do not repeat the outdoor ride capture.",
                    "sdk_local_ble_dropped"
                )
                return
            }
        } catch {
            await failAndRetire(
                "Canonical authenticated-session chronology rejected the latest SDK observation.",
                "canonical_chronology_rejected"
            )
            return
        }

        await refreshCanonicalAuthority()
        applyCanonicalVerdictToProductState()
    }

    private func refreshCanonicalAuthority() async {
        let snapshot = await preflightProvider.currentPreflightSnapshot()
        preflightSnapshot = snapshot
        canonicalVerdict = TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot)
    }

    private func applyCanonicalVerdictToProductState() {
        switch canonicalVerdict {
        case .readyForStationaryMapping:
            guard phase == .observing || phase == .authenticating else { return }
            phase = .accepted
            message = "AUTHENTICATED READ-ONLY GATE PASSED · current Tuya account/device authority, observed local BLE continuity, and genuine application evidence satisfy the canonical preflight."
            log(
                "canonical_acceptance_passed",
                [
                    "generation": String(preflightSnapshot.connectionGeneration),
                    "applicationPayloadCount": String(preflightSnapshot.applicationPayloadCount)
                ]
            )
            watchdog?.cancel()
        case let .blocked(reason):
            guard phase != .failed else { return }
            if preflightSnapshot.applicationPayloadCount > 0 {
                message = "Authenticated application data received. Canonical gate still blocked: \(reason)"
            } else if didMarkAuthenticated {
                message = "Observed local BLE authentication is current. Canonical gate still blocked: \(reason)"
            }
        }
    }

    func prepareExport() {
        let envelope = Export(
            schemaVersion: 4,
            purpose: "Sanitized canonical Tuya authenticated read-only preflight",
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
            sdkConnectCallbackSucceeded: sdkConnectCallbackSucceeded,
            sdkLocalBLEOnline: sdkLocalBLEOnline,
            canonicalConnectionGeneration: preflightSnapshot.connectionGeneration,
            canonicalAuthenticationState: authenticationStateDescription(preflightSnapshot.authenticationState),
            canonicalAuthenticationMethod: preflightSnapshot.authenticationMethod?.rawValue,
            canonicalAuthenticatedDurationSeconds: authenticatedDurationSeconds,
            canonicalApplicationPayloadCount: preflightSnapshot.applicationPayloadCount,
            canonicalVerdict: verdictDescription(canonicalVerdict),
            applicationValueRepresentation: "ThingSmartDeviceDelegate dpsUpdate values projected with String(describing:); application-level SDK evidence, not byte-exact or raw FD50 transport",
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
            message = accepted
                ? "Accepted canonical diagnostics are ready to share. SDK application values are string projections, not raw FD50 bytes."
                : "Blocked-state diagnostics are ready to share. The physical gate remains NO-GO."
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
        sdkConnectCallbackSucceeded = false
        sdkLocalBLEOnline = false
        didMarkAuthenticated = false
        connectRequestedAtUptimeNanoseconds = nil
        exportData = nil
        if let token = connectionToken {
            Task {
                try? await ledger.endConnection(for: token)
            }
        }
        connectionToken = nil
        preflightSnapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .unavailable(reason: "No active authenticated scooter session."),
            connectionStartedAtUptimeNanoseconds: nil,
            authenticatedAtUptimeNanoseconds: nil,
            latestObservedUptimeNanoseconds: nil,
            applicationPayloadCount: 0,
            connectionGeneration: 0
        )
        canonicalVerdict = .blocked(reason: "No active authenticated scooter session.")
    }

    private func fail(_ text: String, _ kind: String) {
        watchdog?.cancel()
        watchdog = nil
        phase = .failed
        message = text
        log(kind, ["message": sanitize(text)])
        let token = connectionToken
        connectionToken = nil
        if let token {
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await self.ledger.endConnection(for: token)
                await self.refreshCanonicalAuthority()
            }
        }
    }

    private func failAndRetire(_ text: String, _ kind: String) async {
        watchdog?.cancel()
        watchdog = nil
        phase = .failed
        message = text
        log(kind, ["message": sanitize(text)])
        if let token = connectionToken {
            try? await ledger.endConnection(for: token)
            connectionToken = nil
        }
        await refreshCanonicalAuthority()
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

    private func authenticationStateDescription(
        _ state: TuyaAuthenticatedReadOnlyPreflightSnapshot.AuthenticationState
    ) -> String {
        switch state {
        case let .unavailable(reason): return "unavailable: \(reason)"
        case .waitingForAuthentication: return "waiting-for-authentication"
        case .authenticating: return "authenticating"
        case .authenticated: return "authenticated"
        case let .failed(reason): return "failed: \(reason)"
        }
    }

    private func verdictDescription(_ verdict: TuyaAuthenticatedReadOnlyPreflight.Verdict) -> String {
        switch verdict {
        case .readyForStationaryMapping:
            return "ready-for-stationary-mapping"
        case let .blocked(reason):
            return "blocked: \(reason)"
        }
    }

    private static func hasTuyaCompanyID(_ data: Data?) -> Bool {
        guard let data, data.count >= 2 else { return false }
        return (UInt16(data[data.startIndex]) | UInt16(data[data.index(after: data.startIndex)]) << 8) == 0x07D0
    }

    private func updateCandidate(
        _ peripheral: CBPeripheral,
        advertisement: [String: Any],
        rssi number: NSNumber
    ) {
        let id = peripheral.identifier
        if phase == .baseline {
            baseline.insert(id)
        }

        let old = byID[id]
        let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? old?.name
        let rssi = number.intValue == 127 ? old?.rssi : number.intValue
        let serviceUUIDs =
            ((advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []) +
            ((advertisement[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []) +
            ((advertisement[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID]) ?? [])
        let serviceData = advertisement[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let fd50 = serviceUUIDs.contains(Self.fd50) || serviceData?.keys.contains(Self.fd50) == true || old?.fd50 == true
        let tuyaCompany = Self.hasTuyaCompanyID(advertisement[CBAdvertisementDataManufacturerDataKey] as? Data) || old?.tuyaCompany == true
        let knownID = id == Self.knownPeripheral
        let newAfterPowerOn = (phase == .scanning && !baseline.contains(id)) || old?.newAfterPowerOn == true
        let expectedName = name?.localizedCaseInsensitiveContains("demo") == true || name?.localizedCaseInsensitiveContains("tuya") == true || old?.expectedName == true

        var score = 0
        var evidence: [String] = []
        if knownID { score += 1000; evidence.append("known previous UUID") }
        if fd50 { score += 500; evidence.append("FD50") }
        if tuyaCompany { score += 350; evidence.append("Tuya company 0x07D0") }
        if newAfterPowerOn { score += 180; evidence.append("appeared after power-on") }
        if expectedName { score += 100; evidence.append("expected name") }
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
        guard phase == .baseline || phase == .scanning else { return }
        updateCandidate(peripheral, advertisement: advertisementData, rssi: RSSI)
    }
}

// MARK: - Official Tuya SDK adapter

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

    static var configured: Bool {
        compiled &&
        !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_KEY"] ?? "").isEmpty &&
        !(ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_SECRET"] ?? "").isEmpty
    }

    @discardableResult
    static func bootstrap() -> Bool {
#if canImport(ThingSmartHomeKit)
        guard configured else { return false }
        if didBootstrap { return true }
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["NEMBRA_TUYA_APP_KEY"], !key.isEmpty,
              let secret = environment["NEMBRA_TUYA_APP_SECRET"], !secret.isEmpty else {
            return false
        }
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
        guard OfficialTuyaFactory.bootstrap() else {
            failure("Private Tuya SDK credentials are missing.")
            return
        }

        self.onApplicationUpdate = onApplicationUpdate
        device = ThingSmartDevice(deviceId: deviceID)
        device?.delegate = self

        // ThingFailureHandler has no error payload for connectBLE in the documented API.
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
        var projected: [String: String] = [:]
        for (key, value) in dps {
            projected[String(describing: key)] = String(describing: value)
        }
        onApplicationUpdate?(projected)
    }
}
#endif

// MARK: - SDK account + exact device membership authority

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
    @Published private(set) var membershipVerdict: TuyaSDKAccountDeviceMembershipGate.Verdict =
        .blocked(reason: "Tuya SDK home/device membership has not been enumerated yet.")

    private let expectedDeviceID: String
#if canImport(ThingSmartHomeKit)
    private var homeManager: ThingSmartHomeManager?
    private var retainedHomes: [ThingSmartHome] = []
    private var pendingHomeLoads = 0
    private var pendingLoadedHomeCount = 0
    private var pendingHomeFailures = 0
    private var pendingOwnedIDs = Set<String>()
    private var pendingSharedIDs = Set<String>()
#endif

    init(expectedDeviceID: String) {
        self.expectedDeviceID = expectedDeviceID
    }

    var membershipAuthorized: Bool {
        if case .authorized = membershipVerdict { return true }
        return false
    }

    var membershipStatus: String {
        switch membershipVerdict {
        case .authorized:
            return "This exact scooter device ID is present in the logged-in Tuya SDK account."
        case let .blocked(reason):
            return reason
        }
    }

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
        if authorized {
            status = "Official Tuya SDK account session is authorized. Verifying this scooter is in the account…"
            refreshMembership()
        } else {
            membershipVerdict = .blocked(reason: "Tuya SDK account session is not logged in.")
            status = "SDK initialized. Sign in with a verification code; metadata QR approval does not count as BLE authentication authority."
        }
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

        let success = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.codeSent = true
                self.status = "Verification code sent by Tuya. Enter it below to authorize the SDK session."
            }
        }
        let failure: (Error?) -> Void = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                let raw = error?.localizedDescription ?? "unknown error"
                self.status = "Tuya could not send the verification code: \(self.redactAccountIdentifier(raw, identity: identity))"
            }
        }

        switch method {
        case .email:
            user?.sendVerifyCode(
                withUserName: identity,
                countryCode: country,
                type: 2,
                success: success,
                failure: failure
            )
        case .phone:
            let region = user?.getDefaultRegionWithCountryCode(country) ?? ""
            user?.sendVerifyCode(
                withUserName: identity,
                region: region,
                countryCode: country,
                type: 2,
                success: success,
                failure: failure
            )
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    func login() {
        bootstrap()
        guard !authorized else {
            refreshMembership()
            return
        }

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

        let success = { [weak self] in
            Task { @MainActor in
                self?.finishLoginSuccess()
            }
        }
        let failure: (Error?) -> Void = { [weak self] error in
            Task { @MainActor in
                self?.finishLoginFailure(error, identity: identity)
            }
        }

        switch method {
        case .email:
            ThingSmartUser.sharedInstance()?.login(
                withEmail: identity,
                countryCode: country,
                code: code,
                success: success,
                failure: failure
            )
        case .phone:
            ThingSmartUser.sharedInstance()?.login(
                withMobile: identity,
                countryCode: country,
                code: code,
                success: success,
                failure: failure
            )
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    func refreshMembership() {
        guard OfficialTuyaFactory.bootstrap(), OfficialTuyaFactory.accountReady else {
            authorized = false
            membershipVerdict = .blocked(reason: "Tuya SDK account session is not logged in.")
            status = "Authorize the official Tuya SDK account before checking scooter membership."
            return
        }

        authorized = true
        membershipVerdict = .blocked(reason: "Tuya SDK home/device membership is being enumerated.")

#if canImport(ThingSmartHomeKit)
        busy = true
        let manager = ThingSmartHomeManager()
        homeManager = manager
        retainedHomes.removeAll()
        pendingHomeLoads = 0
        pendingLoadedHomeCount = 0
        pendingHomeFailures = 0
        pendingOwnedIDs.removeAll()
        pendingSharedIDs.removeAll()

        manager.getHomeList(success: { [weak self] homes in
            Task { @MainActor in
                self?.beginHomeLoads(homes ?? [])
            }
        }, failure: { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.membershipVerdict = .blocked(reason: "Tuya SDK could not enumerate home/device membership.")
                self.status = "Scooter membership could not be verified. Bluetooth discovery stays locked."
            }
        })
#else
        busy = false
        membershipVerdict = .blocked(reason: "Official Tuya SmartLife SDK is not compiled into this build.")
#endif
    }

    private func finishLoginSuccess() {
        busy = false
        verificationCode = ""
        authorized = OfficialTuyaFactory.accountReady
        guard authorized else {
            membershipVerdict = .blocked(reason: "Tuya SDK login callback returned, but current SDK login authority is not present.")
            status = "Tuya returned a login success callback, but the SDK does not report a current logged-in session."
            return
        }
        status = "Official Tuya SDK account authorized. Verifying scooter membership…"
        refreshMembership()
    }

    private func finishLoginFailure(_ error: Error?, identity: String) {
        busy = false
        verificationCode = ""
        authorized = false
        membershipVerdict = .blocked(reason: "Tuya SDK account session is not logged in.")
        let raw = error?.localizedDescription ?? "unknown error"
        status = "Tuya SDK login failed: \(redactAccountIdentifier(raw, identity: identity))"
    }

    private func redactAccountIdentifier(_ text: String, identity: String) -> String {
        let trimmed = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        return text.replacingOccurrences(of: trimmed, with: "<account-redacted>")
    }

#if canImport(ThingSmartHomeKit)
    private func beginHomeLoads(_ homes: [ThingSmartHomeModel]) {
        pendingHomeLoads = homes.count
        if homes.isEmpty {
            finishMembershipEnumeration()
            return
        }

        for model in homes {
            guard let home = ThingSmartHome(homeId: model.homeId) else {
                pendingHomeFailures += 1
                pendingHomeLoads -= 1
                if pendingHomeLoads == 0 { finishMembershipEnumeration() }
                continue
            }

            retainedHomes.append(home)
            home.getDataWithSuccess({ [weak self, weak home] _ in
                Task { @MainActor in
                    guard let self, let home else { return }
                    self.pendingLoadedHomeCount += 1
                    for device in home.deviceList ?? [] {
                        let id = device.devId.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !id.isEmpty { self.pendingOwnedIDs.insert(id) }
                    }
                    for device in home.sharedDeviceList ?? [] {
                        let id = device.devId.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !id.isEmpty { self.pendingSharedIDs.insert(id) }
                    }
                    self.pendingHomeLoads -= 1
                    if self.pendingHomeLoads == 0 { self.finishMembershipEnumeration() }
                }
            }, failure: { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.pendingHomeFailures += 1
                    self.pendingHomeLoads -= 1
                    if self.pendingHomeLoads == 0 { self.finishMembershipEnumeration() }
                }
            })
        }
    }

    private func finishMembershipEnumeration() {
        busy = false
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: OfficialTuyaFactory.accountReady,
            homeEnumerationCompleted: true,
            loadedHomeCount: pendingLoadedHomeCount,
            ownedDeviceIDs: pendingOwnedIDs,
            sharedDeviceIDs: pendingSharedIDs,
            homeLoadFailureCount: pendingHomeFailures
        )
        membershipVerdict = TuyaSDKAccountDeviceMembershipGate.verdict(
            expectedDeviceID: expectedDeviceID,
            snapshot: snapshot
        )
        status = membershipAuthorized
            ? "Official Tuya SDK account and exact scooter membership are authorized."
            : "Account login succeeded, but scooter membership is not yet authoritative."
    }
#endif
}

// MARK: - Secure-link product surface

@MainActor
private struct SecureLinkView: View {
    @StateObject private var test: SecureLinkController
    @StateObject private var sdkAccount: OfficialTuyaAccountAuthorizer

    init(device: TuyaAccountBridge.LinkedDevice) {
        let authorizer = OfficialTuyaAccountAuthorizer(expectedDeviceID: device.id)
        _sdkAccount = StateObject(wrappedValue: authorizer)
        _test = StateObject(wrappedValue: SecureLinkController(device: device, accountAuthorizer: authorizer))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("SMALLEST INDOOR TEST")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.green)
                Text("Authenticate. Observe. Prove.")
                    .font(.largeTitle.bold())
                Text("Keep the scooter stationary. Do not run the old 17-step sequence.")
                    .foregroundStyle(.secondary)

                canonicalStatusCard
                sdkGateCard
                if test.sdkCompiled && test.privateConfig && !sdkAccount.authorized {
                    sdkAuthorizationCard
                }
                if sdkAccount.authorized && !sdkAccount.membershipAuthorized {
                    membershipCard
                }
                discoveryCard
                if let candidate = test.selected {
                    authenticationCard(candidate)
                }
                acceptanceCard
                exportCard
            }
            .frame(maxWidth: 760)
            .padding(18)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Secure Link")
        .task {
            sdkAccount.bootstrap()
        }
    }

    private var canonicalStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(test.accepted ? "Canonical secure-link gate passed" : test.phase == .failed ? "Secure-link test stopped" : "Canonical authentication preflight")
                    .font(.headline)
                Spacer()
                Text("G\(test.preflightSnapshot.connectionGeneration)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text(test.message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let age = test.authenticatedDurationSeconds {
                LabeledContent("Observed authenticated continuity", value: String(format: "%.1f s", age))
                ProgressView(value: min(age / 45, 1))
            }

            LabeledContent("Tuya local BLE", value: test.sdkLocalBLEOnline ? "Observed online" : "Not current")
            LabeledContent("Canonical application evidence", value: String(test.preflightSnapshot.applicationPayloadCount))
            if let reason = test.canonicalBlockReason, !test.accepted {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .captureCard()
    }

    private var sdkGateCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Official Tuya authority", systemImage: "checkmark.shield")
                .font(.headline)
            LabeledContent("SDK compiled in", value: test.sdkCompiled ? "Yes" : "No")
            LabeledContent("Private app config", value: test.privateConfig ? "Yes" : "No")
            LabeledContent("SDK account current", value: test.sdkAccountAuthorized ? "Yes" : "No")
            LabeledContent("Exact scooter in SDK account", value: test.sdkDeviceMembershipAuthorized ? "Yes" : "No")

            if !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized || !test.sdkDeviceMembershipAuthorized {
                Text("NO PHYSICAL TEST YET: the official SDK/security component, private app credentials, current SDK login, and exact scooter membership must all be authoritative before Bluetooth discovery begins.")
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            }
        }
        .captureCard()
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

            Text("Nembra does not ask for or persist the Tuya account password. Verification codes stay in memory and are cleared after the login attempt; account identifiers are scrubbed from SDK error text before display.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .captureCard()
    }

    private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Verify this scooter belongs to the SDK account", systemImage: "person.text.rectangle")
                .font(.headline)
            Text(sdkAccount.membershipStatus)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(sdkAccount.busy ? "Checking homes…" : "Refresh scooter membership") {
                sdkAccount.refreshMembership()
            }
            .buttonStyle(.borderedProminent)
            .disabled(sdkAccount.busy)
        }
        .captureCard()
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Find the known scooter", systemImage: "scope")
                .font(.headline)

            switch test.phase {
            case .idle, .failed:
                Button("Start scooter-OFF baseline") {
                    test.startBaseline()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!test.sdkAccountAuthorized || !test.sdkDeviceMembershipAuthorized)
            case .baseline:
                Button("Save OFF baseline") {
                    test.saveBaseline()
                }
                .buttonStyle(.borderedProminent)
            case .powerOn:
                Text("Turn scooter ON, keep it still.")
                    .foregroundStyle(.secondary)
                Button("Scan after power-on") {
                    test.scanAfterPowerOn()
                }
                .buttonStyle(.borderedProminent)
            case .scanning:
                Button("Stop scan / use authoritative evidence") {
                    test.stopScan()
                }
                .buttonStyle(.bordered)
            default:
                EmptyView()
            }

            ForEach(test.candidates.prefix(8)) { candidate in
                Button {
                    test.choose(candidate)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(candidate.title).bold()
                            if candidate.authoritativeTarget {
                                Text("TARGET EVIDENCE")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.green, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            Spacer()
                            Text("\(candidate.score)")
                                .monospacedDigit()
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
                .disabled(!candidate.authoritativeTarget)
            }
        }
        .captureCard()
    }

    private func authenticationCard(_ candidate: SecureLinkController.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Authentication gate", systemImage: "key.horizontal")
                .font(.headline)
            Text(candidate.evidence.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Start secure read-only test") {
                test.authenticate()
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                !candidate.authoritativeTarget ||
                !test.sdkCompiled ||
                !test.privateConfig ||
                !test.sdkAccountAuthorized ||
                !test.sdkDeviceMembershipAuthorized ||
                test.phase == .authenticating ||
                test.phase == .observing ||
                test.phase == .accepted
            )
        }
        .captureCard()
    }

    private var acceptanceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Acceptance", systemImage: test.accepted ? "checkmark.seal.fill" : "hourglass")
                .font(.headline)
                .foregroundStyle(test.accepted ? .green : .white)

            Text("Only the canonical NembraBluetoothCapture preflight can promote this screen to accepted. It requires a current connection generation, accepted Tuya SDK authentication provenance, at least one genuine application update, valid monotonic chronology, and more than 45 seconds of observed authenticated continuity.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if test.accepted {
                Text("AUTHENTICATED READ-ONLY GATE PASSED\nReady to plan the smallest stationary mapping step")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
            }
        }
        .captureCard()
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Prepare sanitized diagnostic JSON") {
                test.prepareExport()
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

            Text("Export records canonical generation/provenance/chronology and projected SDK application evidence. It does not claim raw FD50 bytes and excludes passwords, verification codes, account tokens, local_key, AppKey and AppSecret.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .captureCard()
    }
}

private struct SecureTransfer: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { transfer in
            transfer.data
        }
        .suggestedFileName { transfer in
            transfer.name
        }
    }
}

private extension View {
    func captureCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}
