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
#if canImport(NembraTuyaPrivateConfig)
import NembraTuyaPrivateConfig
#endif

let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable

@main @MainActor
struct NembraCaptureApp: App {
    var body: some Scene {
        WindowGroup { CaptureP0Root().preferredColorScheme(.dark) }
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
                    Text("The next physical run is stationary. It proves current SDK account authority, exact scooter membership, a fresh repeated OFF1→ON1→OFF2→ON2 Bluetooth correlation, Tuya-owned authentication, genuine same-generation application updates, and a sealed 45-second observation prefix.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Read-only control boundary", systemImage: "shield.checkered")
                            .font(.headline)
                        Text("Nembra never turns local_key into a BLE login key, invents Tuya authentication frames, or opens a second CoreBluetooth connection after Tuya's SDK owns BLE.")
                            .foregroundStyle(.secondary)
                        Text("No DP query, DP publish, unbind, reset, lock, speed, light, mode, throttle, brake, firmware, or other scooter command is sent.")
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
            Label("2 · Choose the scooter", systemImage: "bicycle").font(.headline)
            if tuya.devices.isEmpty {
                Button("Refresh Tuya devices") { tuya.refreshDevices() }.buttonStyle(.bordered)
            }
            ForEach(tuya.devices) { device in
                VStack(alignment: .leading, spacing: 7) {
                    Text(device.name.isEmpty ? "Unnamed Tuya device" : device.name).font(.headline)
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
            Text("The metadata bridge supplies device identity only. local_key never enters the BLE authentication controller.")
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
        var advertisements: Int?
        var newAfterPowerOn: Bool
        var fd50: Bool
        var tuyaCompany: Bool
        var historicalCaptureID: Bool
        var freshlyCorrelated: Bool
        var expectedName: Bool
        var score: Int
        var evidence: [String]

        var title: String { name?.isEmpty == false ? name! : "Correlated Bluetooth target" }
        // Current target authority is earned only by the package-owned repeated
        // OFF1→ON1→OFF2→ON2 correlation series. A historical capture UUID may
        // remain descriptive evidence but never mints current-session authority.
        var likely: Bool { freshlyCorrelated }
    }

    enum Phase: String, Codable {
        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed
    }

    struct Export: Codable {
        let schemaVersion: Int
        let purpose: String
        let exportedAt: Date
        let buildIdentifier: String
        let sourceCommitSHA: String
        let tuyaDeviceID: String
        let tuyaUUID: String
        let productID: String
        let selectedPeripheralID: String?
        let phase: Phase
        let privateConfigPresent: Bool
        let sdkAccountLoggedIn: Bool
        let sdkDeviceMembershipVerified: Bool
        let secureSessionEstablished: Bool
        let canonicalObservedAgeSeconds: Double?
        let sdkLocalBLEOnline: Bool
        let applicationUpdateCount: Int
        let connectionGeneration: UInt64
        let authenticationMethod: String?
        let preflightVerdict: String
        let applicationValueRepresentation: String
        let rawFD50BytesCaptured: Bool
        let secretsRedacted: Bool
        let dpQueriesSent: Bool
        let dpCommandsSent: Bool
        let candidates: [Candidate]
        let events: [Event]
    }

    struct Event: Codable {
        let at: Date
        let kind: String
        let details: [String: String]
    }

    static let historicalCapturePeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    static let fd50 = CBUUID(string: "FD50")
    private static let maximumObservationPollGapNanoseconds = TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Log in the official SDK account and verify the exact scooter before Bluetooth discovery."
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

    private let buildIdentity = NembraCaptureBuildIdentity.current
    private var central: CBCentralManager!
    private var byID: [UUID: Candidate] = [:]
    private var baseline = Set<UUID>()
    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?
    private var driver: OfficialTuyaDriver?
    private var events: [Event] = []
    private var watchdog: Task<Void, Never>?
    private let sessionLedger = TuyaAuthenticatedReadOnlySessionLedger()
    private var currentConnectionToken: TuyaReadOnlyConnectionToken?
    private var localBLESettlementToken: TuyaReadOnlyConnectionToken?
    private var membershipAccountUID: String?
    private var membershipDeviceID: String?
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

    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }
    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }
    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }
    var selected: Candidate? { selectedID.flatMap { byID[$0] } }
    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }
    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }
    var correlationWindowIsScanning: Bool { correlationProgress?.isScanning == true }
    var correlationObservedCandidateCount: Int { correlationProgress?.currentObservedCandidateCount ?? 0 }
    var correlationCompletedWindowCount: Int { correlationProgress?.completedWindowCount ?? 0 }

    var correlationWindowLabel: String {
        guard let phase = correlationProgress?.phase else { return "OFF1" }
        switch phase {
        case .firstPoweredOff: return "OFF1"
        case .firstPoweredOn: return "ON1"
        case .secondPoweredOff: return "OFF2"
        case .secondPoweredOn: return "ON2"
        }
    }

    var correlationWindowInstruction: String {
        guard let phase = correlationProgress?.phase else { return "Keep the scooter OFF and stationary." }
        return phase.operatorExpectedPowerOn
            ? "Turn the scooter ON and keep it stationary."
            : "Turn the scooter OFF and keep it stationary."
    }

    private var accountIdentityLeaseSnapshot: TuyaSDKAccountIdentityLeaseGate.Snapshot {
        .init(
            sdkIsLoggedIn: sdkAccountLoggedIn,
            currentAccountUID: currentAccountUID,
            membershipAccountUID: membershipAccountUID,
            expectedDeviceID: deviceID,
            membershipDeviceID: membershipDeviceID
        )
    }

    var accountIdentityLeaseIsAuthorized: Bool {
        TuyaSDKAccountIdentityLeaseGate.verdict(for: accountIdentityLeaseSnapshot) == .authorized
    }

    var secureSessionEstablished: Bool {
        if case .authenticated = ledgerSnapshot.authenticationState { return true }
        return false
    }

    var canonicalObservedAgeSeconds: Double? {
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

    func startBaseline() {
        guard buildIdentity.isAuthoritativeFieldBuild else {
            failLocally(buildIdentity.blocker ?? "Exact field-build provenance is unavailable.", "field_build_identity_unavailable")
            return
        }
        guard privateConfig, sdkAccountLoggedIn else {
            failLocally("Private Tuya app identity and a current SDK login are required before any scooter correlation scan.", "sdk_authority_required_before_scan")
            return
        }

        // Every physical attempt receives a fresh complete current-account membership verdict
        // before the package-owned four-window Bluetooth correlation series may start.
        verifySDKMembership { [weak self] authorized in
            guard let self else { return }
            let leaseVerdict = TuyaSDKAccountIdentityLeaseGate.verdict(for: self.accountIdentityLeaseSnapshot)
            guard authorized,
                  self.sdkAccountLoggedIn,
                  leaseVerdict == .authorized else {
                self.failLocally("Exact scooter membership could not be proven for this same current SDK account. Bluetooth correlation remains disabled.", "sdk_device_membership_required_before_scan")
                return
            }
            self.beginCorrelationSeries()
        }
    }

    private func beginCorrelationSeries() {
        guard privateConfig,
              sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally("SDK account/device authority changed before Bluetooth correlation began.", "sdk_authority_changed_before_scan")
            return
        }
        guard currentConnectionToken == nil else {
            failLocally(
                "A prior authenticated generation has not been terminally retired. Relaunch Capture before starting another attempt.",
                "active_generation_blocks_discovery_reset"
            )
            return
        }

        resetDiscoverySessionOnly()
        do {
            correlationSession = try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)
            log("target_correlation_series_created", [
                "method": "package-owned-fresh-manager-off1-on1-off2-on2",
                "minimumWindowSeconds": "10"
            ])
            startCurrentCorrelationWindow()
        } catch {
            failLocally("Could not create the bounded Bluetooth correlation series: \(error.localizedDescription)", "target_correlation_series_create_failed")
        }
    }

    func startNextCorrelationWindow() {
        guard phase == .powerOn else { return }
        startCurrentCorrelationWindow()
    }

    private func startCurrentCorrelationWindow() {
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
            failLocally("SDK account/device authority changed before the next correlation window.", "sdk_authority_changed_during_target_correlation")
            return
        }
        guard let session = correlationSession,
              let progress = session.progress else {
            failLocally("Fresh Bluetooth correlation authority is unavailable. Restart from OFF1.", "target_correlation_authority_unavailable")
            return
        }

        let label = correlationWindowLabel
        do {
            try session.startCurrentWindow()
            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline
            message = "\(label) requested with a fresh CoreBluetooth manager. Wait for scanner liveness, then keep this state for at least 10 receipt-bounded seconds before sealing it."
            log("target_correlation_window_started", [
                "window": label,
                "operatorExpectedPowerOn": String(progress.phase.operatorExpectedPowerOn),
                "completedWindows": String(progress.completedWindowCount)
            ])
        } catch {
            session.abandonCurrentWindow()
            correlationSession = nil
            failLocally("The \(label) correlation window failed closed: \(error.localizedDescription). Restart from OFF1.", "target_correlation_window_start_failed")
        }
    }

    func finishCorrelationWindow() {
        guard phase == .baseline || phase == .scanning,
              let session = correlationSession else { return }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            session.abandonCurrentWindow()
            correlationSession = nil
            failLocally("SDK account/device authority changed during Bluetooth correlation. Restart from OFF1 after re-verifying membership.", "sdk_authority_changed_during_target_correlation")
            return
        }

        let sealedLabel = correlationWindowLabel
        do {
            let final = try session.finishCurrentWindow()
            if let final {
                finishCorrelationSeries(final)
                return
            }

            phase = .powerOn
            message = "\(sealedLabel) sealed. \(correlationWindowInstruction) When the scooter has settled, start \(correlationWindowLabel)."
            log("target_correlation_window_sealed", [
                "window": sealedLabel,
                "completedWindows": String(correlationCompletedWindowCount)
            ])
        } catch let error as PassiveBluetoothPowerCycleObservationSessionError {
            switch error {
            case .minimumWindowDurationNotReached:
                message = "Keep \(sealedLabel) unchanged a little longer. The package has not yet earned the required 10 receipt-bounded seconds."
            case .scanReadinessPending:
                message = "\(sealedLabel) is still waiting for confirmed CoreBluetooth scan liveness. Do not advance the physical state yet."
            default:
                session.abandonCurrentWindow()
                correlationSession = nil
                failLocally("\(sealedLabel) failed closed (\(String(describing: error))). Restart the complete OFF1→ON1→OFF2→ON2 series.", "target_correlation_window_failed")
            }
        } catch {
            session.abandonCurrentWindow()
            correlationSession = nil
            failLocally("\(sealedLabel) failed closed: \(error.localizedDescription). Restart the complete correlation series.", "target_correlation_window_failed")
        }
    }

    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {
        switch result.correlation.disposition {
        case let .singleRepeatableCandidate(id):
            let historicalCaptureID = id == Self.historicalCapturePeripheral
            var evidence = ["fresh OFF1→ON1→OFF2→ON2 full-UUID correlation"]
            if historicalCaptureID {
                evidence.append("matches C7D09A22 capture-local UUID descriptive")
            }
            let candidate = Candidate(
                id: id,
                name: nil,
                rssi: nil,
                advertisements: nil,
                newAfterPowerOn: true,
                fd50: false,
                tuyaCompany: false,
                historicalCaptureID: historicalCaptureID,
                freshlyCorrelated: true,
                expectedName: false,
                score: 0,
                evidence: evidence
            )
            byID = [id: candidate]
            candidates = [candidate]
            selectedID = nil
            correlationSession = nil
            phase = .correlated
            message = "Scooter signal found by the complete repeated power-cycle series. Confirm this correlated Bluetooth target before Tuya may take BLE ownership. This is current-session correlation evidence, not permanent scooter identity."
            log("candidate_correlation_ready", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id-awaiting-operator-confirmation",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])

        case let .ambiguousRepeatableCandidates(ids):
            correlationSession = nil
            failLocally("Fresh correlation remained ambiguous across \(ids.count) repeatable full UUIDs. Do not guess from name, RSSI, FD50, or Tuya hints; restart from OFF1 after reducing nearby-device ambiguity.", "target_correlation_ambiguous")

        case .noRepeatableCandidate:
            correlationSession = nil
            failLocally("No full UUID repeated the required OFF1→ON1→OFF2→ON2 pattern. Do not fall back to the historical capture UUID; restart the fresh correlation series.", "target_correlation_no_repeatable_candidate")

        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            correlationSession = nil
            failLocally("The package rejected correlation provenance/chronology. Restart from OFF1; prior windows cannot be spliced into a new attempt.", "target_correlation_provenance_rejected")
        }
    }

    func invalidateSDKMembership() {
        let token = currentConnectionToken
        membershipRequestID = UUID()
        membershipBusy = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        if phase == .baseline || phase == .powerOn || phase == .scanning {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        central.stopScan()
        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {
            phase = .failed
            message = "SDK account authority changed. Discovery stopped before any authenticated BLE attempt."
        }
        if (phase == .authenticating || phase == .observing), let token {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.invalidateSourceAuthority(
                    token: token,
                    message: "SDK account authority changed during the authenticated attempt.",
                    kind: "sdk_source_authority_lost"
                )
            }
        }
        log("sdk_membership_invalidated")
    }

    func confirmCorrelatedTarget(_ candidate: Candidate) {
        guard phase == .correlated,
              selectedID == nil,
              candidate.freshlyCorrelated,
              byID[candidate.id] == candidate else {
            failLocally("Only the single target earned by this exact OFF1→ON1→OFF2→ON2 series can be confirmed.", "target_confirmation_rejected")
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Current Tuya account/device authority changed before target confirmation.", "sdk_authority_changed_before_target_confirmation")
            return
        }
        selectedID = candidate.id
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this attempt. This confirmation does not establish durable scooter identity. Tuya may now take sole BLE ownership for the read-only authentication test."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "authority": "operator-confirmed-current-session-correlation",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }

    func verifySDKMembership(completion: ((Bool) -> Void)? = nil) {
        membershipAccountUID = nil
        membershipDeviceID = nil
        guard privateConfig else {
            sdkDeviceMembershipVerified = false
            membershipStatus = "Private Tuya app identity / official SDK integration is not provisioned."
            completion?(false)
            return
        }
        guard sdkAccountLoggedIn, currentAccountUID != nil else {
            sdkDeviceMembershipVerified = false
            membershipStatus = "The official Tuya SDK account has no current UID authority."
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
        membershipStatus = "Checking every current SDK home for the exact scooter device ID…"
        let probe = OfficialTuyaMembershipProbe(expectedDeviceID: expected) { [weak self] result in
            Task { @MainActor in
                guard let self, self.membershipRequestID == requestID else { return }
                self.membershipBusy = false
                self.membershipProbe = nil
                switch result.verdict {
                case .authorized:
                    self.membershipAccountUID = result.membershipAccountUID
                    self.membershipDeviceID = expected
                    let lease = TuyaSDKAccountIdentityLeaseGate.verdict(for: self.accountIdentityLeaseSnapshot)
                    guard lease == .authorized else {
                        self.sdkDeviceMembershipVerified = false
                        self.membershipAccountUID = nil
                        self.membershipDeviceID = nil
                        self.membershipStatus = "Tuya account identity changed while scooter membership was being verified. Verify again under the current account."
                        self.log("sdk_account_identity_lease_blocked")
                        completion?(false)
                        return
                    }
                    self.sdkDeviceMembershipVerified = true
                    self.membershipStatus = "Exact scooter membership verified and leased to this current SDK account."
                    self.log("sdk_device_membership_verified", [
                        "loadedHomes": String(result.loadedHomeCount),
                        "ownedDevices": String(result.ownedDeviceCount),
                        "sharedDevices": String(result.sharedDeviceCount)
                    ])
                    completion?(true)
                case let .blocked(reason):
                    self.sdkDeviceMembershipVerified = false
                    self.membershipAccountUID = nil
                    self.membershipDeviceID = nil
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
            failLocally("A fresh repeated OFF1→ON1→OFF2→ON2 Bluetooth correlation is required before Tuya BLE ownership.", "candidate_not_authoritative")
            return
        }
        guard buildIdentity.isAuthoritativeFieldBuild else {
            failLocally(buildIdentity.blocker ?? "Exact field-build provenance is unavailable.", "field_build_identity_unavailable")
            return
        }
        guard !deviceID.isEmpty, !tuyaUUID.isEmpty, !productID.isEmpty else {
            failLocally("Tuya device ID, UUID or product ID is missing.", "tuya_identity_incomplete")
            return
        }
        guard privateConfig, sdkAccountLoggedIn, sdkDeviceMembershipVerified, accountIdentityLeaseIsAuthorized else {
            failLocally("Private Tuya SDK configuration, current same-account membership and exact scooter authority are required.", "sdk_authority_unavailable")
            return
        }

        // Membership is re-proven immediately before granting Tuya BLE ownership.
        verifySDKMembership { [weak self] stillAuthorized in
            guard let self else { return }
            guard stillAuthorized,
                  self.sdkAccountLoggedIn,
                  self.accountIdentityLeaseIsAuthorized,
                  self.selectedID == candidate.id else {
                self.failLocally("Exact scooter/account authority could not be re-verified immediately before BLE authentication.", "sdk_device_membership_recheck_failed")
                return
            }
            self.beginOfficialConnection(candidate: candidate)
        }
    }

    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected || phase == .failed else { return }
        guard candidate.likely,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Tuya account/device authority changed before connection start.", "sdk_authority_changed")
            return
        }
        guard let newDriver = OfficialTuyaFactory.make() else {
            failLocally("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

        central.stopScan()
        driver = newDriver
        watchdog?.cancel()
        watchdog = nil
        sdkLocalBLEOnline = false
        localBLESettlementToken = nil
        phase = .authenticating
        message = "Tuya's SDK is establishing the supported secure BLE session. Nembra sends no DP query or command."

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = try await self.sessionLedger.beginConnection()
                self.currentConnectionToken = token
                do {
                    try await self.sessionLedger.markAuthenticationStarted(for: token)
                } catch {
                    await self.invalidateChronologyIntegrity(
                        token: token,
                        message: "Authenticated-session chronology could not start safely: \(error.localizedDescription)",
                        kind: "session_auth_start_rejected"
                    )
                    return
                }
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
                        Task { @MainActor in
                            await self?.receivedApplicationUpdate(update, token: token)
                        }
                    },
                    success: { [weak self] in
                        Task { @MainActor in await self?.authenticated(token: token) }
                    },
                    failure: { [weak self] in
                        Task { @MainActor in await self?.authenticationFailed(token: token) }
                    }
                )
            } catch {
                self.failLocally("Could not create a fresh authenticated-session generation: \(error.localizedDescription)", "session_generation_failed")
            }
        }
    }

    private func authenticated(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_success_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        if phase == .observing {
            log("duplicate_connect_success_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard phase == .authenticating else {
            await invalidateSourceAuthority(
                token: token,
                message: "Tuya transport success arrived outside the active authentication phase. The generation was retired instead of being left hidden.",
                kind: "sdk_transport_success_outside_authentication"
            )
            return
        }
        guard localBLESettlementToken != token else {
            log("duplicate_connect_success_settlement_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            await invalidateSourceAuthority(
                token: token,
                message: "Tuya account/device source authority changed before transport success could enter local-BLE settlement.",
                kind: "sdk_source_authority_lost_before_local_ble_settlement"
            )
            return
        }
        guard let driver else {
            await invalidateSourceAuthority(
                token: token,
                message: "Official Tuya driver authority disappeared before local-BLE settlement.",
                kind: "sdk_driver_authority_lost_before_local_ble_settlement"
            )
            return
        }

        localBLESettlementToken = token
        defer {
            if localBLESettlementToken == token {
                localBLESettlementToken = nil
            }
        }

        let acquisitionStarted = DispatchTime.now().uptimeNanoseconds
        while currentConnectionToken == token, phase == .authenticating {
            guard accountIdentityLeaseIsAuthorized else {
                await invalidateSourceAuthority(
                    token: token,
                    message: "Tuya account/device source authority changed while local BLE status was settling.",
                    kind: "sdk_source_authority_lost_during_local_ble_settlement"
                )
                return
            }

            let observedAt = DispatchTime.now().uptimeNanoseconds
            let isLocallyOnline = driver.isLocallyConnected(uuid: tuyaUUID)
            switch TuyaLocalBLEAcquisitionWindow.verdict(
                startedAtUptimeNanoseconds: acquisitionStarted,
                observedAtUptimeNanoseconds: observedAt,
                isLocallyOnline: isLocallyOnline,
                maximumWaitNanoseconds: TuyaLocalBLEAcquisitionWindow.maximumWaitNanoseconds
            ) {
            case .observedOnline:
                sdkLocalBLEOnline = true
                do {
                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    await refreshLedgerSnapshot()
                    phase = .observing
                    message = "Authenticated generation \(token.diagnosticGeneration) is live. Waiting for a genuine application update and the canonical 45-second horizon…"
                    log("sdk_local_ble_authenticated", [
                        "generation": String(token.diagnosticGeneration),
                        "localBLEOnline": "true"
                    ])
                    startWatchdog(token: token)
                } catch {
                    await invalidateChronologyIntegrity(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
                return

            case .keepWaiting:
                try? await Task.sleep(for: .milliseconds(200))

            case .timedOut:
                await authenticationAcquisitionFailed(
                    token: token,
                    message: "Tuya reported transport success, but current local-BLE status did not become authoritative within the bounded settlement window.",
                    kind: "sdk_local_ble_settlement_timed_out"
                )
                return

            case .invalidClock:
                await invalidateChronologyIntegrity(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return
            }
        }
    }

    private func invalidateChronologyIntegrity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        try? await sessionLedger.markChronologyIntegrityInvalidated(for: token)
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        await authenticationAcquisitionFailed(
            token: token,
            message: "Tuya SmartLife SDK did not establish the supported BLE session.",
            kind: "official_connect_failed"
        )
    }

    private func authenticationAcquisitionFailed(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markAuthenticationFailed(for: token)
        } catch {
            await invalidateChronologyIntegrity(token: token, message: message, kind: kind + "_chronology_fallback")
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func receivedApplicationUpdate(
        _ update: [String: String],
        token: TuyaReadOnlyConnectionToken
    ) async {
        guard !update.isEmpty else { return }
        guard currentConnectionToken == token else {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard phase == .observing else {
            log("application_update_outside_observation_ignored", [
                "generation": String(token.diagnosticGeneration),
                "phase": phase.rawValue
            ])
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
            await invalidateSourceAuthority(
                token: token,
                message: "SDK account/device source authority changed before application evidence arrived.",
                kind: "sdk_source_authority_changed_during_observation"
            )
            return
        }
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }

        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
            message = "Receiving same-generation scooter application data · \(applicationUpdateCount) update(s). Canonical readiness still depends on the sealed observation horizon."
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch {
            await invalidateObservationContinuity(
                token: token,
                message: "Application chronology failed closed: \(error.localizedDescription)",
                kind: "application_update_rejected"
            )
        }
    }

    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            var previousPollUptime = DispatchTime.now().uptimeNanoseconds

            while !Task.isCancelled {
                guard let self,
                      self.currentConnectionToken == token,
                      self.secureSessionEstablished,
                      let driver = self.driver else { return }

                let now = DispatchTime.now().uptimeNanoseconds
                guard now >= previousPollUptime else {
                    await self.invalidateChronologyIntegrity(
                        token: token,
                        message: "Authenticated observation chronology failed closed because the monotonic clock regressed.",
                        kind: "observation_clock_regressed"
                    )
                    return
                }

                let gap = now - previousPollUptime
                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.",
                        kind: "observation_poll_gap_exceeded"
                    )
                    return
                }
                previousPollUptime = now

                guard self.sdkAccountLoggedIn,
                      self.sdkDeviceMembershipVerified,
                      self.accountIdentityLeaseIsAuthorized else {
                    await self.invalidateSourceAuthority(
                        token: token,
                        message: "SDK account/device source authority changed during authenticated observation.",
                        kind: "sdk_source_authority_lost_during_observation"
                    )
                    return
                }

                self.sdkLocalBLEOnline = driver.isLocallyConnected(uuid: self.tuyaUUID)
                guard self.sdkLocalBLEOnline else {
                    await self.recordObservedTransportLoss(token: token)
                    return
                }

                do {
                    try await self.sessionLedger.observeCurrentConnection(for: token)
                    await self.refreshLedgerSnapshot()
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
                    self.log("stale_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    self.log("sealed_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness chronology failed closed: \(error.localizedDescription)",
                        kind: "session_liveness_rejected"
                    )
                    return
                }

                switch TuyaAuthenticatedReadOnlyPreflight.verdict(for: self.ledgerSnapshot) {
                case .readyForStationaryMapping:
                    guard self.buildIdentity.isAuthoritativeFieldBuild else {
                        await self.invalidateSourceAuthority(
                            token: token,
                            message: self.buildIdentity.blocker ?? "Exact field-build provenance became unavailable before acceptance.",
                            kind: "field_build_identity_rejected_at_seal"
                        )
                        return
                    }
                    guard self.accountIdentityLeaseIsAuthorized else {
                        await self.invalidateSourceAuthority(
                            token: token,
                            message: "Tuya account/device source authority changed before canonical acceptance could be sealed.",
                            kind: "sdk_source_authority_rejected_at_seal"
                        )
                        return
                    }
                    do {
                        try await sessionLedger.sealAcceptedObservation(for: token)
                        self.currentConnectionToken = nil
                        await self.refreshLedgerSnapshot()
                        self.phase = .accepted
                        self.message = "Secure scooter link established. Canonical readiness was sealed before UI acceptance; delayed callbacks cannot mutate the accepted prefix."
                        self.log("acceptance_sealed", [
                            "generation": String(token.diagnosticGeneration),
                            "applicationUpdates": String(self.applicationUpdateCount),
                            "buildIdentifier": self.buildIdentity.buildIdentifier,
                            "sourceCommitSHA": self.buildIdentity.sourceCommitSHA
                        ])
                    } catch {
                        await self.invalidateObservationContinuity(
                            token: token,
                            message: "Canonical readiness could not be sealed: \(error.localizedDescription)",
                            kind: "accepted_prefix_seal_failed"
                        )
                    }
                    return

                case .blocked:
                    break
                }

                if (self.canonicalObservedAgeSeconds ?? 0) > 60,
                   self.applicationUpdateCount == 0 {
                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch {
                        await self.invalidateChronologyIntegrity(
                            token: token,
                            message: "Authenticated session reached the no-application deadline while chronology could not be sealed safely.",
                            kind: "authenticated_application_timeout_chronology_fallback"
                        )
                        return
                    }
                    self.currentConnectionToken = nil
                    self.localBLESettlementToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture."
                    self.log("authenticated_application_timeout", ["generation": String(token.diagnosticGeneration)])
                    return
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.endConnection(for: token)
        } catch {
            await invalidateChronologyIntegrity(
                token: token,
                message: "Tuya local-BLE transport ended, but session chronology also became invalid while retiring authority.",
                kind: "sdk_local_ble_drop_chronology_fallback"
            )
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        message = "Tuya's current local-BLE session ended before acceptance. Export diagnostics; do not repeat the outdoor ride capture."
        log("sdk_local_ble_dropped", ["generation": String(token.diagnosticGeneration)])
    }

    private func invalidateSourceAuthority(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markSourceAuthorityInvalidated(for: token)
        } catch {
            await invalidateChronologyIntegrity(token: token, message: message, kind: kind + "_chronology_fallback")
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func invalidateObservationContinuity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markObservationContinuityInvalidated(for: token)
        } catch {
            await invalidateChronologyIntegrity(token: token, message: message, kind: kind + "_chronology_fallback")
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func refreshLedgerSnapshot() async {
        ledgerSnapshot = await sessionLedger.currentPreflightSnapshot()
    }

    func prepareExport() {
        let envelope = Export(
            schemaVersion: 7,
            purpose: "Sanitized Tuya authenticated read-only stationary preflight",
            exportedAt: Date(),
            buildIdentifier: buildIdentity.buildIdentifier,
            sourceCommitSHA: buildIdentity.sourceCommitSHA,
            tuyaDeviceID: deviceID,
            tuyaUUID: tuyaUUID,
            productID: productID,
            selectedPeripheralID: selectedID?.uuidString,
            phase: phase,
            privateConfigPresent: privateConfig,
            sdkAccountLoggedIn: sdkAccountLoggedIn,
            sdkDeviceMembershipVerified: sdkDeviceMembershipVerified,
            secureSessionEstablished: secureSessionEstablished,
            canonicalObservedAgeSeconds: canonicalObservedAgeSeconds,
            sdkLocalBLEOnline: sdkLocalBLEOnline,
            applicationUpdateCount: applicationUpdateCount,
            connectionGeneration: ledgerSnapshot.connectionGeneration,
            authenticationMethod: ledgerSnapshot.authenticationMethod?.rawValue,
            preflightVerdict: preflightVerdictText,
            applicationValueRepresentation: "ThingSmartDeviceDelegate dpsUpdate values projected with String(describing:); application-level SDK data, not byte-exact or raw FD50 transport",
            rawFD50BytesCaptured: false,
            secretsRedacted: true,
            dpQueriesSent: false,
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
            message = "Sanitized diagnostics ready with exact compiled build provenance. No account UID, AppKey/AppSecret, password, account token, local_key, session key, raw FD50 claim, DP query, or DP command is exported."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    private func resetDiscoverySessionOnly() {
        correlationSession?.abandonCurrentWindow()
        correlationSession = nil
        central.stopScan()
        watchdog?.cancel()
        watchdog = nil
        driver = nil
        localBLESettlementToken = nil
        byID.removeAll()
        candidates.removeAll()
        baseline.removeAll()
        selectedID = nil
        sdkLocalBLEOnline = false
        exportData = nil
        // Active authenticated generations must be terminally retired by their
        // owning outcome path before a new discovery attempt. Generic reset never
        // manufactures a transport-disconnect terminal.
        assert(currentConnectionToken == nil)
    }

    private func failLocally(_ text: String, _ kind: String) {
        if phase == .baseline || phase == .powerOn || phase == .scanning {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }
        watchdog?.cancel()
        watchdog = nil
        central.stopScan()
        phase = .failed
        message = text
        log(kind, ["message": text])
    }

    private func log(_ kind: String, _ details: [String: String] = [:]) {
        events.append(Event(at: Date(), kind: kind, details: details))
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
        let fd50 = serviceUUIDs.contains(Self.fd50)
            || serviceData?.keys.contains(Self.fd50) == true
            || old?.fd50 == true
        let tuyaCompany = Self.hasTuyaCompanyID(advertisement[CBAdvertisementDataManufacturerDataKey] as? Data)
            || old?.tuyaCompany == true
        let historicalCaptureID = id == Self.historicalCapturePeripheral
        let newAfterPowerOn = (phase == .scanning && !baseline.contains(id)) || old?.newAfterPowerOn == true
        let expectedName = name?.localizedCaseInsensitiveContains("demo") == true
            || name?.localizedCaseInsensitiveContains("tuya") == true
            || old?.expectedName == true

        var score = 0
        var evidence: [String] = []
        if historicalCaptureID { evidence.append("matches C7D09A22 capture-local UUID descriptive") }
        if fd50 { score += 500; evidence.append("FD50 descriptive") }
        if tuyaCompany { score += 350; evidence.append("Tuya company 0x07D0 descriptive") }
        if newAfterPowerOn { score += 180; evidence.append("appeared after power-on descriptive") }
        if expectedName { score += 100; evidence.append("name hint descriptive") }
        if let rssi {
            if rssi >= -50 { score += 80; evidence.append("very close RSSI descriptive") }
            else if rssi >= -65 { score += 50; evidence.append("nearby RSSI descriptive") }
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
            historicalCaptureID: historicalCaptureID,
            freshlyCorrelated: false,
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
        guard phase == .baseline || phase == .scanning else { return }
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

    static var configured: Bool {
#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)
        !NembraTuyaPrivateIdentity.appKey.isEmpty && !NembraTuyaPrivateIdentity.appSecret.isEmpty
#else
        false
#endif
    }

    @discardableResult
    static func bootstrap() -> Bool {
#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)
        guard configured else { return false }
        if didBootstrap { return true }
        ThingSmartSDK.sharedInstance()?.start(
            withAppKey: NembraTuyaPrivateIdentity.appKey,
            secretKey: NembraTuyaPrivateIdentity.appSecret
        )
        didBootstrap = true
        return true
#else
        false
#endif
    }

    static var accountLoggedIn: Bool {
#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)
        guard bootstrap() else { return false }
        return ThingSmartUser.sharedInstance()?.isLogin == true
#else
        return false
#endif
    }

    static var currentAccountUID: String? {
#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)
        guard bootstrap(), ThingSmartUser.sharedInstance()?.isLogin == true,
              let rawUID = ThingSmartUser.sharedInstance()?.uid else { return nil }
        let uid = rawUID.trimmingCharacters(in: .whitespacesAndNewlines)
        return uid.isEmpty ? nil : uid
#else
        return nil
#endif
    }

    static func make() -> OfficialTuyaDriver? {
#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)
        guard bootstrap(), accountLoggedIn, currentAccountUID != nil else { return nil }
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
        let membershipAccountUID: String?
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
    private var membershipAccountUID: String?

    init(expectedDeviceID: String, completion: @escaping (Result) -> Void) {
        self.expectedDeviceID = expectedDeviceID
        self.completion = completion
    }

    func start() {
        guard OfficialTuyaFactory.bootstrap(),
              OfficialTuyaFactory.accountLoggedIn,
              let currentAccountUID = OfficialTuyaFactory.currentAccountUID else {
            finish(enumerationCompleted: false)
            return
        }
        membershipAccountUID = currentAccountUID
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
            verdict: TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: expectedDeviceID, snapshot: snapshot),
            membershipAccountUID: membershipAccountUID,
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
        guard OfficialTuyaFactory.configured else {
            status = "Private Tuya AppKey/AppSecret + official SmartLife SDK are not provisioned in this field build."
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
            ? "Official Tuya SDK account is logged in. Exact scooter membership must still be freshly verified before Bluetooth discovery."
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
                        self?.status = "Tuya could not send the verification code: \(Self.redactedError(error, submittedIdentity: identity))"
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
                        self?.status = "Tuya could not send the verification code: \(Self.redactedError(error, submittedIdentity: identity))"
                    }
                }
            )
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    func login() {
        guard OfficialTuyaFactory.bootstrap() else {
            status = "Tuya SDK initialization failed closed."
            return
        }
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
                failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error, submittedIdentity: identity) } }
            )
        case .phone:
            ThingSmartUser.sharedInstance()?.login(
                withMobile: identity,
                countryCode: country,
                code: code,
                success: { [weak self] in Task { @MainActor in self?.finishLoginSuccess() } },
                failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error, submittedIdentity: identity) } }
            )
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    private func finishLoginSuccess() {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = loggedIn
            ? "Official Tuya SDK account is logged in. Nembra must freshly verify exact scooter membership before Bluetooth discovery."
            : "Tuya returned a login-success callback, but the SDK reports no current logged-in session. Bluetooth remains disabled."
    }

    private func finishLoginFailure(_ error: Error?, submittedIdentity: String) {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya SDK login failed: \(Self.redactedError(error, submittedIdentity: submittedIdentity))"
    }

    private static func redactedError(_ error: Error?, submittedIdentity: String) -> String {
        let raw = error?.localizedDescription ?? "unknown error"
        let identity = submittedIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty else { return raw }
        return raw.replacingOccurrences(
            of: identity,
            with: "<redacted-account>",
            options: [.caseInsensitive, .literal]
        )
    }
}

@MainActor
private struct SecureLinkView: View {
    @StateObject private var test: SecureLinkController
    @StateObject private var sdkAccount = OfficialTuyaAccountAuthorizer()

    init(device: TuyaAccountBridge.LinkedDevice) {
        _test = StateObject(wrappedValue: SecureLinkController(device: device))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SMALLEST INDOOR TEST").font(.caption.monospaced().bold()).foregroundStyle(.green)
                    Text("Correlate. Authenticate. Seal.").font(.largeTitle.bold())
                    Text("Keep the scooter stationary. Do not run the old 17-step sequence.").foregroundStyle(.secondary)
                    statusCard
                    authorityCard
                    if test.privateConfig && !sdkAccount.loggedIn { sdkAuthorizationCard }
                    discoveryCard
                    if let candidate = test.selected { authenticationCard(candidate) }
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
        .task {
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
            if loggedIn { test.verifySDKMembership() }
            else { test.invalidateSDKMembership() }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(test.phase == .accepted ? "Secure scooter link established" : test.phase == .failed ? "Secure-link test stopped" : "Authentication preflight")
                    .font(.headline)
                Spacer()
                Text("\(test.applicationUpdateCount)").monospacedDigit()
            }
            Text(test.message).font(.footnote).foregroundStyle(.secondary)
            if let age = test.canonicalObservedAgeSeconds {
                LabeledContent("Canonical observed age", value: String(format: "%.1f s", age))
                ProgressView(value: min(age / 45, 1))
            }
            LabeledContent("Connection generation", value: String(test.ledgerSnapshot.connectionGeneration))
            LabeledContent("Tuya local BLE", value: test.sdkLocalBLEOnline ? "Online" : "Not proven")
            LabeledContent("Same-generation updates", value: String(test.applicationUpdateCount))
        }
        .card()
    }

    private var authorityCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Official Tuya authority", systemImage: "checkmark.shield").font(.headline)
            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact provenance verified" : "Not authoritative")
            LabeledContent("Private SDK config", value: test.privateConfig ? "Present" : "Missing")
            LabeledContent("SDK account logged in", value: test.sdkAccountLoggedIn ? "Yes" : "No")
            LabeledContent("Exact scooter membership", value: test.sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized ? "Verified for current account" : test.membershipBusy ? "Checking…" : "Not verified")
            Text(test.membershipStatus).font(.footnote).foregroundStyle(test.sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized ? .green : .secondary)
            if test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized) {
                Button(test.membershipBusy ? "Checking scooter membership…" : "Verify scooter in SDK account") { test.verifySDKMembership() }
                    .buttonStyle(.bordered)
                    .disabled(test.membershipBusy)
            }
            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: the private exact field build, current SDK account identity, and exact scooter membership must all be proven before even the OFF baseline scan can start.")
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            }
        }
        .card()
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Correlate this-session Bluetooth target", systemImage: "scope").font(.headline)
            Text("Authority requires one package-owned OFF1→ON1→OFF2→ON2 series. Each window uses a fresh CoreBluetooth manager. Name, RSSI, FD50, Tuya company ID, and the C7D09A22 UUID are non-authoritative hints only.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            switch test.phase {
            case .idle, .failed:
                Button("Start OFF1 correlation") { test.startBaseline() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)

            case .baseline, .scanning:
                Text("\(test.correlationWindowLabel) · \(test.correlationWindowInstruction)")
                    .font(.headline)
                LabeledContent("Fresh manager scan", value: test.correlationWindowIsScanning ? "Live" : "Starting…")
                LabeledContent("Completed windows", value: "\(test.correlationCompletedWindowCount) / 4")
                LabeledContent("Unique candidates this window", value: String(test.correlationObservedCandidateCount))
                Button("Seal \(test.correlationWindowLabel) window") { test.finishCorrelationWindow() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.correlationWindowIsScanning)

            case .powerOn:
                Text("Next: \(test.correlationWindowLabel) · \(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            case .correlated:
                Text("Scooter signal found").font(.headline)
                Text("One full CoreBluetooth target repeated across the complete four-window series. Confirm it explicitly before authentication. This is current-session correlation evidence, not permanent scooter identity.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let candidate = test.candidates.first(where: { $0.freshlyCorrelated }) {
                    Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget(candidate) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)
                }

            default:
                EmptyView()
            }

            ForEach(test.candidates.prefix(8)) { candidate in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(candidate.title).bold()
                        if candidate.likely {
                            Text("FRESH CORRELATION")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green, in: Capsule())
                                .foregroundStyle(.black)
                        }
                        Spacer()
                    }
                    Text(candidate.id.uuidString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(candidate.evidence.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private func authenticationCard(_ candidate: SecureLinkController.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Authentication gate", systemImage: "key.horizontal").font(.headline)
            Text(candidate.evidence.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
            Button("Start secure read-only test") { test.authenticate() }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !candidate.likely
                        || !test.privateConfig
                        || !test.sdkAccountLoggedIn
                        || !test.sdkDeviceMembershipVerified
                        || !test.accountIdentityLeaseIsAuthorized
                        || test.membershipBusy
                        || [.authenticating, .observing, .accepted].contains(test.phase)
                )
        }
        .card()
    }

    private var acceptanceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Canonical acceptance", systemImage: test.phase == .accepted ? "checkmark.seal.fill" : "hourglass")
                .font(.headline)
                .foregroundStyle(test.phase == .accepted ? .green : .white)
            Text("The product does not maintain a parallel readiness boolean. The canonical preflight verdict is evaluated from the current generation and sealed only after exact build + same-account source authority are re-checked.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(test.preflightVerdictText).font(.caption.monospaced()).foregroundStyle(.secondary)
            if test.phase == .accepted {
                Text("Accepted prefix sealed\nDelayed callbacks retired")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
            }
        }
        .card()
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Prepare sanitized diagnostic JSON") { test.prepareExport() }.buttonStyle(.bordered)
            if let data = test.exportData {
                ShareLink(item: SecureTransfer(data: data, name: test.exportName), preview: SharePreview(test.exportName)) {
                    Label("Share diagnostic JSON", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            Text("Export includes exact build identity, current-session correlated target ID, SDK membership state, canonical generation/chronology, local-BLE status, terminal state, and opaque application-value projections. Account UID remains process-local and is not exported. It explicitly records rawFD50BytesCaptured=false, dpQueriesSent=false, and dpCommandsSent=false.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var sdkAuthorizationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Log in the official SDK account", systemImage: "person.crop.circle.badge.checkmark").font(.headline)
            Text(sdkAccount.status).font(.footnote).foregroundStyle(.secondary)
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
                Button("Log in SDK account") { sdkAccount.login() }
                    .buttonStyle(.borderedProminent)
                    .disabled(sdkAccount.busy || sdkAccount.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Nembra never asks for or persists the Tuya password. Verification codes stay in memory and are cleared after login. Submitted email/phone values are redacted from Tuya error text. Login alone cannot start Bluetooth discovery.")
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
