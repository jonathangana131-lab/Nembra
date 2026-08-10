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
                    Text("P0 · TUYA AUTHENTICATION")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(.green)
                    Text("Prove the secure scooter link first.")
                        .font(.largeTitle.bold())
                    Text("No ride calibration is available here. The next physical run is stationary and only proves supported Tuya authentication, at least 45 s continuity, and real FD50 notification bytes.")
                        .foregroundStyle(.secondary)
                    safety
                    account
                    if tuya.isLinked { devices }
                }
                .frame(maxWidth: 760)
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Nembra Capture")
        }
    }

    private var safety: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Read-only control boundary", systemImage: "shield.checkered")
                .font(.headline)
            Text("The existing QR account link is metadata/ownership discovery only. Nembra does not turn local_key into a BLE login key or synthesize/fuzz FD50 authentication frames.")
                .foregroundStyle(.secondary)
            Text("No unbind, reset, lock, speed, light, mode, throttle, brake, firmware, or other DP command is sent.")
                .font(.footnote.bold())
                .foregroundStyle(.green)
        }
        .card()
    }

    private var account: some View {
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
                Button("Reset account link") { tuya.resetLink() }
                    .buttonStyle(.bordered)
            }
        }
        .card()
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2 · Choose the scooter", systemImage: "bicycle")
                .font(.headline)
            if tuya.devices.isEmpty {
                Button("Refresh Tuya devices") { tuya.refreshDevices() }
                    .buttonStyle(.bordered)
            }
            ForEach(tuya.devices) { d in
                VStack(alignment: .leading, spacing: 7) {
                    Text(d.name.isEmpty ? "Unnamed Tuya device" : d.name)
                        .font(.headline)
                    Text([d.productName, d.category].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(tuya.selectedDeviceID == d.id ? "Refresh metadata" : "Use this device") {
                            tuya.selectDevice(d)
                        }
                        .buttonStyle(.bordered)

                        if tuya.selectedDeviceID == d.id,
                           tuya.phase == .ready,
                           !d.productID.isEmpty,
                           !d.uuid.isEmpty {
                            NavigationLink("Secure link test") { SecureLinkView(device: d) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(12)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Only Tuya device UUID + product ID enter the secure-link controller; local_key does not.")
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
        var ads: Int
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
        let kind: String
        let details: [String: String]
        let hex: String?
        let base64: String?
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
        let secureSessionEstablished: Bool
        let secureSessionAgeSeconds: Double?
        let applicationNotificationCount: Int
        let candidates: [Candidate]
        let secretsRedacted: Bool
        let dpCommandsSent: Bool
        let events: [Event]
    }

    static let known = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    static let fd50 = CBUUID(string: "FD50")
    static let notify = CBUUID(string: "00000002-0000-1001-8001-00805F9B07D0")

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Start with the scooter OFF. This is only an identification + authentication test."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var packetCount = 0
    @Published private(set) var secure = false
    @Published private(set) var exportData: Data?
    @Published private(set) var exportName = "Nembra-Secure-Link-Diagnostics.json"

    let deviceID: String
    let deviceName: String
    let productID: String
    let tuyaUUID: String

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var byID: [UUID: Candidate] = [:]
    private var baseline = Set<UUID>()
    private var selectedPeripheral: CBPeripheral?
    private var driver: OfficialTuyaDriver?
    private var authUptime: UInt64?
    private var acceptRaw = false
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

    var age: Double? {
        guard let authUptime else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        return now >= authUptime ? Double(now - authUptime) / 1e9 : nil
    }

    var passed: Bool {
        secure &&
        (phase == .observing || phase == .accepted) &&
        packetCount > 0 &&
        (age ?? 0) >= 45
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
        message = "Baseline saved. Turn the scooter ON."
        log("baseline_saved", ["count": String(baseline.count)])
    }

    func scanOn() {
        guard central.state == .poweredOn else {
            fail("Bluetooth is not ready.", "bluetooth_unavailable")
            return
        }
        phase = .scanning
        message = "Ranking OFF→ON delta, known UUID, FD50, Tuya company ID, name, and RSSI."
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        log("power_on_scan_started")
    }

    func stopScan() {
        central.stopScan()
        if selectedID == nil, let candidate = candidates.first, candidate.likely {
            choose(candidate)
        }
        if selectedID == nil {
            message = "No candidate has enough scooter/Tuya evidence yet."
        }
        log("scan_stopped")
    }

    func choose(_ candidate: Candidate) {
        central.stopScan()
        selectedID = candidate.id
        selectedPeripheral = peripherals[candidate.id]
        phase = .selected
        message = candidate.likely
            ? "Likely scooter selected automatically from evidence."
            : "Evidence is not strong enough; re-scan instead of guessing."
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
        guard let peripheral = selectedPeripheral,
              let candidate = selected,
              candidate.likely else {
            fail("A strongly matched scooter candidate is required.", "candidate_not_confident")
            return
        }
        guard !tuyaUUID.isEmpty, !productID.isEmpty else {
            fail("Tuya UUID/product ID is missing.", "tuya_identity_incomplete")
            return
        }
        guard sdkCompiled, privateConfig else {
            fail(
                "Official Tuya SmartLife SDK/security configuration is not provisioned. Do not run the physical test yet.",
                "sdk_unavailable"
            )
            return
        }
        guard sdkAccountAuthorized else {
            fail(
                "The official Tuya SDK has no authorized account session. The metadata QR session cannot substitute for SDK login.",
                "sdk_account_not_authorized"
            )
            return
        }
        guard let provider = OfficialTuyaFactory.make() else {
            fail("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

        driver = provider
        phase = .authenticating
        message = "Tuya is establishing its supported secure BLE session. Nembra sends no DP command."
        log(
            "official_connect_requested",
            [
                "coreBluetoothID": peripheral.identifier.uuidString,
                "tuyaUUID": tuyaUUID,
                "productID": productID
            ]
        )
        provider.connect(
            uuid: tuyaUUID,
            productID: productID,
            success: { [weak self] in
                Task { @MainActor in self?.authenticated() }
            },
            failure: { [weak self] message in
                Task { @MainActor in self?.fail(message, "official_connect_failed") }
            }
        )
    }

    private func authenticated() {
        guard phase == .authenticating, let peripheral = selectedPeripheral else { return }
        secure = true
        acceptRaw = true
        authUptime = DispatchTime.now().uptimeNanoseconds
        phase = .observing
        message = "Secure scooter link established. Attaching passive FD50 notification observer…"
        log("official_session_ready")
        peripheral.delegate = self
        central.connect(peripheral)
        startWatchdog()
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.secure else { return }
                if self.passed {
                    self.phase = .accepted
                    self.message = "Receiving scooter data. Secure link passed the 45-second gate."
                    self.log("acceptance_passed", ["packets": String(self.packetCount)])
                    return
                }
                if (self.age ?? 0) > 60, self.packetCount == 0 {
                    self.fail(
                        "Secure session survived, but no post-auth FD50 notification arrived within 60 seconds.",
                        "no_notifications"
                    )
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func prepareExport() {
        let export = Export(
            schemaVersion: 1,
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
            secureSessionEstablished: secure,
            secureSessionAgeSeconds: age,
            applicationNotificationCount: packetCount,
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
            exportName = "Nembra-Secure-Link-\(deviceID.prefix(8))-Diagnostics.json"
            message = "Sanitized diagnostics ready; passwords, tokens, local_key and AppSecret are excluded."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    private func resetDiscovery() {
        central.stopScan()
        watchdog?.cancel()
        watchdog = nil
        peripherals.removeAll()
        byID.removeAll()
        candidates.removeAll()
        baseline.removeAll()
        selectedID = nil
        selectedPeripheral = nil
        secure = false
        acceptRaw = false
        authUptime = nil
        packetCount = 0
        exportData = nil
    }

    private func fail(_ message: String, _ kind: String) {
        watchdog?.cancel()
        watchdog = nil
        acceptRaw = false
        phase = .failed
        self.message = message
        log(kind, ["message": sanitize(message)])
    }

    private func log(_ kind: String, _ details: [String: String] = [:], raw: Data? = nil) {
        events.append(
            Event(
                at: Date(),
                kind: kind,
                details: details.mapValues(sanitize),
                hex: raw.map { $0.map { String(format: "%02X", $0) }.joined() },
                base64: raw?.base64EncodedString()
            )
        )
    }

    private func sanitize(_ string: String) -> String {
        var result = string
        for key in ["NEMBRA_TUYA_APP_KEY", "NEMBRA_TUYA_APP_SECRET"] {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                result = result.replacingOccurrences(of: value, with: "<redacted>")
            }
        }
        return result
    }

    private static func tuyaCompany(_ data: Data?) -> Bool {
        guard let data, data.count >= 2 else { return false }
        return (UInt16(data[data.startIndex]) |
                UInt16(data[data.index(after: data.startIndex)]) << 8) == 0x07D0
    }

    private func update(_ peripheral: CBPeripheral, _ advertisement: [String: Any], _ rssiNumber: NSNumber) {
        let id = peripheral.identifier
        peripherals[id] = peripheral
        if phase == .baseline { baseline.insert(id) }

        let old = byID[id]
        let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? old?.name
        let rssi = rssiNumber.intValue == 127 ? old?.rssi : rssiNumber.intValue
        let uuids =
            ((advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []) +
            ((advertisement[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []) +
            ((advertisement[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID]) ?? [])
        let serviceData = advertisement[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let hasFD50 = uuids.contains(Self.fd50) || serviceData?.keys.contains(Self.fd50) == true || old?.fd50 == true
        let hasTuyaCompany =
            Self.tuyaCompany(advertisement[CBAdvertisementDataManufacturerDataKey] as? Data) ||
            old?.tuyaCompany == true
        let knownID = id == Self.known
        let newAfterPowerOn = (phase == .scanning && !baseline.contains(id)) || old?.newAfterPowerOn == true
        let expectedName =
            name?.localizedCaseInsensitiveContains("demo") == true ||
            name?.localizedCaseInsensitiveContains("tuya") == true ||
            old?.expectedName == true

        var score = 0
        var evidence: [String] = []
        if knownID { score += 1000; evidence.append("known previous UUID") }
        if hasFD50 { score += 500; evidence.append("FD50") }
        if hasTuyaCompany { score += 350; evidence.append("Tuya company 0x07D0") }
        if newAfterPowerOn { score += 180; evidence.append("appeared after power-on") }
        if expectedName { score += 100; evidence.append("expected name") }
        if let rssi {
            if rssi >= -50 {
                score += 80
                evidence.append("very close RSSI")
            } else if rssi >= -65 {
                score += 50
                evidence.append("nearby RSSI")
            } else if rssi >= -80 {
                score += 20
            }
        }

        byID[id] = Candidate(
            id: id,
            name: name,
            rssi: rssi,
            ads: (old?.ads ?? 0) + 1,
            newAfterPowerOn: newAfterPowerOn,
            fd50: hasFD50,
            tuyaCompany: hasTuyaCompany,
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
        rssi: NSNumber
    ) {
        update(peripheral, advertisementData, rssi)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard acceptRaw, selectedID == peripheral.identifier else { return }
        log("observer_connected")
        peripheral.delegate = self
        peripheral.discoverServices([Self.fd50])
        message = "Secure scooter link established. Looking for FD50 notify 0002…"
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard acceptRaw, selectedID == peripheral.identifier else { return }
        fail(
            "Passive observer could not attach: \(error?.localizedDescription ?? "unknown")",
            "observer_connect_failed"
        )
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard selectedID == peripheral.identifier else { return }
        log("observer_disconnected", ["error": error?.localizedDescription ?? ""])
        if secure && phase != .accepted {
            fail(
                "Secure link disconnected before acceptance. Export diagnostics; do not repeat the ride capture.",
                "disconnect_before_acceptance"
            )
        }
    }
}

extension SecureLinkController: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            fail("FD50 discovery failed: \(error.localizedDescription)", "fd50_discovery_failed")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.fd50 }) else {
            fail("FD50 service missing.", "fd50_missing")
            return
        }
        peripheral.discoverCharacteristics([Self.notify], for: service)
        log("fd50_found")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            fail("Notify discovery failed: \(error.localizedDescription)", "notify_discovery_failed")
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.notify }),
              characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
            fail("FD50 notify characteristic 0002 missing.", "notify_missing")
            return
        }
        peripheral.setNotifyValue(true, for: characteristic)
        log("notify_subscription_requested")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            fail("Notification subscription failed: \(error.localizedDescription)", "subscription_failed")
            return
        }
        log("notify_state", ["enabled": characteristic.isNotifying ? "true" : "false"])
        if characteristic.isNotifying {
            message = "Secure scooter link established. Waiting for post-auth FD50 bytes…"
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard acceptRaw, characteristic.uuid == Self.notify, characteristic.isNotifying else { return }
        if let error {
            log("notification_error", ["error": error.localizedDescription])
            return
        }
        guard let value = characteristic.value, !value.isEmpty else { return }
        packetCount += 1
        log("post_auth_fd50_notification", ["bytes": String(value.count)], raw: value)
        if passed {
            phase = .accepted
            message = "Receiving scooter data. Secure link passed."
        } else {
            message = "Receiving scooter data · \(packetCount) packet(s). Keep it stationary until 45 s."
        }
    }
}

@MainActor
private protocol OfficialTuyaDriver: AnyObject {
    func connect(
        uuid: String,
        productID: String,
        success: @escaping () -> Void,
        failure: @escaping (String) -> Void
    )
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
        guard configured,
              let key = ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_KEY"],
              !key.isEmpty,
              let secret = ProcessInfo.processInfo.environment["NEMBRA_TUYA_APP_SECRET"],
              !secret.isEmpty else {
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

@MainActor
private final class TuyaSDKAccountAuthorization: ObservableObject {
    @Published var email = ""
    @Published var countryCode = "1"
    @Published var verificationCode = ""
    @Published private(set) var statusMessage = "Checking the official Tuya SDK account gate…"
    @Published private(set) var isBusy = false

    init() {
        refresh()
    }

    var isAuthorized: Bool { OfficialTuyaFactory.accountReady }

    func refresh() {
        guard OfficialTuyaFactory.compiled else {
            statusMessage = "ThingSmartHomeKit is not compiled into this build."
            return
        }
        guard OfficialTuyaFactory.configured else {
            statusMessage = "Private Tuya AppKey/AppSecret are not injected into this Xcode run."
            return
        }
        guard OfficialTuyaFactory.bootstrap() else {
            statusMessage = "The official Tuya SDK could not be initialized."
            return
        }
        statusMessage = isAuthorized
            ? "Official Tuya SDK account session is authorized."
            : "SDK initialized. Authorize an SDK account before the secure BLE test."
    }

    func sendLoginCode() {
        guard !isBusy else { return }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCountry = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)

        guard OfficialTuyaFactory.bootstrap() else {
            refresh()
            return
        }
        guard !normalizedEmail.isEmpty, !normalizedCountry.isEmpty else {
            statusMessage = "Email and country code are required."
            return
        }

        isBusy = true
        statusMessage = "Requesting a one-time Tuya SDK login code…"
#if canImport(ThingSmartHomeKit)
        ThingSmartUser.sharedInstance()?.sendVerifyCode(
            withUserName: normalizedEmail,
            countryCode: normalizedCountry,
            type: 2,
            success: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.isBusy = false
                    self.statusMessage = "Verification code sent. Enter it below to authorize the SDK account."
                }
            },
            failure: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isBusy = false
                    self.statusMessage = "Tuya verification-code request failed: \(error?.localizedDescription ?? "unknown error")"
                }
            }
        )
#else
        isBusy = false
#endif
    }

    func authorize() {
        guard !isBusy else { return }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCountry = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)

        guard OfficialTuyaFactory.bootstrap() else {
            refresh()
            return
        }
        guard !normalizedEmail.isEmpty, !normalizedCountry.isEmpty, !normalizedCode.isEmpty else {
            statusMessage = "Email, country code, and verification code are required."
            return
        }

        isBusy = true
        verificationCode = ""
        statusMessage = "Authorizing the official Tuya SDK account session…"
#if canImport(ThingSmartHomeKit)
        ThingSmartUser.sharedInstance()?.login(
            withEmail: normalizedEmail,
            countryCode: normalizedCountry,
            code: normalizedCode,
            success: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.isBusy = false
                    self.refresh()
                    if self.isAuthorized {
                        self.statusMessage = "Official Tuya SDK account authorized. Device ownership still must be accepted by Tuya; Nembra will fail closed if the scooter is not available to this SDK account."
                    }
                }
            },
            failure: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isBusy = false
                    self.statusMessage = "Official Tuya SDK login failed: \(error?.localizedDescription ?? "unknown error")"
                }
            }
        )
#else
        isBusy = false
#endif
    }
}

#if canImport(ThingSmartHomeKit)
@MainActor
private final class SmartLifeDriver: NSObject, OfficialTuyaDriver {
    func connect(
        uuid: String,
        productID: String,
        success: @escaping () -> Void,
        failure: @escaping (String) -> Void
    ) {
        guard OfficialTuyaFactory.bootstrap() else {
            failure("Private Tuya SDK credentials are missing.")
            return
        }
        ThingSmartBLEManager.sharedInstance().connectBLE(
            withUUID: uuid,
            productKey: productID,
            success: success,
            failure: {
                failure("Tuya SmartLife SDK did not establish the BLE session.")
            }
        )
    }
}
#endif

@MainActor
private struct SecureLinkView: View {
    @StateObject private var test: SecureLinkController
    @StateObject private var sdkAccount = TuyaSDKAccountAuthorization()

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
                    status
                    sdk
                    discovery
                    if let candidate = test.selected { selected(candidate) }
                    acceptance
                    export
                }
                .frame(maxWidth: 760)
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
        }
        .navigationTitle("Secure Link")
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(
                    test.passed
                        ? "Secure scooter link established"
                        : test.phase == .failed
                            ? "Secure-link test stopped"
                            : "Authentication preflight"
                )
                .font(.headline)
                Spacer()
                Text("\(test.packetCount)")
                    .monospacedDigit()
            }
            Text(test.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let age = test.age {
                LabeledContent("Secure-session age", value: String(format: "%.1f s", age))
                ProgressView(value: min(age / 45, 1))
            }
            LabeledContent("Post-auth FD50 packets", value: String(test.packetCount))
        }
        .card()
    }

    private var sdk: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Official Tuya gate", systemImage: "checkmark.shield")
                .font(.headline)
            LabeledContent("SDK compiled in", value: test.sdkCompiled ? "Yes" : "No")
            LabeledContent("Private app config", value: test.privateConfig ? "Yes" : "No")
            LabeledContent("SDK account authorized", value: test.sdkAccountAuthorized ? "Yes" : "No")
            Text(sdkAccount.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if test.sdkCompiled, test.privateConfig, !test.sdkAccountAuthorized {
                TextField("Tuya SDK account email", text: $sdkAccount.email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .textFieldStyle(.roundedBorder)
                TextField("Country code, e.g. 1", text: $sdkAccount.countryCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(sdkAccount.isBusy ? "Working…" : "Send one-time code") {
                        sdkAccount.sendLoginCode()
                    }
                    .buttonStyle(.bordered)
                    .disabled(sdkAccount.isBusy || sdkAccount.email.isEmpty || sdkAccount.countryCode.isEmpty)

                    TextField("Verification code", text: $sdkAccount.verificationCode)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .textFieldStyle(.roundedBorder)
                }
                Button(sdkAccount.isBusy ? "Authorizing…" : "Authorize official SDK session") {
                    sdkAccount.authorize()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    sdkAccount.isBusy ||
                    sdkAccount.email.isEmpty ||
                    sdkAccount.countryCode.isEmpty ||
                    sdkAccount.verificationCode.isEmpty
                )
                Text("Nembra uses Tuya's documented one-time email-code login. It never asks for or stores the Tuya account password, and the code is cleared before the login callback returns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized {
                Text("NO PHYSICAL TEST YET: official SDK/security component, matching private app credentials, and an authorized SDK account session must all be ready.")
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            }
        }
        .card()
    }

    private var discovery: some View {
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
                Button("Scan after power-on") { test.scanOn() }
                    .buttonStyle(.borderedProminent)
            case .scanning:
                Button("Stop scan / use best evidence") { test.stopScan() }
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
                            if candidate.likely {
                                Text("LIKELY SCOOTER")
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
            }
        }
        .card()
    }

    private func selected(_ candidate: SecureLinkController.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Authentication gate", systemImage: "key.horizontal")
                .font(.headline)
            Text(candidate.evidence.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Start secure read-only test") { test.authenticate() }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !candidate.likely ||
                    !test.sdkCompiled ||
                    !test.privateConfig ||
                    !test.sdkAccountAuthorized ||
                    [.authenticating, .observing, .accepted].contains(test.phase)
                )
        }
        .card()
    }

    private var acceptance: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                "Acceptance",
                systemImage: test.passed ? "checkmark.seal.fill" : "hourglass"
            )
            .font(.headline)
            .foregroundStyle(test.passed ? .green : .white)
            Text("Pass only when Tuya's official session succeeds, it survives at least 45 seconds, and at least one genuine post-auth FD50 notification is captured. No DP meaning is inferred here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if test.passed {
                Text("Secure scooter link established\nReceiving scooter data")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
            }
        }
        .card()
    }

    private var export: some View {
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
            Text("Export includes candidate evidence, timings, failures, and post-auth raw bytes; it excludes passwords, verification codes, tokens, local_key, and AppSecret.")
                .font(.footnote)
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
