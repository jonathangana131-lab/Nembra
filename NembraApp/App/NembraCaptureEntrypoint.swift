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
    var body: some Scene {
        WindowGroup {
            CaptureP0Root()
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
private final class TuyaSDKAccountGate: ObservableObject {
    @Published private(set) var isInitialized = false
    @Published private(set) var isLoggedIn = false
    @Published private(set) var isBusy = false
    @Published private(set) var codeRequested = false
    @Published private(set) var message = "Checking the official Tuya SDK account gate…"

    var compiled: Bool { OfficialTuyaFactory.compiled }
    var configured: Bool { OfficialTuyaFactory.configured }

    init() {
        bootstrap()
    }

    func bootstrap() {
#if canImport(ThingSmartHomeKit)
        guard let key = OfficialTuyaFactory.privateCredential(named: "NEMBRA_TUYA_APP_KEY"),
              let secret = OfficialTuyaFactory.privateCredential(named: "NEMBRA_TUYA_APP_SECRET") else {
            isInitialized = false
            isLoggedIn = false
            message = "Private Tuya AppKey/AppSecret are not injected into this exact field build."
            return
        }

        // Initialization intentionally happens before the first account-authority read.
        ThingSmartSDK.sharedInstance()?.start(withAppKey: key, secretKey: secret)
        isInitialized = true
        isLoggedIn = ThingSmartUser.sharedInstance()?.isLogin == true
        message = isLoggedIn
            ? "Official Tuya SDK initialized and its account session is authorized."
            : "Official Tuya SDK initialized. Authorize the account with a one-time email code."
#else
        isInitialized = false
        isLoggedIn = false
        message = "ThingSmartHomeKit is not compiled into this field build."
#endif
    }

    func requestEmailCode(countryCode: String, email: String) {
        bootstrap()
        guard isInitialized, !isLoggedIn, !isBusy else { return }
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !country.isEmpty, address.contains("@") else {
            message = "Enter the Tuya account email and country code first."
            return
        }

#if canImport(ThingSmartHomeKit)
        guard let user = ThingSmartUser.sharedInstance() else {
            message = "Tuya account service is unavailable in this build."
            return
        }
        isBusy = true
        message = "Requesting a one-time login code from Tuya…"
        user.sendVerifyCode(withUserName: address, countryCode: country, type: 2) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false
                self.codeRequested = true
                self.message = "Tuya sent a login code. Enter that code below; Nembra does not need your reusable Tuya password."
            }
        } failure: { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false
                self.codeRequested = false
                self.message = "Tuya could not send the login code: \(error?.localizedDescription ?? "unknown error")"
            }
        }
#endif
    }

    func loginWithEmailCode(countryCode: String, email: String, code: String) {
        bootstrap()
        guard isInitialized, !isLoggedIn, !isBusy else { return }
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let oneTimeCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !country.isEmpty, address.contains("@"), !oneTimeCode.isEmpty else {
            message = "Email, country code, and the one-time login code are required."
            return
        }

#if canImport(ThingSmartHomeKit)
        guard let user = ThingSmartUser.sharedInstance() else {
            message = "Tuya account service is unavailable in this build."
            return
        }
        isBusy = true
        message = "Authorizing the official SDK session with the one-time code…"
        user.login(withEmail: address, countryCode: country, code: oneTimeCode) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false
                self.isLoggedIn = ThingSmartUser.sharedInstance()?.isLogin == true
                self.codeRequested = false
                self.message = self.isLoggedIn
                    ? "Official Tuya SDK account authorized. Secure BLE can now be attempted."
                    : "Tuya returned login success, but no authorized SDK account session is visible. Secure BLE stays locked."
            }
        } failure: { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isBusy = false
                self.isLoggedIn = false
                self.message = "Official Tuya code login failed: \(error?.localizedDescription ?? "unknown error")"
            }
        }
#endif
    }
}

@MainActor
private struct CaptureP0Root: View {
    @StateObject private var tuya = TuyaAccountBridge()
    @StateObject private var sdk = TuyaSDKAccountGate()
    @State private var countryCode = "1"
    @State private var email = ""
    @State private var verificationCode = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("P0 · TUYA AUTHENTICATION")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.green)
                    Text("Prove the secure scooter link first.")
                        .font(.largeTitle.bold())
                    Text("The next physical run is stationary. It proves supported Tuya authentication, >45 s continuity, and genuine application updates through Tuya's own SDK. The old 17-step ride sequence stays disabled until this passes.")
                        .foregroundStyle(.secondary)

                    safetyCard
                    sdkAccountCard
                    metadataAccountCard
                    if tuya.isLinked { deviceCard }
                }
                .frame(maxWidth: 760)
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Nembra Capture")
            .onAppear { sdk.bootstrap() }
        }
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Read-only control boundary", systemImage: "shield.checkered")
                .font(.headline)
            Text("Account linking is used for ownership/device identity. Nembra does not turn local_key into a BLE login key, synthesize Tuya authentication frames, or open a second CoreBluetooth connection after the official SDK takes ownership.")
                .foregroundStyle(.secondary)
            Text("No unbind, reset, lock, speed, light, mode, throttle, brake, firmware, DP query, or DP control command is sent.")
                .font(.footnote.bold())
                .foregroundStyle(.green)
        }
        .card()
    }

    private var sdkAccountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("1 · Authorize the official Tuya SDK", systemImage: "person.badge.key")
                .font(.headline)
            LabeledContent("SDK compiled", value: sdk.compiled ? "Yes" : "No")
            LabeledContent("Private app config", value: sdk.configured ? "Injected" : "Missing")
            LabeledContent("SDK initialized", value: sdk.isInitialized ? "Yes" : "No")
            LabeledContent("SDK account", value: sdk.isLoggedIn ? "Authorized" : "Not authorized")
            Text(sdk.message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if sdk.isInitialized && !sdk.isLoggedIn {
                TextField("Country code, e.g. 1", text: $countryCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                TextField("Tuya account email", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Button(sdk.isBusy ? "Requesting…" : "Send one-time login code") {
                    verificationCode = ""
                    sdk.requestEmailCode(countryCode: countryCode, email: email)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sdk.isBusy || email.isEmpty || countryCode.isEmpty)

                if sdk.codeRequested {
                    TextField("One-time code", text: $verificationCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button(sdk.isBusy ? "Authorizing…" : "Authorize SDK session") {
                        let code = verificationCode
                        verificationCode = ""
                        sdk.loginWithEmailCode(countryCode: countryCode, email: email, code: code)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sdk.isBusy || verificationCode.isEmpty)
                }

                Text("This path uses Tuya's verification-code login. Nembra does not collect or retain the reusable Tuya account password, and the one-time code is cleared from the field immediately after submission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var metadataAccountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2 · Identify your already-bound Tuya device", systemImage: "qrcode.viewfinder")
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
                Button("Create metadata approval QR") { tuya.requestApproval() }
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
                Button("I approved it · check now") { tuya.checkApprovalNow() }
                    .buttonStyle(.bordered)
            }
            if tuya.phase == .failed {
                Button("Reset metadata account link") { tuya.resetLink() }
                    .buttonStyle(.bordered)
            }
            Text("This QR path is metadata/ownership discovery only. It cannot satisfy the official SDK authentication gate above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("3 · Choose the scooter", systemImage: "bicycle")
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
                            NavigationLink("Secure stationary test") {
                                SecureLinkView(device: device)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!sdk.isLoggedIn)
                        }
                    }
                }
                .padding(12)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            if !sdk.isLoggedIn {
                Label("Secure test stays locked until the official SDK account is authorized.", systemImage: "lock.fill")
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            }
            Text("Only Tuya device ID, device UUID, and product ID enter the supported secure-link controller. local_key does not.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

private actor FieldTuyaPreflightProvider: TuyaReadOnlyAuthenticationSessionProvider {
    private var snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
        authenticationState: .waitingForAuthentication,
        authenticationMethod: nil,
        connectionStartedAtUptimeNanoseconds: nil,
        authenticatedAtUptimeNanoseconds: nil,
        latestObservedUptimeNanoseconds: nil,
        applicationPayloadCount: 0,
        latestApplicationPayloadUptimeNanoseconds: nil,
        connectionGeneration: 0
    )

    func replace(with snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot) {
        self.snapshot = snapshot
    }

    func currentPreflightSnapshot() async -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        snapshot
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
        var likely: Bool { knownID || (fd50 && tuyaCompany) || score >= 600 }
    }

    enum Phase: String, Codable {
        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed
    }

    struct Event: Codable {
        let at: Date
        let uptimeNanoseconds: UInt64
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
        let authenticationMethod: String?
        let connectionGeneration: UInt64
        let authenticatedDurationSeconds: Double?
        let sdkLocalBLEOnline: Bool
        let applicationUpdateCount: Int
        let canonicalPreflightVerdict: String
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
    @Published private(set) var sdkLocalBLEOnline = false
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
    private let preflightProvider = FieldTuyaPreflightProvider()
    private var connectionGeneration: UInt64 = 0
    private var connectionStartedAtUptime: UInt64?
    private var authenticatedAtUptime: UInt64?
    private var latestApplicationPayloadUptime: UInt64?
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

    var authenticatedDurationSeconds: Double? {
        guard let start = authenticatedAtUptime else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= start else { return nil }
        return Double(now - start) / 1_000_000_000
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
        message = "Ranking OFF→ON delta, known peripheral, FD50, Tuya company ID, name, and RSSI."
        log("power_on_scan_started")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        central.stopScan()
        if selectedID == nil, let first = candidates.first, first.likely {
            choose(first)
        }
        if selectedID == nil {
            message = "No candidate has enough scooter/Tuya evidence. Re-scan instead of guessing."
        }
        log("scan_stopped")
    }

    func choose(_ candidate: Candidate) {
        guard candidate.likely else {
            message = "Candidate confidence is too low. Re-scan instead of guessing."
            return
        }
        central.stopScan()
        selectedID = candidate.id
        phase = .selected
        message = "Likely scooter selected. CoreBluetooth discovery is stopped before Tuya's SDK takes connection ownership."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "score": String(candidate.score),
            "evidence": candidate.evidence.joined(separator: ",")
        ])
    }

    func authenticate() {
        guard let candidate = selected, candidate.likely else {
            fail("A strongly matched scooter candidate is required.", "candidate_not_confident")
            return
        }
        guard !deviceID.isEmpty, !tuyaUUID.isEmpty, !productID.isEmpty else {
            fail("Tuya device ID, UUID, or product ID is missing.", "tuya_identity_incomplete")
            return
        }
        guard OfficialTuyaFactory.bootstrap(), sdkCompiled, privateConfig else {
            fail("Official Tuya SmartLife SDK/security configuration is not provisioned. Do not run the physical test yet.", "sdk_unavailable")
            return
        }
        guard sdkAccountAuthorized else {
            fail("The official Tuya SDK has no authorized account session. The metadata QR session cannot substitute for SDK login.", "sdk_account_not_authorized")
            return
        }
        guard let newDriver = OfficialTuyaFactory.make() else {
            fail("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

        central.stopScan()
        watchdog?.cancel()
        driver = newDriver
        connectionGeneration &+= 1
        connectionStartedAtUptime = DispatchTime.now().uptimeNanoseconds
        authenticatedAtUptime = nil
        latestApplicationPayloadUptime = nil
        applicationUpdateCount = 0
        sdkLocalBLEOnline = false
        phase = .authenticating
        message = "Tuya's SDK is establishing the supported secure BLE session. Nembra sends no DP command."
        log("official_connect_requested", [
            "coreBluetoothID": candidate.id.uuidString,
            "tuyaDeviceID": deviceID,
            "tuyaUUID": tuyaUUID,
            "productID": productID,
            "generation": String(connectionGeneration)
        ])
        publishSnapshot(state: .authenticating, observedAt: connectionStartedAtUptime)

        newDriver.connect(
            deviceID: deviceID,
            uuid: tuyaUUID,
            productID: productID,
            onApplicationUpdate: { [weak self] update in
                Task { @MainActor in self?.receivedApplicationUpdate(update) }
            },
            success: { [weak self] in
                Task { @MainActor in self?.officialConnectReturnedSuccess() }
            },
            failure: { [weak self] error in
                Task { @MainActor in self?.fail(error, "official_connect_failed") }
            }
        )
    }

    private func officialConnectReturnedSuccess() {
        guard phase == .authenticating else { return }
        phase = .observing
        message = "Official connect callback returned. Waiting for Tuya's local-BLE authority before starting the 45-second evidence clock."
        log("official_connect_success_callback")
        refreshSDKConnectionState()
        startWatchdog()
    }

    private func refreshSDKConnectionState() {
        guard let driver, [.authenticating, .observing].contains(phase) else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let connected = driver.isLocallyConnected(uuid: tuyaUUID)

        if connected {
            if !sdkLocalBLEOnline {
                sdkLocalBLEOnline = true
                authenticatedAtUptime = now
                log("sdk_local_ble_connected", ["generation": String(connectionGeneration)])
                message = "Tuya's local BLE session is live. Waiting for genuine application updates through the SDK-owned device delegate."
            }
            publishSnapshot(state: .authenticated, observedAt: now)
            return
        }

        if sdkLocalBLEOnline || authenticatedAtUptime != nil {
            sdkLocalBLEOnline = false
            authenticatedAtUptime = nil
            fail("Tuya's local BLE session dropped before canonical preflight acceptance.", "sdk_local_ble_dropped")
        }
    }

    private func receivedApplicationUpdate(_ update: [String: String]) {
        guard [.authenticating, .observing].contains(phase), let driver else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            log("application_update_rejected_without_current_local_ble")
            fail("A Tuya application callback arrived after local BLE authority was unavailable; it was not admitted as physical evidence.", "stale_application_callback")
            return
        }

        if authenticatedAtUptime == nil {
            sdkLocalBLEOnline = true
            authenticatedAtUptime = now
            log("sdk_local_ble_connected_from_payload")
        }
        applicationUpdateCount += 1
        latestApplicationPayloadUptime = now
        log("tuya_application_update", update)
        message = "Receiving genuine Tuya application data · \(applicationUpdateCount) update(s). Keep the scooter stationary through the canonical 45-second gate."
        publishSnapshot(state: .authenticated, observedAt: now)
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, [.authenticating, .observing].contains(self.phase) else { return }
                self.refreshSDKConnectionState()
                if self.phase == .failed || self.phase == .accepted { return }

                if let started = self.connectionStartedAtUptime,
                   self.authenticatedAtUptime == nil {
                    let now = DispatchTime.now().uptimeNanoseconds
                    if now >= started, now - started >= 15_000_000_000 {
                        self.fail("Tuya's connect callback never became a current local BLE session within 15 seconds.", "sdk_local_ble_never_current")
                        return
                    }
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func publishSnapshot(
        state: TuyaAuthenticatedReadOnlyPreflightSnapshot.AuthenticationState,
        observedAt: UInt64?
    ) {
        let generation = connectionGeneration
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: state,
            authenticationMethod: state == .authenticated ? .smartLifeAppSDK : nil,
            connectionStartedAtUptimeNanoseconds: connectionStartedAtUptime,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptime,
            latestObservedUptimeNanoseconds: observedAt,
            applicationPayloadCount: applicationUpdateCount,
            latestApplicationPayloadUptimeNanoseconds: latestApplicationPayloadUptime,
            connectionGeneration: generation
        )

        Task { [weak self, preflightProvider] in
            await preflightProvider.replace(with: snapshot)
            let current = await preflightProvider.currentPreflightSnapshot()
            let verdict = TuyaAuthenticatedReadOnlyPreflight.verdict(for: current)
            await MainActor.run {
                self?.consumeCanonicalVerdict(verdict, snapshot: current)
            }
        }
    }

    private func consumeCanonicalVerdict(
        _ verdict: TuyaAuthenticatedReadOnlyPreflight.Verdict,
        snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) {
        guard snapshot.connectionGeneration == connectionGeneration, phase != .failed else { return }
        switch verdict {
        case .blocked(let reason):
            canonicalPreflightVerdict = "Blocked · \(reason)"
        case .readyForStationaryMapping:
            guard sdkLocalBLEOnline, phase == .observing else { return }
            canonicalPreflightVerdict = "READY · canonical authenticated preflight accepted"
            phase = .accepted
            watchdog?.cancel()
            watchdog = nil
            message = "Secure scooter link accepted. Tuya stayed locally connected beyond 45 seconds and delivered genuine application data. The next experiment may be stationary DP mapping only."
            log("canonical_preflight_accepted", [
                "generation": String(connectionGeneration),
                "applicationUpdates": String(applicationUpdateCount)
            ])
        }
    }

    func prepareExport() {
        let envelope = Export(
            schemaVersion: 3,
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
            authenticationMethod: authenticatedAtUptime == nil ? nil : TuyaReadOnlyAuthenticationMethod.smartLifeAppSDK.rawValue,
            connectionGeneration: connectionGeneration,
            authenticatedDurationSeconds: authenticatedDurationSeconds,
            sdkLocalBLEOnline: sdkLocalBLEOnline,
            applicationUpdateCount: applicationUpdateCount,
            canonicalPreflightVerdict: canonicalPreflightVerdict,
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
            message = "Sanitized diagnostics ready. Passwords, verification codes, account tokens, local_key, AppKey, and AppSecret are excluded."
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
        connectionGeneration = 0
        connectionStartedAtUptime = nil
        authenticatedAtUptime = nil
        latestApplicationPayloadUptime = nil
        sdkLocalBLEOnline = false
        applicationUpdateCount = 0
        canonicalPreflightVerdict = "Blocked · Tuya authentication required."
        exportData = nil
    }

    private func fail(_ text: String, _ kind: String) {
        watchdog?.cancel()
        watchdog = nil
        phase = .failed
        sdkLocalBLEOnline = false
        canonicalPreflightVerdict = "Blocked · \(text)"
        message = text
        log(kind, ["message": sanitize(text)])

        let now = DispatchTime.now().uptimeNanoseconds
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .failed(reason: text),
            authenticationMethod: nil,
            connectionStartedAtUptimeNanoseconds: connectionStartedAtUptime,
            authenticatedAtUptimeNanoseconds: nil,
            latestObservedUptimeNanoseconds: now,
            applicationPayloadCount: applicationUpdateCount,
            latestApplicationPayloadUptimeNanoseconds: latestApplicationPayloadUptime,
            connectionGeneration: connectionGeneration
        )
        Task { [preflightProvider] in
            await preflightProvider.replace(with: snapshot)
        }
    }

    private func log(_ kind: String, _ details: [String: String] = [:]) {
        events.append(Event(
            at: Date(),
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
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
        failure: @escaping (String) -> Void
    )
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

    static func privateCredential(named name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { return nil }
        return value
    }

    static var configured: Bool {
        compiled
            && privateCredential(named: "NEMBRA_TUYA_APP_KEY") != nil
            && privateCredential(named: "NEMBRA_TUYA_APP_SECRET") != nil
    }

    @discardableResult
    static func bootstrap() -> Bool {
#if canImport(ThingSmartHomeKit)
        guard let key = privateCredential(named: "NEMBRA_TUYA_APP_KEY"),
              let secret = privateCredential(named: "NEMBRA_TUYA_APP_SECRET") else { return false }
        ThingSmartSDK.sharedInstance()?.start(withAppKey: key, secretKey: secret)
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
            failure: { error in
                failure("Tuya SmartLife SDK did not establish the BLE session: \(error?.localizedDescription ?? "unknown error")")
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
private struct SecureLinkView: View {
    @StateObject private var test: SecureLinkController

    init(device: TuyaAccountBridge.LinkedDevice) {
        _test = StateObject(wrappedValue: SecureLinkController(device: device))
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
                            LabeledContent("Authenticated duration", value: String(format: "%.1f s", age))
                            ProgressView(value: min(age / 45, 1))
                        }
                        LabeledContent("Tuya local BLE", value: test.sdkLocalBLEOnline ? "Online" : "Not proven")
                        LabeledContent("Application updates", value: String(test.applicationUpdateCount))
                        Text(test.canonicalPreflightVerdict)
                            .font(.caption.monospaced())
                            .foregroundStyle(test.accepted ? .green : .secondary)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Official Tuya gate", systemImage: "checkmark.shield")
                            .font(.headline)
                        LabeledContent("SDK compiled in", value: test.sdkCompiled ? "Yes" : "No")
                        LabeledContent("Private app config", value: test.privateConfig ? "Yes" : "No")
                        LabeledContent("SDK account authorized", value: test.sdkAccountAuthorized ? "Yes" : "No")
                        if !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized {
                            Text("NO PHYSICAL TEST YET: Tuya's official SDK/security component, matching private app credentials, and an authorized SDK account session must all be ready. Metadata QR approval alone is not BLE authentication.")
                                .font(.footnote.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                    .card()

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
                            Button("Stop scan / use best evidence") { test.stopScan() }
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
                                            Text("LIKELY SCOOTER")
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
                                .disabled(!candidate.likely || !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized || [.authenticating, .observing, .accepted].contains(test.phase))
                        }
                        .card()
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Acceptance", systemImage: test.accepted ? "checkmark.seal.fill" : "hourglass")
                            .font(.headline)
                            .foregroundStyle(test.accepted ? .green : .white)
                        Text("The app does not own a parallel pass boolean. Only TuyaAuthenticatedReadOnlyPreflight.verdict(for:) may advance this screen: current official SDK authentication provenance, current connection generation, valid monotonic chronology, >45 seconds after authenticated local BLE, and at least one genuine application payload are all required.")
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
                        Button("Prepare sanitized diagnostic JSON") { test.prepareExport() }
                            .buttonStyle(.bordered)
                        if let data = test.exportData {
                            ShareLink(item: SecureTransfer(data: data, name: test.exportName), preview: SharePreview(test.exportName)) {
                                Label("Share diagnostic JSON", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Text("Export includes candidate evidence, connection generation, canonical verdict, monotonic continuity, SDK-local status, failures, and opaque application-update values. It excludes account passwords, verification codes, account tokens, local_key, AppKey, and AppSecret.")
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
