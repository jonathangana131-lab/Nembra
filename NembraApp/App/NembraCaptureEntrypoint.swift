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

    var compiled: Bool { OfficialTuyaFactory.compiled }
    var configured: Bool { OfficialTuyaFactory.configured }

    init() { bootstrapIfPossible() }

    func bootstrapIfPossible() {
        guard compiled else {
            isInitialized = false
            isLoggedIn = false
            message = "ThingSmartHomeKit is not compiled into this build."
            return
        }
        guard OfficialTuyaFactory.bootstrapSDK() else {
            isInitialized = false
            isLoggedIn = false
            message = "Private Tuya AppKey/AppSecret are not injected into this run."
            return
        }
        isInitialized = true
        refreshLoginState()
        message = isLoggedIn
            ? "Official Tuya SDK initialized and account session is authorized."
            : "Official Tuya SDK initialized. Authorize the account before the secure BLE test."
    }

    func refreshLoginState() {
        isLoggedIn = OfficialTuyaFactory.accountReady
    }

    func login(kind: LoginKind, countryCode: String, account: String, password: String) {
        guard !isLoggingIn else { return }
        bootstrapIfPossible()
        guard isInitialized else { return }

        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !country.isEmpty, !user.isEmpty, !password.isEmpty else {
            message = "Country code, account, and password are required."
            return
        }

        isLoggingIn = true
        message = "Authorizing through the official Tuya SDK…"
#if canImport(ThingSmartHomeKit)
        let success: () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isLoggingIn = false
                self.refreshLoginState()
                self.message = self.isLoggedIn
                    ? "Official Tuya account authorized. Nembra does not retain the password."
                    : "Tuya returned login success but no active SDK account session is visible."
            }
        }
        let failure: (Error?) -> Void = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoggingIn = false
                self.refreshLoginState()
                self.message = "Official Tuya login failed: \(error?.localizedDescription ?? "unknown error")"
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
}

@MainActor
private struct CaptureP0Root: View {
    @StateObject private var tuya = TuyaAccountBridge()
    @StateObject private var sdkAccount = TuyaSDKAccountSession()
    @State private var loginKind: TuyaSDKAccountSession.LoginKind = .email
    @State private var countryCode = "1"
    @State private var sdkAccountIdentifier = ""
    @State private var sdkPassword = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("P0 · TUYA AUTHENTICATION").font(.caption.monospaced().bold()).foregroundStyle(.green)
                    Text("Prove the secure scooter link first.").font(.largeTitle.bold())
                    Text("The next physical run is stationary. It proves supported Tuya authentication, >45 s local-BLE continuity, and real application updates through Tuya's own SDK. The old 17-step ride sequence stays disabled until this passes.").foregroundStyle(.secondary)
                    safetyCard
                    sdkAccountCard
                    metadataAccountCard
                    if tuya.isLinked { deviceCard }
                }.frame(maxWidth: 760).padding(18).frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Nembra Capture")
            .onAppear { sdkAccount.bootstrapIfPossible() }
        }
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Read-only control boundary", systemImage: "shield.checkered").font(.headline)
            Text("Account linking is used for ownership/device identity. Nembra does not turn local_key into a BLE login key, synthesize Tuya authentication frames, or open a second CoreBluetooth connection after the official SDK takes ownership.").foregroundStyle(.secondary)
            Text("No unbind, reset, lock, speed, light, mode, throttle, brake, firmware, or other DP command is sent.").font(.footnote.bold()).foregroundStyle(.green)
        }.card()
    }

    private var sdkAccountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("1 · Authorize the official Tuya SDK", systemImage: "person.badge.key").font(.headline)
            LabeledContent("SDK compiled in", value: sdkAccount.compiled ? "Yes" : "No")
            LabeledContent("Private app config", value: sdkAccount.configured ? "Yes" : "No")
            LabeledContent("SDK initialized", value: sdkAccount.isInitialized ? "Yes" : "No")
            LabeledContent("SDK account authorized", value: sdkAccount.isLoggedIn ? "Yes" : "No")
            Text(sdkAccount.message).font(.footnote).foregroundStyle(.secondary)

            if sdkAccount.isInitialized && !sdkAccount.isLoggedIn {
                Picker("Account type", selection: $loginKind) {
                    ForEach(TuyaSDKAccountSession.LoginKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                }.pickerStyle(.segmented)
                TextField("Country code, e.g. 1", text: $countryCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                TextField(loginKind == .email ? "Tuya account email" : "Tuya account phone", text: $sdkAccountIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("Tuya account password", text: $sdkPassword).textFieldStyle(.roundedBorder)
                Button(sdkAccount.isLoggingIn ? "Authorizing…" : "Authorize official SDK session") {
                    let password = sdkPassword
                    sdkPassword = ""
                    sdkAccount.login(kind: loginKind, countryCode: countryCode, account: sdkAccountIdentifier, password: password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sdkAccount.isLoggingIn || sdkAccountIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sdkPassword.isEmpty)
                Text("The password field is cleared before the SDK request runs and is never included in Capture diagnostics.").font(.caption).foregroundStyle(.secondary)
            }
        }.card()
    }

    private var metadataAccountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2 · Identify your bound Tuya device", systemImage: "qrcode.viewfinder").font(.headline)
            Text(tuya.statusMessage).font(.footnote).foregroundStyle(.secondary)
            if !tuya.isLinked {
                TextField("Tuya Smart User Code", text: $tuya.userCode).textInputAutocapitalization(.never).autocorrectionDisabled().padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                Button("Create metadata approval QR") { tuya.requestApproval() }.buttonStyle(.borderedProminent).disabled(tuya.phase == .requestingApproval)
            }
            if let data = tuya.qrPNGData, let image = UIImage(data: data), !tuya.isLinked {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 230).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 14))
                Button("I approved it · check now") { tuya.checkApprovalNow() }.buttonStyle(.bordered)
            }
            if tuya.phase == .failed { Button("Reset metadata account link") { tuya.resetLink() }.buttonStyle(.bordered) }
            Text("This QR path is metadata/ownership discovery only. It never substitutes for the official SDK account gate above.").font(.caption).foregroundStyle(.secondary)
        }.card()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("3 · Choose the scooter", systemImage: "bicycle").font(.headline)
            if tuya.devices.isEmpty { Button("Refresh Tuya devices") { tuya.refreshDevices() }.buttonStyle(.bordered) }
            ForEach(tuya.devices) { device in
                VStack(alignment: .leading, spacing: 7) {
                    Text(device.name.isEmpty ? "Unnamed Tuya device" : device.name).font(.headline)
                    Text([device.productName, device.category].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(tuya.selectedDeviceID == device.id ? "Refresh metadata" : "Use this device") { tuya.selectDevice(device) }.buttonStyle(.bordered)
                        if tuya.selectedDeviceID == device.id, tuya.phase == .ready, !device.productID.isEmpty, !device.uuid.isEmpty {
                            NavigationLink("Secure stationary test") { SecureLinkView(device: device) }
                                .buttonStyle(.borderedProminent)
                                .disabled(!sdkAccount.isLoggedIn)
                        }
                    }
                }.padding(12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Only Tuya device ID, device UUID and product ID enter the supported secure-link controller. local_key does not.").font(.footnote).foregroundStyle(.secondary)
            if !sdkAccount.isLoggedIn {
                Label("Secure test is locked until the official SDK account is authorized.", systemImage: "lock.fill").font(.footnote.bold()).foregroundStyle(.orange)
            }
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
    struct Event: Codable { let at: Date; let monotonicNanoseconds: UInt64; let kind: String; let details: [String: String] }
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
        let secretsRedacted: Bool
        let dpCommandsSent: Bool
        let candidates: [Candidate]
        let events: [Event]
    }

    static let knownPeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    static let fd50 = CBUUID(string: "FD50")
    static let localBLEAcquireTimeoutNanoseconds: UInt64 = 15_000_000_000
    static let acceptanceDurationNanoseconds: UInt64 = 45_000_000_000

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Start with the scooter OFF. This test only identifies it and proves Tuya's supported secure session."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var applicationUpdateCount = 0
    @Published private(set) var secureSessionEstablished = false
    @Published private(set) var sdkLocalBLEOnline = false
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
    private var transportSuccessUptime: UInt64?
    private var authenticatedAtUptime: UInt64?
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
        guard let start = authenticatedAtUptime else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        return now >= start ? Double(now - start) / 1_000_000_000 : nil
    }

    var passed: Bool {
        guard phase == .observing || phase == .accepted,
              secureSessionEstablished,
              sdkLocalBLEOnline,
              applicationUpdateCount > 0,
              let start = authenticatedAtUptime else { return false }
        let now = DispatchTime.now().uptimeNanoseconds
        return now >= start && now - start >= Self.acceptanceDurationNanoseconds
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
        phase = .scanning; message = "Looking for the prior physical UUID or corroborating FD50 + Tuya company evidence."; log("power_on_scan_started")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        central.stopScan()
        if selectedID == nil, let first = candidates.first(where: { $0.likely }) { choose(first) }
        if selectedID == nil { message = "No candidate has enough deterministic scooter/Tuya evidence. Re-scan instead of guessing." }
        log("scan_stopped")
    }

    func choose(_ candidate: Candidate) {
        guard candidate.likely else { message = "This candidate lacks deterministic target evidence. Re-scan instead of guessing."; return }
        central.stopScan(); selectedID = candidate.id; phase = .selected
        message = "Scooter target selected. CoreBluetooth discovery is stopped before Tuya's SDK takes connection ownership."
        log("candidate_selected", ["id": candidate.id.uuidString, "score": String(candidate.score), "evidence": candidate.evidence.joined(separator: ",")])
    }

    func authenticate() {
        guard let candidate = selected, candidate.likely else { fail("A strongly correlated scooter candidate is required.", "candidate_not_confident"); return }
        guard !deviceID.isEmpty, !tuyaUUID.isEmpty, !productID.isEmpty else { fail("Tuya device ID, UUID or product ID is missing.", "tuya_identity_incomplete"); return }
        guard sdkCompiled, privateConfig else { fail("Official Tuya SmartLife SDK/security configuration is not provisioned. Do not run the physical test yet.", "sdk_unavailable"); return }
        guard OfficialTuyaFactory.bootstrapSDK(), sdkAccountAuthorized else { fail("The official Tuya SDK has no authorized account session. The metadata QR session cannot substitute for SDK login.", "sdk_account_not_authorized"); return }
        guard let newDriver = OfficialTuyaFactory.make() else { fail("Official Tuya provider is unavailable.", "sdk_provider_unavailable"); return }

        central.stopScan(); driver = newDriver; phase = .authenticating
        message = "Tuya's SDK is establishing the supported secure BLE session. Nembra sends no DP command."
        log("official_connect_requested", ["coreBluetoothID": candidate.id.uuidString, "tuyaDeviceID": deviceID, "tuyaUUID": tuyaUUID, "productID": productID])
        newDriver.connect(
            deviceID: deviceID,
            uuid: tuyaUUID,
            productID: productID,
            onApplicationUpdate: { [weak self] update in Task { @MainActor in self?.receivedApplicationUpdate(update) } },
            success: { [weak self] in Task { @MainActor in self?.transportConnectSucceeded() } },
            failure: { [weak self] error in Task { @MainActor in self?.fail(error, "official_connect_failed") } }
        )
    }

    private func transportConnectSucceeded() {
        guard phase == .authenticating else { return }
        secureSessionEstablished = true
        transportSuccessUptime = DispatchTime.now().uptimeNanoseconds
        authenticatedAtUptime = nil
        sdkLocalBLEOnline = false
        phase = .observing
        message = "Official connect callback returned. Waiting for Tuya to prove the local BLE link is actually online…"
        log("official_connect_success_callback")
        refreshLocalBLEState()
        startWatchdog()
    }

    private func refreshLocalBLEState() {
        guard secureSessionEstablished, let driver else { return }
        let online = driver.isLocallyConnected(uuid: tuyaUUID)
        if online && !sdkLocalBLEOnline {
            sdkLocalBLEOnline = true
            authenticatedAtUptime = DispatchTime.now().uptimeNanoseconds
            applicationUpdateCount = 0
            log("sdk_local_ble_online")
            message = "Tuya local BLE is online. The 45-second continuity clock starts now; waiting for a current-session application update."
        } else if !online && sdkLocalBLEOnline {
            sdkLocalBLEOnline = false
            authenticatedAtUptime = nil
            fail("Tuya's local BLE session dropped before the authenticated capture was sealed. Export diagnostics; do not repeat the outdoor ride capture.", "sdk_local_ble_dropped")
        }
    }

    private func receivedApplicationUpdate(_ update: [String: String]) {
        guard secureSessionEstablished, phase == .observing || phase == .accepted else { return }
        refreshLocalBLEState()
        guard phase != .failed else { return }
        guard sdkLocalBLEOnline, authenticatedAtUptime != nil else {
            log("tuya_application_update_before_local_gate", update)
            return
        }
        applicationUpdateCount += 1
        log("tuya_application_update", update)
        message = passed
            ? "Secure scooter link passed. Tuya delivered current-session application data and local BLE remained online for at least 45 seconds."
            : "Receiving current-session scooter data · \(applicationUpdateCount) update(s). Keep it stationary until the 45-second gate passes."
        if passed { acceptIfReady() }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.secureSessionEstablished, self.phase == .observing || self.phase == .accepted else { return }
                self.refreshLocalBLEState()
                if self.phase == .failed { return }

                if self.passed {
                    self.acceptIfReady()
                    return
                }

                let now = DispatchTime.now().uptimeNanoseconds
                if self.authenticatedAtUptime == nil,
                   let transport = self.transportSuccessUptime,
                   now >= transport,
                   now - transport >= Self.localBLEAcquireTimeoutNanoseconds {
                    self.fail("Tuya returned a connect callback, but local BLE never became current within 15 seconds. Export diagnostics; do not proceed to mapping.", "sdk_local_ble_not_acquired")
                    return
                }

                if let start = self.authenticatedAtUptime,
                   now >= start,
                   now - start >= 60_000_000_000,
                   self.applicationUpdateCount == 0 {
                    self.fail("Tuya local BLE survived 60 seconds, but no current-session application update arrived.", "no_application_updates")
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func acceptIfReady() {
        guard passed, phase != .accepted else { return }
        phase = .accepted
        message = "Secure scooter link passed. Tuya delivered current-session application data and local BLE remained online for at least 45 seconds."
        log("acceptance_passed", ["applicationUpdates": String(applicationUpdateCount)])
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
            secretsRedacted: true,
            dpCommandsSent: false,
            candidates: candidates,
            events: events
        )
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .iso8601
            exportData = try encoder.encode(envelope)
            exportName = "Nembra-Secure-Link-\(deviceID.prefix(8))-Diagnostics.json"
            message = "Sanitized diagnostics ready. Passwords, account tokens, local_key and AppSecret are excluded."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    private func resetDiscovery() {
        central.stopScan(); watchdog?.cancel(); watchdog = nil; driver = nil
        byID.removeAll(); candidates.removeAll(); baseline.removeAll(); selectedID = nil
        secureSessionEstablished = false; sdkLocalBLEOnline = false; transportSuccessUptime = nil; authenticatedAtUptime = nil
        applicationUpdateCount = 0; exportData = nil
    }

    private func fail(_ text: String, _ kind: String) {
        watchdog?.cancel(); watchdog = nil
        sdkLocalBLEOnline = false; authenticatedAtUptime = nil
        phase = .failed; message = text; log(kind, ["message": sanitize(text)])
    }

    private func log(_ kind: String, _ details: [String: String] = [:]) {
        events.append(Event(at: Date(), monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds, kind: kind, details: details.mapValues(sanitize)))
    }

    private func sanitize(_ text: String) -> String {
        var result = text
        for key in ["NEMBRA_TUYA_APP_KEY", "NEMBRA_TUYA_APP_SECRET"] {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty { result = result.replacingOccurrences(of: value, with: "<redacted>") }
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

        var score = 0; var evidence: [String] = []
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
    static var compiled: Bool {
#if canImport(ThingSmartHomeKit)
        true
#else
        false
#endif
    }

    static var configured: Bool {
        compiled && privateCredential(named: "NEMBRA_TUYA_APP_KEY") != nil && privateCredential(named: "NEMBRA_TUYA_APP_SECRET") != nil
    }

    static var accountReady: Bool {
#if canImport(ThingSmartHomeKit)
        ThingSmartUser.sharedInstance()?.isLogin == true
#else
        false
#endif
    }

    static func bootstrapSDK() -> Bool {
#if canImport(ThingSmartHomeKit)
        guard let key = privateCredential(named: "NEMBRA_TUYA_APP_KEY"), let secret = privateCredential(named: "NEMBRA_TUYA_APP_SECRET") else { return false }
        ThingSmartSDK.sharedInstance()?.start(withAppKey: key, secretKey: secret)
        return true
#else
        return false
#endif
    }

    static func make() -> OfficialTuyaDriver? {
#if canImport(ThingSmartHomeKit)
        guard bootstrapSDK(), accountReady else { return nil }
        return SmartLifeDriver()
#else
        return nil
#endif
    }

    private static func privateCredential(named name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { return nil }
        return value
    }
}

#if canImport(ThingSmartHomeKit)
@MainActor
private final class SmartLifeDriver: NSObject, OfficialTuyaDriver, ThingSmartDeviceDelegate {
    private var device: ThingSmartDevice?
    private var onApplicationUpdate: (([String: String]) -> Void)?

    func connect(deviceID: String, uuid: String, productID: String, onApplicationUpdate: @escaping ([String: String]) -> Void, success: @escaping () -> Void, failure: @escaping (String) -> Void) {
        guard OfficialTuyaFactory.bootstrapSDK(), OfficialTuyaFactory.accountReady else {
            failure("Official Tuya SDK/account session is unavailable.")
            return
        }
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
        var opaque: [String: String] = [:]
        for (key, value) in dps { opaque[String(describing: key)] = String(describing: value) }
        onApplicationUpdate?(opaque)
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
                        HStack {
                            Text(test.passed ? "Secure scooter link established" : test.phase == .failed ? "Secure-link test stopped" : "Authentication preflight").font(.headline)
                            Spacer(); Text("\(test.applicationUpdateCount)").monospacedDigit()
                        }
                        Text(test.message).font(.footnote).foregroundStyle(.secondary)
                        if let age = test.secureSessionAgeSeconds {
                            LabeledContent("Proven local-BLE age", value: String(format: "%.1f s", age))
                            ProgressView(value: min(age / 45, 1))
                        }
                        LabeledContent("Tuya local BLE", value: test.sdkLocalBLEOnline ? "Online" : "Not proven")
                        LabeledContent("Current-session application updates", value: String(test.applicationUpdateCount))
                    }.card()

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Official Tuya gate", systemImage: "checkmark.shield").font(.headline)
                        LabeledContent("SDK compiled in", value: test.sdkCompiled ? "Yes" : "No")
                        LabeledContent("Private app config", value: test.privateConfig ? "Yes" : "No")
                        LabeledContent("SDK account authorized", value: test.sdkAccountAuthorized ? "Yes" : "No")
                        if !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized {
                            Text("NO PHYSICAL TEST YET: Tuya's official SDK/security component, matching private app credentials, and an authorized SDK account session must all be ready. Metadata QR approval alone is not BLE authentication.").font(.footnote.bold()).foregroundStyle(.orange)
                        }
                    }.card()

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
                            Button("Stop scan / use best deterministic evidence") { test.stopScan() }.buttonStyle(.bordered)
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
                                        Spacer(); Text("\(candidate.score)").monospacedDigit()
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
                                .disabled(!candidate.likely || !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized || [.authenticating, .observing, .accepted].contains(test.phase))
                        }.card()
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Acceptance", systemImage: test.passed ? "checkmark.seal.fill" : "hourglass").font(.headline).foregroundStyle(test.passed ? .green : .white)
                        Text("Pass only when Tuya's official SDK reports local BLE online continuously for at least 45 monotonic seconds and at least one application update is received after that local session became current. Nembra still assigns no DP meaning here.").font(.footnote).foregroundStyle(.secondary)
                        if test.passed { Text("Secure scooter link established\nReceiving current-session scooter data").font(.title3.bold()).foregroundStyle(.green) }
                    }.card()

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Prepare sanitized diagnostic JSON") { test.prepareExport() }.buttonStyle(.bordered)
                        if let data = test.exportData {
                            ShareLink(item: SecureTransfer(data: data, name: test.exportName), preview: SharePreview(test.exportName)) {
                                Label("Share diagnostic JSON", systemImage: "square.and.arrow.up")
                            }.buttonStyle(.borderedProminent)
                        }
                        Text("Export includes deterministic target evidence, monotonic continuity, SDK-local status, failures and opaque application-update values. It excludes passwords, account tokens, local_key and AppSecret.").font(.footnote).foregroundStyle(.secondary)
                    }.card()
                }.frame(maxWidth: 760).padding(18).frame(maxWidth: .infinity)
            }.background(Color.black.ignoresSafeArea())
        }.navigationTitle("Secure Link")
    }
}

private struct SecureTransfer: Transferable {
    let data: Data; let name: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }.suggestedFileName { $0.name }
    }
}

private extension View {
    func card() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}
