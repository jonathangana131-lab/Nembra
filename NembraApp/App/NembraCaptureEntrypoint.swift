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

                    Text("The next physical run is stationary. It proves current Tuya account/device authority, a supported local BLE session that remains observed for more than 45 seconds, and at least one genuine Tuya application update. The old 17-step ride sequence stays disabled until this gate passes.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Read-only control boundary", systemImage: "shield.checkered")
                            .font(.headline)
                        Text("CoreBluetooth is used only to correlate the already-observed scooter. Once selected, Tuya's official SDK is the sole authenticated BLE owner.")
                            .foregroundStyle(.secondary)
                        Text("No generic BLE write, DP publish/query, unbind, reset, pair, lock, speed, light, mode, throttle, brake, or firmware command is exposed here.")
                            .font(.footnote.bold())
                            .foregroundStyle(.green)
                    }
                    .captureCard()

                    accountCard
                    if tuya.isLinked {
                        devicesCard
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
            Label("1 · Identify the bound Tuya device", systemImage: "person.badge.key")
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

    private var devicesCard: some View {
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

            Text("Only device identity enters the secure-link path. local_key never becomes Nembra BLE authentication material.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .captureCard()
    }
}

// MARK: - Canonical session controller

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

        /// Ranking hints never become identity authority.
        /// The first field run physically established the prior CoreBluetooth UUID; otherwise
        /// this conservative fallback requires both FD50 and Tuya company evidence.
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
        let canonicalApplicationUpdateCount: Int
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
    @Published private(set) var message = "Authorize the official Tuya SDK account and exact scooter membership before Bluetooth discovery."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var sdkConnectCallbackSucceeded = false
    @Published private(set) var sdkLocalBLEOnline = false
    @Published private(set) var snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
        authenticationState: .unavailable(reason: "No active authenticated scooter session."),
        connectionStartedAtUptimeNanoseconds: nil,
        authenticatedAtUptimeNanoseconds: nil,
        latestObservedUptimeNanoseconds: nil,
        applicationPayloadCount: 0,
        connectionGeneration: 0
    )
    @Published private(set) var verdict: TuyaAuthenticatedReadOnlyPreflight.Verdict =
        .blocked(reason: "No active authenticated scooter session.")
    @Published private(set) var exportData: Data?
    @Published private(set) var exportName = "Nembra-Secure-Link-Diagnostics.json"

    let deviceID: String
    let productID: String
    let tuyaUUID: String

    private let account: OfficialTuyaAccountAuthorizer
    private let ledger = TuyaAuthenticatedReadOnlySessionLedger()
    private var token: TuyaReadOnlyConnectionToken?
    private var central: CBCentralManager!
    private var byID: [UUID: Candidate] = [:]
    private var baseline = Set<UUID>()
    private var driver: OfficialTuyaDriver?
    private var didObserveAuthenticatedLocalBLE = false
    private var connectRequestedAtUptimeNanoseconds: UInt64?
    private var events: [Event] = []
    private var watchdog: Task<Void, Never>?

    init(device: TuyaAccountBridge.LinkedDevice, account: OfficialTuyaAccountAuthorizer) {
        self.account = account
        self.deviceID = device.id
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
    var sdkAccountAuthorized: Bool { account.authorized && OfficialTuyaFactory.accountLoggedIn }
    var sdkDeviceMembershipAuthorized: Bool { account.membershipAuthorized }
    var selected: Candidate? { selectedID.flatMap { byID[$0] } }

    var accepted: Bool {
        guard phase == .accepted else { return false }
        if case .readyForStationaryMapping = verdict { return true }
        return false
    }

    var authenticatedDurationSeconds: Double? {
        guard let authenticatedAt = snapshot.authenticatedAtUptimeNanoseconds,
              let latest = snapshot.latestObservedUptimeNanoseconds,
              latest >= authenticatedAt else {
            return nil
        }
        return Double(latest - authenticatedAt) / 1_000_000_000
    }

    var blockReason: String? {
        if case let .blocked(reason) = verdict { return reason }
        return nil
    }

    func startBaseline() {
        guard sdkAccountAuthorized else {
            fail("Authorize the current official Tuya SDK account before Bluetooth discovery.", "sdk_account_not_authorized")
            return
        }
        guard sdkDeviceMembershipAuthorized else {
            fail("Verify that this exact scooter is in the current Tuya SDK account before Bluetooth discovery.", "sdk_device_membership_not_authorized")
            return
        }
        guard central.state == .poweredOn else {
            fail("Bluetooth is not ready.", "bluetooth_unavailable")
            return
        }

        resetAttemptForDiscovery()
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
            fail("Tuya account/device authority changed before the ON scan.", "sdk_authority_changed")
            return
        }
        guard central.state == .poweredOn else {
            fail("Bluetooth is not ready.", "bluetooth_unavailable")
            return
        }

        phase = .scanning
        message = "Ranking OFF→ON observations. Name and RSSI are hints only; they cannot authorize the target."
        log("power_on_scan_started")
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        central.stopScan()
        if selectedID == nil,
           let authoritative = candidates.first(where: { $0.authoritativeTarget }) {
            choose(authoritative)
        }
        if selectedID == nil {
            message = "No candidate has authoritative scooter evidence. Re-scan instead of guessing from name or RSSI."
        }
        log("scan_stopped")
    }

    func choose(_ candidate: Candidate) {
        guard candidate.authoritativeTarget else {
            message = "That candidate has ranking evidence only. It cannot authorize the scooter target."
            return
        }
        central.stopScan()
        selectedID = candidate.id
        phase = .selected
        message = "Scooter target correlated. CoreBluetooth is stopped before Tuya's SDK takes authenticated BLE ownership."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "score": String(candidate.score),
            "evidence": candidate.evidence.joined(separator: ",")
        ])
    }

    func authenticate() {
        Task { @MainActor [weak self] in
            await self?.beginAuthentication()
        }
    }

    private func beginAuthentication() async {
        guard let candidate = selected, candidate.authoritativeTarget else {
            fail("An authoritatively correlated scooter target is required.", "candidate_not_authoritative")
            return
        }
        guard sdkCompiled, privateConfig else {
            fail("Official Tuya SDK/security configuration is unavailable. Do not run the physical test yet.", "sdk_unavailable")
            return
        }
        guard sdkAccountAuthorized, sdkDeviceMembershipAuthorized else {
            fail("Current Tuya SDK account/device authority is not valid.", "sdk_authority_not_current")
            return
        }
        guard !deviceID.isEmpty, !tuyaUUID.isEmpty, !productID.isEmpty else {
            fail("Tuya device ID, UUID, or product ID is incomplete.", "tuya_identity_incomplete")
            return
        }
        guard let newDriver = OfficialTuyaFactory.make() else {
            fail("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

        do {
            if let oldToken = token {
                try? await ledger.endConnection(for: oldToken)
            }
            let freshToken = try await ledger.beginConnection()
            token = freshToken
            try await ledger.markAuthenticationStarted(for: freshToken)
            await refreshAuthority()
        } catch {
            fail("Could not create a fresh canonical connection generation.", "canonical_generation_failed")
            return
        }

        central.stopScan()
        driver = newDriver
        sdkConnectCallbackSucceeded = false
        sdkLocalBLEOnline = false
        didObserveAuthenticatedLocalBLE = false
        connectRequestedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        phase = .authenticating
        message = "Tuya's official SDK is establishing the supported read-only session."
        log("official_connect_requested", [
            "coreBluetoothID": candidate.id.uuidString,
            "generation": String(token?.diagnosticGeneration ?? 0)
        ])

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
                    await self?.officialConnectSucceeded()
                }
            },
            failure: { [weak self] reason in
                Task { @MainActor in
                    await self?.failAndRetire(reason, kind: "official_connect_failed")
                }
            }
        )
    }

    private func officialConnectSucceeded() async {
        guard phase == .authenticating else {
            log("late_connect_success_ignored", ["phase": phase.rawValue])
            return
        }
        sdkConnectCallbackSucceeded = true
        phase = .observing
        message = "Tuya transport callback succeeded. Waiting for the SDK to prove this scooter locally BLE-online."
        log("official_connect_callback_succeeded")
        await sampleConnection()
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
        guard let token else {
            log("application_update_without_generation_ignored")
            return
        }

        do {
            if !didObserveAuthenticatedLocalBLE {
                try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                didObserveAuthenticatedLocalBLE = true
                log("canonical_authenticated_observed", ["source": "sdk-local-ble-current"])
            }
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
            await refreshAuthority()
            log("tuya_application_update", update)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        } catch {
            await failAndRetire("Canonical chronology rejected the application update.", kind: "canonical_update_rejected")
            return
        }

        applyVerdict()
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.phase == .authenticating || self.phase == .observing else { return }

                await self.sampleConnection()
                if self.phase == .accepted || self.phase == .failed { return }

                if !self.didObserveAuthenticatedLocalBLE,
                   let requestedAt = self.connectRequestedAtUptimeNanoseconds {
                    let now = DispatchTime.now().uptimeNanoseconds
                    if now >= requestedAt,
                       Double(now - requestedAt) / 1_000_000_000 > 15 {
                        await self.failAndRetire(
                            "Tuya's connect callback never became a currently observed local BLE session.",
                            kind: "local_ble_never_current"
                        )
                        return
                    }
                }

                if self.didObserveAuthenticatedLocalBLE,
                   self.snapshot.applicationPayloadCount == 0,
                   let age = self.authenticatedDurationSeconds,
                   age > 60 {
                    await self.failAndRetire(
                        "The authenticated local BLE session survived, but Tuya delivered no application update within 60 seconds.",
                        kind: "no_application_updates"
                    )
                    return
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func sampleConnection() async {
        guard let driver, let token else { return }
        let online = driver.isLocallyConnected(uuid: tuyaUUID)
        sdkLocalBLEOnline = online

        do {
            if online {
                if !didObserveAuthenticatedLocalBLE {
                    try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    didObserveAuthenticatedLocalBLE = true
                    log("canonical_authenticated_observed", ["source": "sdk-local-ble-current"])
                } else {
                    try await ledger.observeCurrentConnection(for: token)
                }
            } else if didObserveAuthenticatedLocalBLE {
                await failAndRetire(
                    "Tuya's observed local BLE session dropped before canonical acceptance. Export diagnostics; do not repeat the outdoor ride capture.",
                    kind: "sdk_local_ble_dropped"
                )
                return
            }
        } catch {
            await failAndRetire(
                "Canonical authenticated-session chronology rejected the latest SDK observation.",
                kind: "canonical_chronology_rejected"
            )
            return
        }

        await refreshAuthority()
        applyVerdict()
    }

    private func refreshAuthority() async {
        snapshot = await ledger.currentPreflightSnapshot()
        verdict = TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot)
    }

    private func applyVerdict() {
        switch verdict {
        case .readyForStationaryMapping:
            guard phase == .observing || phase == .authenticating else { return }
            phase = .accepted
            message = "AUTHENTICATED READ-ONLY GATE PASSED · canonical chronology, current local BLE, and genuine application evidence are accepted."
            log("canonical_acceptance_passed", [
                "generation": String(snapshot.connectionGeneration),
                "applicationUpdates": String(snapshot.applicationPayloadCount)
            ])
            watchdog?.cancel()
        case let .blocked(reason):
            guard phase != .failed else { return }
            if snapshot.applicationPayloadCount > 0 {
                message = "Authenticated application data received. Canonical gate still blocked: \(reason)"
            } else if didObserveAuthenticatedLocalBLE {
                message = "Current local BLE authentication is observed. Canonical gate still blocked: \(reason)"
            }
        }
    }

    func prepareExport() {
        let envelope = Export(
            schemaVersion: 5,
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
            canonicalConnectionGeneration: snapshot.connectionGeneration,
            canonicalAuthenticationState: authenticationStateDescription(snapshot.authenticationState),
            canonicalAuthenticationMethod: snapshot.authenticationMethod?.rawValue,
            canonicalAuthenticatedDurationSeconds: authenticatedDurationSeconds,
            canonicalApplicationUpdateCount: snapshot.applicationPayloadCount,
            canonicalVerdict: verdictDescription(verdict),
            applicationValueRepresentation: "ThingSmartDeviceDelegate dpsUpdate string projection; application-level SDK evidence, not byte-exact/raw FD50 transport",
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
                ? "Accepted canonical diagnostics are ready to share. Application values are SDK projections, not raw FD50 bytes."
                : "Blocked-state diagnostics are ready to share. The physical gate remains NO-GO."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    private func fail(_ text: String, _ kind: String) {
        watchdog?.cancel()
        watchdog = nil
        phase = .failed
        message = text
        log(kind, ["message": sanitize(text)])
    }

    private func failAndRetire(_ text: String, kind: String) async {
        watchdog?.cancel()
        watchdog = nil
        phase = .failed
        message = text
        log(kind, ["message": sanitize(text)])
        if let token {
            try? await ledger.endConnection(for: token)
            self.token = nil
        }
        await refreshAuthority()
    }

    private func resetAttemptForDiscovery() {
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
        didObserveAuthenticatedLocalBLE = false
        connectRequestedAtUptimeNanoseconds = nil
        exportData = nil
        if let token {
            let oldToken = token
            self.token = nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await self.ledger.endConnection(for: oldToken)
                await self.refreshAuthority()
            }
        }
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
        case .readyForStationaryMapping: return "ready-for-stationary-mapping"
        case let .blocked(reason): return "blocked: \(reason)"
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
        if phase == .baseline { baseline.insert(id) }

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

// MARK: - Official Tuya SDK

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

// MARK: - Official account + exact device membership

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
    private var membershipProbe: OfficialTuyaMembershipProbe?
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
            authorized = false
            status = "Official Tuya SmartLife SDK is not compiled into this build."
            return
        }
        guard OfficialTuyaFactory.configured else {
            authorized = false
            status = "Private Tuya AppKey/AppSecret are not provisioned for this build."
            return
        }
        guard OfficialTuyaFactory.bootstrap() else {
            authorized = false
            status = "Tuya SDK initialization failed closed."
            return
        }

        authorized = OfficialTuyaFactory.accountLoggedIn
        if authorized {
            status = "Official Tuya SDK account is current. Verifying exact scooter membership…"
            refreshMembership()
        } else {
            membershipVerdict = .blocked(reason: "Tuya SDK account session is not logged in.")
            status = "SDK initialized. Sign in with a verification code; metadata QR approval is not BLE authentication authority."
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
        guard OfficialTuyaFactory.bootstrap(), OfficialTuyaFactory.accountLoggedIn else {
            authorized = false
            membershipVerdict = .blocked(reason: "Tuya SDK account session is not logged in.")
            status = "Authorize the official Tuya SDK account before checking scooter membership."
            return
        }
        authorized = true
        membershipVerdict = .blocked(reason: "Tuya SDK home/device membership is being enumerated.")

#if canImport(ThingSmartHomeKit)
        busy = true
        let probe = OfficialTuyaMembershipProbe(expectedDeviceID: expectedDeviceID) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.membershipProbe = nil
                self.membershipVerdict = result.verdict
                self.status = self.membershipAuthorized
                    ? "Official Tuya SDK account and exact scooter membership are authorized."
                    : "Account login succeeded, but exact scooter membership is not authoritative."
            }
        }
        membershipProbe = probe
        probe.start()
#else
        busy = false
        membershipVerdict = .blocked(reason: "Official Tuya SmartLife SDK is not compiled into this build.")
#endif
    }

    private func finishLoginSuccess() {
        busy = false
        verificationCode = ""
        authorized = OfficialTuyaFactory.accountLoggedIn
        guard authorized else {
            membershipVerdict = .blocked(reason: "Tuya SDK login callback returned, but current SDK login authority is absent.")
            status = "Tuya returned a login callback, but the SDK does not report a current logged-in session."
            return
        }
        status = "Official Tuya SDK account authorized. Verifying exact scooter membership…"
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
}

#if canImport(ThingSmartHomeKit)
@MainActor
private final class OfficialTuyaMembershipProbe {
    struct Result {
        let verdict: TuyaSDKAccountDeviceMembershipGate.Verdict
    }

    private let expectedDeviceID: String
    private let completion: (Result) -> Void
    private let manager = ThingSmartHomeManager()
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

        manager.getHomeList(success: { [weak self] homes in
            Task { @MainActor in
                guard let self else { return }
                self.homes = homes ?? []
                self.loadNextHome()
            }
        }, failure: { [weak self] _ in
            Task { @MainActor in
                self?.finish(enumerationCompleted: false)
            }
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
            )
        ))
    }
}
#endif

// MARK: - Product surface

@MainActor
private struct SecureLinkView: View {
    @StateObject private var account: OfficialTuyaAccountAuthorizer
    @StateObject private var test: SecureLinkController

    init(device: TuyaAccountBridge.LinkedDevice) {
        let authorizer = OfficialTuyaAccountAuthorizer(expectedDeviceID: device.id)
        _account = StateObject(wrappedValue: authorizer)
        _test = StateObject(wrappedValue: SecureLinkController(device: device, account: authorizer))
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

                statusCard
                authorityCard

                if test.sdkCompiled && test.privateConfig && !account.authorized {
                    loginCard
                }
                if account.authorized && !account.membershipAuthorized {
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
            account.bootstrap()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(test.accepted ? "Canonical secure-link gate passed" : test.phase == .failed ? "Secure-link test stopped" : "Canonical authentication preflight")
                    .font(.headline)
                Spacer()
                Text("G\(test.snapshot.connectionGeneration)")
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
            LabeledContent("Canonical application updates", value: String(test.snapshot.applicationPayloadCount))
            if let reason = test.blockReason, !test.accepted {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .captureCard()
    }

    private var authorityCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Official Tuya authority", systemImage: "checkmark.shield")
                .font(.headline)
            LabeledContent("SDK compiled in", value: test.sdkCompiled ? "Yes" : "No")
            LabeledContent("Private app config", value: test.privateConfig ? "Yes" : "No")
            LabeledContent("SDK account current", value: test.sdkAccountAuthorized ? "Yes" : "No")
            LabeledContent("Exact scooter in SDK account", value: test.sdkDeviceMembershipAuthorized ? "Yes" : "No")

            if !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized || !test.sdkDeviceMembershipAuthorized {
                Text("NO PHYSICAL TEST YET: private SDK provisioning, a current SDK account session, and exact scooter membership must be authoritative before Bluetooth discovery begins.")
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            }
        }
        .captureCard()
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Authorize the official SDK account", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            Text(account.status)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Login method", selection: $account.method) {
                ForEach(OfficialTuyaAccountAuthorizer.LoginMethod.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)

            TextField("Country code (for example 1)", text: $account.countryCode)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

            TextField(
                account.method == .email ? "Tuya account email" : "Tuya account phone number",
                text: $account.account
            )
            .keyboardType(account.method == .email ? .emailAddress : .phonePad)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .privacySensitive()
            .padding(10)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

            Button(account.busy ? "Contacting Tuya…" : "Send login code") {
                account.sendCode()
            }
            .buttonStyle(.bordered)
            .disabled(account.busy)

            if account.codeSent {
                SecureField("Verification code", text: $account.verificationCode)
                    .keyboardType(.numberPad)
                    .privacySensitive()
                    .padding(10)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

                Button("Authorize SDK account") {
                    account.login()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    account.busy ||
                    account.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            Text("Nembra never asks for the account password. Verification codes remain in memory only and are cleared after login; submitted email/phone text is removed from SDK error messages before display.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .captureCard()
    }

    private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Verify this scooter in the SDK account", systemImage: "person.text.rectangle")
                .font(.headline)
            Text(account.membershipStatus)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(account.busy ? "Checking homes…" : "Refresh scooter membership") {
                account.refreshMembership()
            }
            .buttonStyle(.borderedProminent)
            .disabled(account.busy)
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

            Text("Only NembraBluetoothCapture's canonical preflight verdict can promote this surface. It requires current Tuya SDK authentication provenance, a current connection generation, genuine same-generation application evidence, monotonic chronology, and the full authenticated observation window.")
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

            Text("Export records canonical chronology and SDK-projected application values. It does not claim raw FD50 bytes and excludes passwords, verification codes, account tokens, local_key, AppKey, and AppSecret.")
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
