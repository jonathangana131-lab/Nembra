@preconcurrency import CoreBluetooth
import CoreTransferable
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
#if canImport(ThingSmartHomeKit)
import ThingSmartHomeKit
#endif

private let nembraConnectableAdvertisementKey = CBAdvertisementDataIsConnectable

@main @MainActor
struct NembraCaptureAuthenticatedApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureAuthenticationRoot()
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
private final class TuyaSDKAccountSession: ObservableObject {
    enum LoginKind: String, CaseIterable, Identifiable {
        case email = "Email"
        case phone = "Phone"
        var id: String { rawValue }
    }

    @Published private(set) var message = "Checking the official Tuya SDK gate…"
    @Published private(set) var isInitialized = false
    @Published private(set) var isLoggedIn = false
    @Published private(set) var isLoggingIn = false

    var compiled: Bool {
#if canImport(ThingSmartHomeKit)
        true
#else
        false
#endif
    }

    var configured: Bool {
        compiled && Self.privateCredential(named: "NEMBRA_TUYA_APP_KEY") != nil && Self.privateCredential(named: "NEMBRA_TUYA_APP_SECRET") != nil
    }

    init() {
        bootstrapIfPossible()
    }

    func bootstrapIfPossible() {
        guard compiled else {
            isInitialized = false
            isLoggedIn = false
            message = "ThingSmartHomeKit is not compiled into this build. Provision the official Tuya SDK/security component first."
            return
        }
        guard let key = Self.privateCredential(named: "NEMBRA_TUYA_APP_KEY"),
              let secret = Self.privateCredential(named: "NEMBRA_TUYA_APP_SECRET") else {
            isInitialized = false
            isLoggedIn = false
            message = "Private Tuya AppKey/AppSecret are not injected into this Xcode run."
            return
        }
#if canImport(ThingSmartHomeKit)
        ThingSmartSDK.sharedInstance()?.start(withAppKey: key, secretKey: secret)
        isInitialized = true
        refreshLoginState()
        if isLoggedIn {
            message = "Official Tuya SDK initialized and account session is authorized."
        } else {
            message = "Official Tuya SDK initialized. Sign in through the SDK before the secure BLE test."
        }
#endif
    }

    func refreshLoginState() {
#if canImport(ThingSmartHomeKit)
        isLoggedIn = ThingSmartUser.sharedInstance()?.isLogin == true
#else
        isLoggedIn = false
#endif
    }

    func login(kind: LoginKind, countryCode: String, account: String, password: String) {
        guard !isLoggingIn else { return }
        bootstrapIfPossible()
        guard isInitialized else { return }

        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !country.isEmpty, !user.isEmpty, !password.isEmpty else {
            message = "Country code, account, and password are required for this one-time SDK login."
            return
        }

        isLoggingIn = true
        message = "Authorizing the account through the official Tuya SDK…"
#if canImport(ThingSmartHomeKit)
        let success: () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isLoggingIn = false
                self.refreshLoginState()
                self.message = self.isLoggedIn
                    ? "Official Tuya account authorized. The password is not retained by Nembra."
                    : "Tuya reported login success but no active SDK session is visible; secure BLE remains blocked."
            }
        }
        let failure: (Error?) -> Void = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoggingIn = false
                self.refreshLoginState()
                let detail = error?.localizedDescription ?? "unknown Tuya login error"
                self.message = "Official Tuya login failed: \(detail)"
            }
        }
        switch kind {
        case .email:
            ThingSmartUser.sharedInstance()?.login(
                byEmail: country,
                email: user,
                password: password,
                success: success,
                failure: failure
            )
        case .phone:
            ThingSmartUser.sharedInstance()?.login(
                byPhone: country,
                phoneNumber: user,
                password: password,
                success: success,
                failure: failure
            )
        }
#else
        isLoggingIn = false
#endif
    }

    private static func privateCredential(named name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { return nil }
        return value
    }
}

@MainActor
private struct CaptureAuthenticationRoot: View {
    @StateObject private var cloud = TuyaAccountBridge()
    @StateObject private var sdk = TuyaSDKAccountSession()
    @State private var loginKind: TuyaSDKAccountSession.LoginKind = .email
    @State private var countryCode = "1"
    @State private var sdkAccount = ""
    @State private var sdkPassword = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("P0 · TUYA SECURE LINK")
                        .font(.caption.monospaced().bold())
                        .tracking(1.2)
                        .foregroundStyle(.green)
                    Text("Authenticate. Stay connected. Capture truth.")
                        .font(.largeTitle.bold())
                    Text("This build intentionally replaces the old ride-calibration entry point. The next run is stationary and only advances after the official Tuya session is live.")
                        .foregroundStyle(.secondary)
                    safetyCard
                    sdkCard
                    cloudAccountCard
                    if cloud.isLinked { deviceCard }
                }
                .frame(maxWidth: 760)
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Nembra Capture")
            .onAppear { sdk.bootstrapIfPossible() }
        }
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Read-only boundary", systemImage: "shield.checkered").font(.headline)
            Text("No unbind, reset, pairing reset, lock, speed, light, mode, throttle, brake, firmware, or DP control command is sent.")
                .font(.footnote.bold())
                .foregroundStyle(.green)
            Text("The metadata QR session never becomes BLE authority. local_key is not treated as a Tuya Bluetooth login key. The official SDK is the only authentication producer in this build.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .nembraCard()
    }

    private var sdkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("1 · Official Tuya SDK account", systemImage: "person.badge.key").font(.headline)
            LabeledContent("SDK compiled", value: sdk.compiled ? "Yes" : "No")
            LabeledContent("Private app config", value: sdk.configured ? "Injected" : "Missing")
            LabeledContent("SDK initialized", value: sdk.isInitialized ? "Yes" : "No")
            LabeledContent("SDK account", value: sdk.isLoggedIn ? "Authorized" : "Not authorized")
            Text(sdk.message).font(.footnote).foregroundStyle(.secondary)

            if sdk.isInitialized && !sdk.isLoggedIn {
                Picker("Account type", selection: $loginKind) {
                    ForEach(TuyaSDKAccountSession.LoginKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                TextField("Country code, e.g. 1", text: $countryCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                TextField(loginKind == .email ? "Tuya account email" : "Tuya account phone", text: $sdkAccount)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("Tuya account password", text: $sdkPassword)
                    .textFieldStyle(.roundedBorder)
                Button(sdk.isLoggingIn ? "Authorizing…" : "Authorize official SDK session") {
                    let password = sdkPassword
                    sdkPassword = ""
                    sdk.login(kind: loginKind, countryCode: countryCode, account: sdkAccount, password: password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sdk.isLoggingIn || sdkAccount.isEmpty || sdkPassword.isEmpty)
                Text("Nembra clears its password field immediately after the login request and never writes the password into the diagnostic export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .nembraCard()
    }

    private var cloudAccountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2 · Identify the already-bound scooter", systemImage: "qrcode.viewfinder").font(.headline)
            Text(cloud.statusMessage).font(.footnote).foregroundStyle(.secondary)
            if !cloud.isLinked {
                TextField("Tuya Smart User Code", text: $cloud.userCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                Button("Create metadata approval QR") { cloud.requestApproval() }
                    .buttonStyle(.borderedProminent)
                    .disabled(cloud.phase == .requestingApproval)
            }
            if let data = cloud.qrPNGData, let image = UIImage(data: data), !cloud.isLinked {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 230)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                Button("I approved it · check now") { cloud.checkApprovalNow() }
                    .buttonStyle(.bordered)
            }
            if cloud.phase == .failed {
                Button("Reset metadata account link") { cloud.resetLink() }.buttonStyle(.bordered)
            }
            Text("This QR path is still metadata/ownership discovery only. It does not satisfy the SDK account gate above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .nembraCard()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("3 · Select scooter", systemImage: "bicycle").font(.headline)
            if cloud.devices.isEmpty {
                Button("Refresh Tuya devices") { cloud.refreshDevices() }.buttonStyle(.bordered)
            }
            ForEach(cloud.devices) { device in
                VStack(alignment: .leading, spacing: 7) {
                    Text(device.name.isEmpty ? "Unnamed Tuya device" : device.name).font(.headline)
                    Text([device.productName, device.category].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(cloud.selectedDeviceID == device.id ? "Refresh metadata" : "Use this device") {
                            cloud.selectDevice(device)
                        }
                        .buttonStyle(.bordered)

                        if cloud.selectedDeviceID == device.id,
                           cloud.phase == .ready,
                           !device.productID.isEmpty,
                           !device.uuid.isEmpty {
                            NavigationLink("Secure stationary test") {
                                AuthenticatedSecureLinkView(device: device)
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
        }
        .nembraCard()
    }
}

@MainActor
private final class OfficialTuyaReadOnlySession: NSObject {
    var onApplicationPayload: (([AnyHashable: Any]) -> Void)?
    var onDeviceInfoChanged: (() -> Void)?

#if canImport(ThingSmartHomeKit)
    private var device: ThingSmartDevice?
#endif

    func connect(deviceID: String, uuid: String, productID: String, success: @escaping () -> Void, failure: @escaping (String) -> Void) {
#if canImport(ThingSmartHomeKit)
        guard ThingSmartUser.sharedInstance()?.isLogin == true else {
            failure("Official Tuya SDK account is not logged in.")
            return
        }
        guard !uuid.isEmpty, !productID.isEmpty else {
            failure("Tuya UUID/product ID is incomplete.")
            return
        }
        device = ThingSmartDevice(deviceId: deviceID)
        device?.delegate = self
        ThingSmartBLEManager.sharedInstance().connectBLE(
            withUUID: uuid,
            productKey: productID,
            success: success,
            failure: { failure("ThingSmartBLEManager did not establish the BLE session.") }
        )
#else
        failure("ThingSmartHomeKit is not compiled into this build.")
#endif
    }

    func isLocallyConnected(uuid: String) -> Bool {
#if canImport(ThingSmartHomeKit)
        ThingSmartBLEManager.sharedInstance().deviceStatue(withUUID: uuid)
#else
        false
#endif
    }
}

#if canImport(ThingSmartHomeKit)
extension OfficialTuyaReadOnlySession: ThingSmartDeviceDelegate {
    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        onApplicationPayload?(dps)
    }

    func deviceInfoUpdate(_ device: ThingSmartDevice?) {
        onDeviceInfoChanged?()
    }
}
#endif

@MainActor
private final class AuthenticatedSecureLinkController: NSObject, ObservableObject {
    struct Candidate: Identifiable, Codable, Equatable {
        let id: UUID
        var name: String?
        var rssi: Int?
        var advertisements: Int
        var appearedAfterPowerOn: Bool
        var hasFD50: Bool
        var hasTuyaCompanyID: Bool
        var matchesPriorPhysicalUUID: Bool
        var score: Int
        var evidence: [String]

        var title: String { name?.isEmpty == false ? name! : "Unnamed peripheral" }
        var isStrongMatch: Bool { matchesPriorPhysicalUUID || (hasFD50 && hasTuyaCompanyID) }
    }

    enum Phase: String, Codable {
        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed
    }

    struct Event: Codable {
        let at: Date
        let uptimeNanoseconds: UInt64
        let kind: String
        let details: [String: String]
        let rawHex: String?
        let rawBase64: String?
        let applicationJSON: String?
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
        let sdkLocallyConnected: Bool
        let authenticatedDurationSeconds: Double?
        let applicationPayloadCount: Int
        let rawFD50NotificationCount: Int
        let candidates: [Candidate]
        let secretsRedacted: Bool
        let dpCommandsSent: Bool
        let events: [Event]
    }

    static let priorPhysicalUUID = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    static let fd50 = CBUUID(string: "FD50")
    static let fd50Notify = CBUUID(string: "00000002-0000-1001-8001-00805F9B07D0")
    static let requiredAuthenticatedNanoseconds: UInt64 = 45_000_000_000

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Start with the scooter OFF. No ride is needed."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var applicationPayloadCount = 0
    @Published private(set) var rawPacketCount = 0
    @Published private(set) var sdkLocallyConnected = false
    @Published private(set) var exportData: Data?
    @Published private(set) var exportName = "Nembra-Authenticated-Tuya-Diagnostics.json"

    let deviceID: String
    let productID: String
    let tuyaUUID: String

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var byID: [UUID: Candidate] = [:]
    private var baseline = Set<UUID>()
    private var selectedPeripheral: CBPeripheral?
    private var officialSession: OfficialTuyaReadOnlySession?
    private var authenticatedAtUptime: UInt64?
    private var events: [Event] = []
    private var watchdog: Task<Void, Never>?
    private var rawObserverEnabled = false

    init(device: TuyaAccountBridge.LinkedDevice) {
        deviceID = device.id
        productID = device.productID
        tuyaUUID = device.uuid
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        log("controller_created")
    }

    deinit { watchdog?.cancel() }

    var authenticatedDurationSeconds: Double? {
        guard sdkLocallyConnected, let start = authenticatedAtUptime else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= start else { return nil }
        return Double(now - start) / 1_000_000_000
    }

    var passed: Bool {
        guard sdkLocallyConnected,
              let start = authenticatedAtUptime else { return false }
        let now = DispatchTime.now().uptimeNanoseconds
        return now >= start && now - start >= Self.requiredAuthenticatedNanoseconds && applicationPayloadCount > 0 && rawPacketCount > 0
    }

    func startBaseline() {
        guard central.state == .poweredOn else { fail("Bluetooth is not ready.", kind: "bluetooth_unavailable"); return }
        resetAttempt()
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
        log("baseline_saved", ["candidateCount": String(baseline.count)])
    }

    func scanAfterPowerOn() {
        guard central.state == .poweredOn else { fail("Bluetooth is not ready.", kind: "bluetooth_unavailable"); return }
        phase = .scanning
        message = "Looking for the prior physical UUID and corroborating FD50/Tuya advertisement evidence."
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        log("power_on_scan_started")
    }

    func stopScanAndChooseStrongest() {
        central.stopScan()
        if selectedID == nil, let candidate = candidates.first(where: { $0.isStrongMatch }) {
            choose(candidate)
        }
        if selectedID == nil { message = "No candidate has enough deterministic evidence. Re-scan instead of guessing." }
        log("scan_stopped")
    }

    func choose(_ candidate: Candidate) {
        central.stopScan()
        guard candidate.isStrongMatch else {
            message = "That candidate is not strongly correlated enough to authorize the secure test."
            return
        }
        selectedID = candidate.id
        selectedPeripheral = peripherals[candidate.id]
        phase = .selected
        message = "Scooter candidate selected from physical/FD50 evidence. Ready for the official session."
        log("candidate_selected", ["peripheralID": candidate.id.uuidString, "evidence": candidate.evidence.joined(separator: ",")])
    }

    func authenticate() {
        guard let candidate = selectedID.flatMap({ byID[$0] }), candidate.isStrongMatch else {
            fail("A strongly correlated scooter target is required.", kind: "target_not_correlated")
            return
        }
        guard !tuyaUUID.isEmpty, !productID.isEmpty, !deviceID.isEmpty else {
            fail("Tuya device identity is incomplete.", kind: "tuya_identity_incomplete")
            return
        }

        let session = OfficialTuyaReadOnlySession()
        session.onApplicationPayload = { [weak self] payload in
            Task { @MainActor in self?.recordApplicationPayload(payload) }
        }
        session.onDeviceInfoChanged = { [weak self] in
            Task { @MainActor in self?.refreshSDKConnectionState() }
        }
        officialSession = session
        phase = .authenticating
        message = "ThingSmartBLEManager is establishing the supported Tuya BLE session."
        log("official_connect_requested", ["tuyaUUID": tuyaUUID, "productID": productID])
        session.connect(deviceID: deviceID, uuid: tuyaUUID, productID: productID, success: { [weak self] in
            Task { @MainActor in self?.officialConnectReturnedSuccess() }
        }, failure: { [weak self] reason in
            Task { @MainActor in self?.fail(reason, kind: "official_connect_failed") }
        })
    }

    func prepareExport() {
        let export = Export(
            schemaVersion: 2,
            purpose: "Tuya authenticated stationary read-only preflight",
            exportedAt: Date(),
            tuyaDeviceID: deviceID,
            tuyaUUID: tuyaUUID,
            productID: productID,
            selectedPeripheralID: selectedID?.uuidString,
            phase: phase,
            sdkLocallyConnected: sdkLocallyConnected,
            authenticatedDurationSeconds: authenticatedDurationSeconds,
            applicationPayloadCount: applicationPayloadCount,
            rawFD50NotificationCount: rawPacketCount,
            candidates: candidates,
            secretsRedacted: true,
            dpCommandsSent: false,
            events: events
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            exportData = try encoder.encode(export)
            exportName = "Nembra-Tuya-Auth-\(deviceID.prefix(8))-Diagnostics.json"
            message = "Sanitized authenticated diagnostics are ready to share."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    private func officialConnectReturnedSuccess() {
        guard phase == .authenticating else { return }
        log("official_connect_success_callback")
        phase = .observing
        message = "Official connect callback returned. Waiting for ThingSmartBLEManager to confirm a live local BLE session."
        refreshSDKConnectionState()
        startWatchdog()
    }

    private func refreshSDKConnectionState() {
        guard let officialSession else { return }
        let connected = officialSession.isLocallyConnected(uuid: tuyaUUID)
        if connected && !sdkLocallyConnected {
            sdkLocallyConnected = true
            authenticatedAtUptime = DispatchTime.now().uptimeNanoseconds
            log("sdk_local_ble_connected")
            attachRawObserverIfPossible()
        } else if !connected && sdkLocallyConnected {
            sdkLocallyConnected = false
            authenticatedAtUptime = nil
            fail("The official Tuya local BLE session disconnected before acceptance.", kind: "sdk_local_ble_disconnected")
        }
    }

    private func attachRawObserverIfPossible() {
        guard !rawObserverEnabled, let peripheral = selectedPeripheral else { return }
        rawObserverEnabled = true
        peripheral.delegate = self
        central.connect(peripheral)
        log("supplemental_raw_observer_connect_requested")
        message = "Official Tuya BLE is live. Waiting for application payloads and a supplemental raw FD50 notification tap."
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.phase == .observing || self.phase == .accepted else { return }
                self.refreshSDKConnectionState()
                if self.phase == .failed { return }
                if self.passed {
                    self.phase = .accepted
                    self.message = "Authenticated session survived >45 s with official application payloads and raw FD50 notification bytes."
                    self.log("acceptance_passed", ["applicationPayloads": String(self.applicationPayloadCount), "rawFD50Packets": String(self.rawPacketCount)])
                    return
                }
                if let age = self.authenticatedDurationSeconds, age >= 60 {
                    if self.applicationPayloadCount == 0 {
                        self.message = "Official BLE stayed connected, but no ThingSmart device payload arrived yet. Keep the scooter stationary and export diagnostics if this persists."
                    } else if self.rawPacketCount == 0 {
                        self.message = "Authentication and ThingSmart application payloads are proven, but the supplemental CoreBluetooth tap has not exposed raw FD50 bytes. Export this result; do not repeat the ride test."
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func recordApplicationPayload(_ payload: [AnyHashable: Any]) {
        applicationPayloadCount += 1
        let json = Self.canonicalJSONString(payload)
        log("thingsmart_dps_update", ["entryCount": String(payload.count)], applicationJSON: json)
        if !sdkLocallyConnected { refreshSDKConnectionState() }
        message = "Official application data received (\(applicationPayloadCount)). Keep it stationary until the 45-second gate also has raw FD50 bytes."
    }

    private func resetAttempt() {
        watchdog?.cancel()
        watchdog = nil
        central.stopScan()
        if let selectedPeripheral { central.cancelPeripheralConnection(selectedPeripheral) }
        peripherals.removeAll()
        byID.removeAll()
        candidates.removeAll()
        baseline.removeAll()
        selectedID = nil
        selectedPeripheral = nil
        officialSession = nil
        authenticatedAtUptime = nil
        sdkLocallyConnected = false
        applicationPayloadCount = 0
        rawPacketCount = 0
        rawObserverEnabled = false
        exportData = nil
    }

    private func fail(_ reason: String, kind: String) {
        watchdog?.cancel()
        watchdog = nil
        phase = .failed
        message = reason
        log(kind, ["reason": Self.sanitized(reason)])
    }

    private func log(_ kind: String, _ details: [String: String] = [:], raw: Data? = nil, applicationJSON: String? = nil) {
        events.append(Event(
            at: Date(),
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            kind: kind,
            details: details.mapValues(Self.sanitized),
            rawHex: raw.map { $0.map { String(format: "%02X", $0) }.joined() },
            rawBase64: raw?.base64EncodedString(),
            applicationJSON: applicationJSON.map(Self.sanitized)
        ))
    }

    private static func sanitized(_ string: String) -> String {
        var result = string
        for key in ["NEMBRA_TUYA_APP_KEY", "NEMBRA_TUYA_APP_SECRET"] {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                result = result.replacingOccurrences(of: value, with: "<redacted>")
            }
        }
        return result
    }

    private static func canonicalJSONString(_ payload: [AnyHashable: Any]) -> String? {
        let normalized = payload.reduce(into: [String: Any]()) { output, item in
            output[String(describing: item.key)] = item.value
        }
        guard JSONSerialization.isValidJSONObject(normalized),
              let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func hasTuyaCompanyID(_ data: Data?) -> Bool {
        guard let data, data.count >= 2 else { return false }
        let first = UInt16(data[data.startIndex])
        let second = UInt16(data[data.index(after: data.startIndex)]) << 8
        return first | second == 0x07D0
    }

    private func updateCandidate(_ peripheral: CBPeripheral, advertisement: [String: Any], rssi: NSNumber) {
        let id = peripheral.identifier
        peripherals[id] = peripheral
        if phase == .baseline { baseline.insert(id) }

        let previous = byID[id]
        let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? previous?.name
        let normalizedRSSI = rssi.intValue == 127 ? previous?.rssi : rssi.intValue
        let serviceUUIDs = ((advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? [])
            + ((advertisement[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? [])
            + ((advertisement[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID]) ?? [])
        let serviceData = advertisement[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let hasFD50 = serviceUUIDs.contains(Self.fd50) || serviceData?.keys.contains(Self.fd50) == true || previous?.hasFD50 == true
        let tuyaCompany = Self.hasTuyaCompanyID(advertisement[CBAdvertisementDataManufacturerDataKey] as? Data) || previous?.hasTuyaCompanyID == true
        let priorUUID = id == Self.priorPhysicalUUID
        let appeared = (phase == .scanning && !baseline.contains(id)) || previous?.appearedAfterPowerOn == true

        var score = 0
        var evidence: [String] = []
        if priorUUID { score += 1000; evidence.append("prior physical CoreBluetooth UUID") }
        if hasFD50 { score += 500; evidence.append("FD50") }
        if tuyaCompany { score += 350; evidence.append("Tuya company 0x07D0") }
        if appeared { score += 180; evidence.append("appeared after power-on") }
        if let normalizedRSSI, normalizedRSSI >= -65 { score += 40; evidence.append("nearby RSSI (descriptive only)") }

        byID[id] = Candidate(
            id: id,
            name: name,
            rssi: normalizedRSSI,
            advertisements: (previous?.advertisements ?? 0) + 1,
            appearedAfterPowerOn: appeared,
            hasFD50: hasFD50,
            hasTuyaCompanyID: tuyaCompany,
            matchesPriorPhysicalUUID: priorUUID,
            score: score,
            evidence: evidence
        )
        candidates = byID.values.sorted {
            $0.score == $1.score ? (($0.rssi ?? -999) > ($1.rssi ?? -999)) : $0.score > $1.score
        }
    }
}

extension AuthenticatedSecureLinkController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("central_state", ["rawValue": String(central.state.rawValue)])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        updateCandidate(peripheral, advertisement: advertisementData, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard rawObserverEnabled, selectedID == peripheral.identifier else { return }
        log("raw_observer_connected")
        peripheral.delegate = self
        peripheral.discoverServices([Self.fd50])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard rawObserverEnabled, selectedID == peripheral.identifier else { return }
        log("raw_observer_connect_failed", ["error": error?.localizedDescription ?? "unknown"])
        message = "Official Tuya BLE may still be live, but the supplemental raw observer could not attach. Export diagnostics instead of starting a ride test."
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard rawObserverEnabled, selectedID == peripheral.identifier else { return }
        log("raw_observer_disconnected", ["error": error?.localizedDescription ?? ""])
        message = "Supplemental raw observer disconnected. Official Tuya connection truth is checked separately."
    }
}

extension AuthenticatedSecureLinkController: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            log("fd50_discovery_failed", ["error": error.localizedDescription])
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.fd50 }) else {
            log("fd50_missing")
            return
        }
        log("fd50_found")
        peripheral.discoverCharacteristics([Self.fd50Notify], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            log("notify_discovery_failed", ["error": error.localizedDescription])
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.fd50Notify }),
              characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
            log("fd50_notify_missing")
            return
        }
        peripheral.setNotifyValue(true, for: characteristic)
        log("raw_notify_subscription_requested")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log("raw_notify_subscription_failed", ["error": error.localizedDescription])
            return
        }
        log("raw_notify_state", ["enabled": characteristic.isNotifying ? "true" : "false"])
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard rawObserverEnabled, characteristic.uuid == Self.fd50Notify, characteristic.isNotifying else { return }
        if let error {
            log("raw_notification_error", ["error": error.localizedDescription])
            return
        }
        guard sdkLocallyConnected, let value = characteristic.value, !value.isEmpty else { return }
        rawPacketCount += 1
        log("post_auth_fd50_notification", ["byteCount": String(value.count)], raw: value)
        message = "Raw FD50 data received (\(rawPacketCount)); official application payloads: \(applicationPayloadCount). Keep it stationary through 45 seconds."
    }
}

@MainActor
private struct AuthenticatedSecureLinkView: View {
    @StateObject private var test: AuthenticatedSecureLinkController

    init(device: TuyaAccountBridge.LinkedDevice) {
        _test = StateObject(wrappedValue: AuthenticatedSecureLinkController(device: device))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SMALLEST STATIONARY TEST")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.green)
                    Text("Secure link → payload → 45 s.").font(.largeTitle.bold())
                    Text("Keep the scooter still. Do not run the old 17-step ride sequence.").foregroundStyle(.secondary)
                    statusCard
                    discoveryCard
                    if let selected = test.selectedID.flatMap({ id in test.candidates.first(where: { $0.id == id }) }) {
                        selectedCard(selected)
                    }
                    acceptanceCard
                    exportCard
                }
                .frame(maxWidth: 760)
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
        }
        .navigationTitle("Secure Link")
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(test.passed ? "Authenticated capture gate passed" : test.phase == .failed ? "Secure test stopped" : "Authentication preflight")
                    .font(.headline)
                Spacer()
                Text("\(test.rawPacketCount) raw").monospacedDigit()
            }
            Text(test.message).font(.footnote).foregroundStyle(.secondary)
            LabeledContent("Official local BLE", value: test.sdkLocallyConnected ? "Connected" : "Not proven")
            LabeledContent("Application payloads", value: String(test.applicationPayloadCount))
            LabeledContent("Raw FD50 packets", value: String(test.rawPacketCount))
            if let age = test.authenticatedDurationSeconds {
                LabeledContent("Authenticated duration", value: String(format: "%.1f s", age))
                ProgressView(value: min(age / 45, 1))
            }
        }
        .nembraCard()
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Find the same physical scooter", systemImage: "scope").font(.headline)
            switch test.phase {
            case .idle, .failed:
                Button("Start scooter-OFF baseline") { test.startBaseline() }.buttonStyle(.borderedProminent)
            case .baseline:
                Button("Save OFF baseline") { test.saveBaseline() }.buttonStyle(.borderedProminent)
            case .powerOn:
                Text("Turn scooter ON and keep it stationary.").foregroundStyle(.secondary)
                Button("Scan after power-on") { test.scanAfterPowerOn() }.buttonStyle(.borderedProminent)
            case .scanning:
                Button("Stop scan / use strongest deterministic match") { test.stopScanAndChooseStrongest() }.buttonStyle(.bordered)
            default:
                EmptyView()
            }

            ForEach(test.candidates.prefix(8)) { candidate in
                Button { test.choose(candidate) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(candidate.title).bold()
                            if candidate.isStrongMatch {
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
        .nembraCard()
    }

    private func selectedCard(_ candidate: AuthenticatedSecureLinkController.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Official secure session", systemImage: "key.horizontal").font(.headline)
            Text(candidate.evidence.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
            Button("Start official read-only session") { test.authenticate() }
                .buttonStyle(.borderedProminent)
                .disabled(!candidate.isStrongMatch || [.authenticating, .observing, .accepted].contains(test.phase))
        }
        .nembraCard()
    }

    private var acceptanceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Acceptance", systemImage: test.passed ? "checkmark.seal.fill" : "hourglass")
                .font(.headline)
                .foregroundStyle(test.passed ? .green : .white)
            Text("Pass requires the official Tuya local BLE session to stay current for at least 45 seconds, at least one ThingSmart device payload, and at least one non-empty FD50 notify byte sequence captured after official connection. The app does not infer any DP meaning from this gate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if test.passed {
                Text("SECURE LINK ACCEPTED · READY FOR THE NEXT SMALLEST STATIONARY MAPPING STEP")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.green)
            }
        }
        .nembraCard()
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Prepare sanitized diagnostic JSON") { test.prepareExport() }.buttonStyle(.bordered)
            if let data = test.exportData {
                ShareLink(item: AuthenticatedSecureTransfer(data: data, filename: test.exportName), preview: SharePreview(test.exportName)) {
                    Label("Share authenticated diagnostics", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            Text("The export includes exact raw FD50 bytes (hex + Base64), official DP callback JSON when serializable, monotonic receipt times, target evidence, and connection state. It excludes account passwords, AppKey, AppSecret, tokens, and local_key.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .nembraCard()
    }
}

private struct AuthenticatedSecureTransfer: Transferable {
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { transfer in transfer.data }
            .suggestedFileName { transfer in transfer.filename }
    }
}

private extension View {
    func nembraCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
