@preconcurrency import CoreBluetooth
import Foundation
import NembraBluetoothCapture
import SwiftUI

@MainActor
final class SecureLinkController: NSObject, ObservableObject {
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
        let scooterMembershipVerdict: String
        let scooterMembershipBlockReason: String?
        let sdkLocalBLEOnline: Bool
        let canonicalVerdict: String
        let canonicalBlockReason: String?
        let connectionGeneration: UInt64
        let authenticationState: String
        let authenticationMethod: String?
        let authenticatedDurationSeconds: Double?
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

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Start with the scooter OFF. This test only identifies it and proves Tuya's supported secure session."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var sdkLocalBLEOnline = false
    @Published private(set) var membershipLoading = false
    @Published private(set) var membershipVerdict: TuyaSDKAccountDeviceMembershipGate.Verdict =
        .blocked(reason: "Scooter membership has not been verified for the current SDK account.")
    @Published private(set) var exportData: Data?
    @Published private(set) var exportName = "Nembra-Secure-Link-Diagnostics.json"
    @Published private(set) var preflightSnapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
        authenticationState: .unavailable(reason: "No current authenticated read-only attempt."),
        connectionStartedAtUptimeNanoseconds: nil,
        authenticatedAtUptimeNanoseconds: nil,
        latestObservedUptimeNanoseconds: nil,
        applicationPayloadCount: 0,
        connectionGeneration: 0
    )
    @Published private(set) var preflightVerdict: TuyaAuthenticatedReadOnlyPreflight.Verdict =
        .blocked(reason: "No current Bluetooth connection generation.")

    let deviceID: String
    let deviceName: String
    let productID: String
    let tuyaUUID: String

    private var central: CBCentralManager!
    private var byID: [UUID: Candidate] = [:]
    private var baseline = Set<UUID>()
    private var driver: OfficialTuyaDriver?
    private let membershipResolver = OfficialTuyaMembershipResolver()
    private var membershipAttemptID: UUID?
    private let authority = TuyaAuthenticatedReadOnlySessionLedger()
    private var currentToken: TuyaReadOnlyConnectionToken?
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
    var applicationUpdateCount: Int { preflightSnapshot.applicationPayloadCount }
    var passed: Bool {
        if case .readyForStationaryMapping = preflightVerdict { return true }
        return false
    }
    var preflightBlockReason: String? {
        if case let .blocked(reason) = preflightVerdict { return reason }
        return nil
    }
    var scooterMembershipVerified: Bool {
        if case .authorized = membershipVerdict { return true }
        return false
    }
    var scooterMembershipBlockReason: String? {
        if case let .blocked(reason) = membershipVerdict { return reason }
        return nil
    }
    var secureSessionAgeSeconds: Double? {
        guard let start = preflightSnapshot.authenticatedAtUptimeNanoseconds,
              let end = preflightSnapshot.latestObservedUptimeNanoseconds,
              end >= start else { return nil }
        return Double(end - start) / 1_000_000_000
    }

    private var wallAgeAfterAuthentication: Double? {
        guard let start = preflightSnapshot.authenticatedAtUptimeNanoseconds else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= start else { return nil }
        return Double(now - start) / 1_000_000_000
    }

    func startBaseline() {
        guard central.state == .poweredOn else {
            stopWithFailure("Bluetooth is not ready.", "bluetooth_unavailable")
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
            stopWithFailure("Bluetooth is not ready.", "bluetooth_unavailable")
            return
        }
        phase = .scanning
        message = "Ranking OFF→ON delta, known peripheral, FD50, Tuya company ID, name and RSSI."
        log("power_on_scan_started")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        central.stopScan()
        if selectedID == nil, let best = candidates.first, best.likely { choose(best) }
        if selectedID == nil { message = "No candidate has enough scooter/Tuya evidence. Re-scan instead of guessing." }
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
        guard ![Phase.authenticating, .observing, .accepted].contains(phase) else { return }
        guard let candidate = selected, candidate.likely else {
            stopWithFailure("A strongly matched scooter candidate is required.", "candidate_not_confident")
            return
        }
        guard !deviceID.isEmpty, !tuyaUUID.isEmpty, !productID.isEmpty else {
            stopWithFailure("Tuya device ID, UUID or product ID is missing.", "tuya_identity_incomplete")
            return
        }
        guard sdkCompiled, privateConfig else {
            stopWithFailure("Official Tuya SmartLife SDK/security configuration is not provisioned. Do not run the physical test yet.", "sdk_unavailable")
            return
        }
        guard sdkAccountAuthorized else {
            stopWithFailure("The official Tuya SDK has no authorized account session. Metadata QR approval cannot substitute for SDK login.", "sdk_account_not_authorized")
            return
        }
        guard let newDriver = OfficialTuyaFactory.make() else {
            stopWithFailure("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

        central.stopScan()
        phase = .authenticating
        membershipLoading = true
        membershipVerdict = .blocked(reason: "Enumerating the current Tuya SDK account's exact home/device membership…")
        message = "Verifying this SDK account contains the exact selected scooter before BLE authentication…"
        let attemptID = UUID()
        membershipAttemptID = attemptID
        log("sdk_membership_verification_requested", ["tuyaDeviceID": deviceID])

        membershipResolver.evaluate(expectedDeviceID: deviceID) { [weak self] verdict in
            Task { @MainActor in
                self?.membershipResolved(verdict, attemptID: attemptID, candidate: candidate, driver: newDriver)
            }
        }
    }

    private func membershipResolved(
        _ verdict: TuyaSDKAccountDeviceMembershipGate.Verdict,
        attemptID: UUID,
        candidate: Candidate,
        driver newDriver: OfficialTuyaDriver
    ) {
        guard membershipAttemptID == attemptID, phase == .authenticating else {
            log("stale_membership_result_ignored")
            return
        }
        membershipLoading = false
        membershipVerdict = verdict
        guard case .authorized = verdict else {
            membershipAttemptID = nil
            stopWithFailure(scooterMembershipBlockReason ?? "Scooter membership is not authorized.", "sdk_membership_blocked")
            return
        }

        driver = newDriver
        message = "Exact scooter membership verified. Sealing a new connection generation…"
        log("sdk_membership_authorized", ["tuyaDeviceID": deviceID])

        Task { @MainActor [weak self] in
            guard let self, self.membershipAttemptID == attemptID else { return }
            do {
                let token = try await authority.beginConnection()
                currentToken = token
                try await authority.markAuthenticationStarted(for: token)
                await refreshPreflight()
                log("official_connect_requested", [
                    "coreBluetoothID": candidate.id.uuidString,
                    "tuyaDeviceID": deviceID,
                    "tuyaUUID": tuyaUUID,
                    "productID": productID,
                    "generation": String(token.diagnosticGeneration)
                ])
                newDriver.connect(
                    deviceID: deviceID,
                    uuid: tuyaUUID,
                    productID: productID,
                    onApplicationUpdate: { [weak self] update in
                        Task { @MainActor in await self?.receivedApplicationUpdate(update, token: token) }
                    },
                    success: { [weak self] in
                        Task { @MainActor in await self?.authenticated(token: token) }
                    },
                    failure: { [weak self] error in
                        Task { @MainActor in await self?.authenticationFailed(error, token: token) }
                    }
                )
            } catch {
                self.membershipAttemptID = nil
                self.stopWithFailure("Could not start the sealed authentication attempt.", "authority_begin_failed")
            }
        }
    }

    private func authenticated(token: TuyaReadOnlyConnectionToken) async {
        guard currentToken == token, phase == .authenticating, let driver else {
            log("stale_auth_success_ignored")
            return
        }
        do {
            try await authority.markAuthenticated(for: token, method: .smartLifeAppSDK)
            await refreshPreflight()
        } catch {
            log("auth_success_authority_rejected", ["error": String(describing: error)])
            return
        }
        membershipAttemptID = nil
        sdkLocalBLEOnline = driver.isLocallyConnected(uuid: tuyaUUID)
        phase = .observing
        message = "Secure Tuya session established. Waiting for application updates while the SDK remains the only BLE owner…"
        log("official_session_ready", ["localBLEOnline": sdkLocalBLEOnline ? "true" : "false"])
        startWatchdog(for: token)
    }

    private func authenticationFailed(_ text: String, token: TuyaReadOnlyConnectionToken) async {
        guard currentToken == token else {
            log("stale_auth_failure_ignored")
            return
        }
        do { try await authority.markAuthenticationFailed(for: token) }
        catch { log("auth_failure_authority_rejected", ["error": String(describing: error)]) }
        currentToken = nil
        membershipAttemptID = nil
        await refreshPreflight()
        stopWithFailure(text, "official_connect_failed")
    }

    private func receivedApplicationUpdate(_ update: [String: String], token: TuyaReadOnlyConnectionToken) async {
        guard currentToken == token else {
            log("stale_application_update_ignored")
            return
        }
        do {
            try await authority.recordApplicationUpdate(fieldCount: update.count, for: token)
            await refreshPreflight()
        } catch {
            log("application_update_authority_rejected", ["error": String(describing: error)])
            return
        }
        log("tuya_application_update", update)
        if passed {
            phase = .accepted
            message = "Secure scooter link passed. Canonical authority accepted this current-generation Tuya session."
        } else {
            message = "Receiving scooter application data · \(applicationUpdateCount) update(s). Keep it stationary until the canonical 45-second gate passes."
        }
    }

    private func startWatchdog(for token: TuyaReadOnlyConnectionToken) {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.currentToken == token, let driver = self.driver else { return }
                self.sdkLocalBLEOnline = driver.isLocallyConnected(uuid: self.tuyaUUID)
                if self.sdkLocalBLEOnline {
                    do {
                        try await self.authority.observeCurrentConnection(for: token)
                        await self.refreshPreflight()
                    } catch {
                        self.log("liveness_authority_rejected", ["error": String(describing: error)])
                        return
                    }
                } else if (self.wallAgeAfterAuthentication ?? 0) > 2 {
                    await self.invalidateCurrentAttempt(
                        token: token,
                        message: "Tuya's local BLE session dropped before acceptance. Export diagnostics; do not repeat the outdoor ride capture.",
                        kind: "sdk_local_ble_dropped"
                    )
                    return
                }

                if self.passed {
                    self.phase = .accepted
                    self.message = "Secure scooter link passed. Canonical authority accepted the current SDK-owned session."
                    self.log("acceptance_passed", [
                        "generation": String(self.preflightSnapshot.connectionGeneration),
                        "applicationUpdates": String(self.applicationUpdateCount)
                    ])
                    return
                }
                if (self.secureSessionAgeSeconds ?? 0) > 60, self.applicationUpdateCount == 0 {
                    await self.invalidateCurrentAttempt(
                        token: token,
                        message: "The secure session survived, but Tuya delivered no application update within 60 seconds.",
                        kind: "no_application_updates"
                    )
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func invalidateCurrentAttempt(token: TuyaReadOnlyConnectionToken, message: String, kind: String) async {
        guard currentToken == token else { return }
        do { try await authority.invalidateAttempt(for: token) }
        catch { log("attempt_invalidation_authority_rejected", ["error": String(describing: error)]) }
        currentToken = nil
        await refreshPreflight()
        stopWithFailure(message, kind)
    }

    private func refreshPreflight() async {
        let snapshot = await authority.currentPreflightSnapshot()
        preflightSnapshot = snapshot
        preflightVerdict = TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot)
    }

    func prepareExport() {
        let canonicalVerdict: String
        let canonicalBlockReason: String?
        switch preflightVerdict {
        case .readyForStationaryMapping:
            canonicalVerdict = "readyForStationaryMapping"
            canonicalBlockReason = nil
        case let .blocked(reason):
            canonicalVerdict = "blocked"
            canonicalBlockReason = reason
        }
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
            scooterMembershipVerdict: scooterMembershipVerified ? "authorized" : "blocked",
            scooterMembershipBlockReason: scooterMembershipBlockReason,
            sdkLocalBLEOnline: sdkLocalBLEOnline,
            canonicalVerdict: canonicalVerdict,
            canonicalBlockReason: canonicalBlockReason,
            connectionGeneration: preflightSnapshot.connectionGeneration,
            authenticationState: authenticationStateName,
            authenticationMethod: preflightSnapshot.authenticationMethod?.rawValue,
            authenticatedDurationSeconds: secureSessionAgeSeconds,
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
            message = "Sanitized diagnostics ready. SDK application values are not raw FD50 bytes; secrets remain excluded."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    private var authenticationStateName: String {
        switch preflightSnapshot.authenticationState {
        case .unavailable: return "unavailable"
        case .waitingForAuthentication: return "waitingForAuthentication"
        case .authenticating: return "authenticating"
        case .authenticated: return "authenticated"
        case .failed: return "failed"
        }
    }

    private func resetDiscovery() {
        central.stopScan()
        watchdog?.cancel()
        watchdog = nil
        driver = nil
        membershipAttemptID = nil
        membershipLoading = false
        membershipVerdict = .blocked(reason: "Scooter membership must be re-verified for the next authentication attempt.")
        byID.removeAll()
        candidates.removeAll()
        baseline.removeAll()
        selectedID = nil
        sdkLocalBLEOnline = false
        exportData = nil
    }

    private func stopWithFailure(_ text: String, _ kind: String) {
        watchdog?.cancel()
        watchdog = nil
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
            if let secret = ProcessInfo.processInfo.environment[key], !secret.isEmpty {
                result = result.replacingOccurrences(of: secret, with: "<redacted>")
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
        let expectedName = name?.localizedCaseInsensitiveContains("demo") == true
            || name?.localizedCaseInsensitiveContains("tuya") == true
            || old?.expectedName == true
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
