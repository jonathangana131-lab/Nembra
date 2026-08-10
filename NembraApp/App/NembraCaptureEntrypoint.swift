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
        let tuyaDependencyLockSHA256: String
        let tuyaDeviceID: String
        let tuyaUUID: String
        let productID: String
        let selectedPeripheralID: String?
        let targetCorrelationMethod: String?
        let targetCorrelationWindowCount: Int?
        let targetCorrelationOperatorConfirmed: Bool
        let targetCorrelationProvenance: CorrelationProvenance?
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

    /// Sanitized, replayable projection of the exact package-issued four-window
    /// target-correlation result. This preserves why a full UUID was correlated;
    /// it does not promote that UUID into permanent scooter identity.
    struct CorrelationProvenance: Codable, Equatable {
        struct Window: Codable, Equatable {
            let phase: String
            let operatorExpectedPowerOn: Bool
            let windowSequence: UInt64
            let startedAtUptimeNanoseconds: UInt64
            let endedAtUptimeNanoseconds: UInt64
            let observedCandidateCount: Int
        }

        struct Snapshot: Codable, Equatable {
            struct Candidate: Codable, Equatable {
                let peripheralID: String
                let isConnectable: Bool?
            }

            let observationSeriesID: String
            let windowSequence: UInt64
            let candidates: [Candidate]
        }

        let method: String
        let windows: [Window]
        let observationSnapshots: [Snapshot]
        let disposition: String
        let repeatableCandidateIDs: [String]

        init(result: PassiveBluetoothPowerCycleObservationResult) {
            method = "package-owned-fresh-manager-off1-on1-off2-on2"
            windows = result.windows.map { receipt in
                Window(
                    phase: Self.phaseLabel(receipt.phase),
                    operatorExpectedPowerOn: receipt.phase.operatorExpectedPowerOn,
                    windowSequence: receipt.windowSequence.rawValue,
                    startedAtUptimeNanoseconds: receipt.startedAtUptimeNanoseconds,
                    endedAtUptimeNanoseconds: receipt.endedAtUptimeNanoseconds,
                    observedCandidateCount: receipt.observedCandidateCount
                )
            }
            observationSnapshots = result.observationSnapshots.map { snapshot in
                Snapshot(
                    observationSeriesID: snapshot.observationSeriesIdentity.rawValue.uuidString,
                    windowSequence: snapshot.windowSequence.rawValue,
                    candidates: snapshot.candidates.map { candidate in
                        Snapshot.Candidate(
                            peripheralID: candidate.id.uuidString,
                            isConnectable: candidate.isConnectable
                        )
                    }
                )
            }
            disposition = Self.dispositionLabel(result.correlation.disposition)
            repeatableCandidateIDs = result.correlation.repeatableCandidateIdentifiers.map(\.uuidString)
        }

        private static func phaseLabel(_ phase: PassiveBluetoothPowerCycleObservationPhase) -> String {
            switch phase {
            case .firstPoweredOff: return "OFF1"
            case .firstPoweredOn: return "ON1"
            case .secondPoweredOff: return "OFF2"
            case .secondPoweredOn: return "ON2"
            }
        }

        private static func dispositionLabel(
            _ disposition: PassiveBluetoothPowerCycleTargetCorrelationReport.Disposition
        ) -> String {
            switch disposition {
            case .invalidObservationAuthority: return "invalidObservationAuthority"
            case .invalidObservationWindowOrder: return "invalidObservationWindowOrder"
            case .noRepeatableCandidate: return "noRepeatableCandidate"
            case .ambiguousRepeatableCandidates: return "ambiguousRepeatableCandidates"
            case .singleRepeatableCandidate: return "singleRepeatableCandidate"
            }
        }
    }

    static let historicalCapturePeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    private static let maximumObservationPollGapNanoseconds = TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var message = "Log in the official SDK account and verify the exact scooter before Bluetooth discovery."
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var pendingCorrelatedTargetID: UUID?
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
    private var byID: [UUID: Candidate] = [:]
    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?
    private var correlationProvenance: CorrelationProvenance?
    private var targetCorrelationMethod: String?
    private var targetCorrelationWindowCount: Int?
    private var targetCorrelationOperatorConfirmed = false
    private var driver: OfficialTuyaDriver?
    private var events: [Event] = []
    private var captureAttemptEventStartIndex = 0
    private var applicationUpdateAdmissionsInFlight = 0
    private var acceptanceCutIsClosed = false
    private var sealedAcceptedEventPrefix: [Event]?
    private var sealedAcceptedExport: Export?
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
        log("controller_created")
    }

    deinit { watchdog?.cancel() }

    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }
    var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }
    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }
    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }
    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }
    var selected: Candidate? { selectedID.flatMap { byID[$0] } }
    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }
    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }
    var correlationWindowIsScanning: Bool { correlationProgress?.isScanning == true }
    var correlationObservedCandidateCount: Int { correlationProgress?.currentObservedCandidateCount ?? 0 }
    var correlationCompletedWindowCount: Int { correlationProgress?.completedWindowCount ?? 0 }

    func consumeCorrelationAsyncInvalidation() {
        guard (phase == .baseline || phase == .scanning),
              correlationProgress?.isSeriesInvalidated == true else { return }
        correlationSession = nil
        failLocally(
            "Bluetooth correlation ended before this window could be sealed because package-owned scanner/Bluetooth authority became unavailable. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series.",
            "target_correlation_async_invalidated"
        )
    }

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

        // Accepted app evidence belongs to this physical attempt only. The controller's
        // diagnostic log intentionally survives failures for troubleshooting, so establish an
        // explicit custody boundary before fresh membership/correlation evidence can begin.
        captureAttemptEventStartIndex = events.count
        sealedAcceptedEventPrefix = nil

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
            if let token = currentConnectionToken {
                Task { @MainActor [weak self] in
                    await self?.invalidateInternalLifecycle(
                        token: token,
                        message: "A prior package-owned generation existed when OFF1 restart was requested. It was retired fail-closed; start the correlation series again from OFF1.",
                        kind: "active_generation_blocks_discovery_reset"
                    )
                }
            }
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
        // Preserve the package-issued receipts + exact catalogs before releasing the live scanner.
        // The artifact can therefore audit/replay correlation without trusting a detached UUID.
        correlationProvenance = CorrelationProvenance(result: result)
        targetCorrelationMethod = correlationProvenance?.method
        targetCorrelationWindowCount = result.windows.count
        targetCorrelationOperatorConfirmed = false
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
            pendingCorrelatedTargetID = id
            correlationSession = nil
            phase = .correlated
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. Confirm that correlated Bluetooth target for this attempt before Tuya authentication. Correlation is current-session evidence, not permanent scooter identity."
            log("candidate_correlated", [
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

    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              let id = pendingCorrelatedTargetID,
              let candidate = byID[id],
              candidate.freshlyCorrelated else {
            pendingCorrelatedTargetID = nil
            failLocally("A current-session correlated Bluetooth target is not awaiting confirmation. Restart from OFF1.", "correlated_target_confirmation_unavailable")
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            pendingCorrelatedTargetID = nil
            failLocally("Tuya account/device authority changed before target confirmation. Re-verify membership and restart correlation.", "sdk_authority_changed_before_target_confirmation")
            return
        }
        guard currentConnectionToken == nil else {
            pendingCorrelatedTargetID = nil
            if let token = currentConnectionToken {
                Task { @MainActor [weak self] in
                    await self?.invalidateInternalLifecycle(
                        token: token,
                        message: "An impossible active session generation existed during target confirmation. It was retired fail-closed; restart from OFF1.",
                        kind: "active_generation_blocks_target_confirmation"
                    )
                }
            }
            return
        }

        selectedID = id
        pendingCorrelatedTargetID = nil
        targetCorrelationOperatorConfirmed = true
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this attempt. This remains current-session correlation evidence, not permanent scooter identity. Current same-account Tuya membership remains the independent authentication authority."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "authority": "explicit-operator-confirmation-of-current-session-correlation",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }

    func invalidateSDKMembership() {
        let token = currentConnectionToken
        membershipRequestID = UUID()
        membershipBusy = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        pendingCorrelatedTargetID = nil
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
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
                  self.phase == .selected,
                  self.targetCorrelationOperatorConfirmed,
                  self.sdkAccountLoggedIn,
                  self.accountIdentityLeaseIsAuthorized,
                  self.selectedID == candidate.id else {
                self.failLocally("Exact confirmed scooter/account authority could not be re-verified immediately before BLE authentication.", "sdk_device_membership_recheck_failed")
                return
            }
            self.beginOfficialConnection(candidate: candidate)
        }
    }

    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected else { return }
        guard targetCorrelationOperatorConfirmed,
              selectedID == candidate.id,
              candidate.likely,
              buildIdentity.isAuthoritativeFieldBuild,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Confirmed build or Tuya account/device authority changed before connection start.", "sdk_authority_changed")
            return
        }
        guard let newDriver = OfficialTuyaFactory.make() else {
            failLocally("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

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
                // Own the package generation before any later mutation can fail. Otherwise an
                // auth-start clock regression could strand callback authority in the ledger.
                self.currentConnectionToken = token
                do {
                    try await self.sessionLedger.markAuthenticationStarted(for: token)
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    do {
                        try await self.sessionLedger.markInternalLifecycleFailure(for: token)
                    } catch {
                        self.phase = .failed
                        self.message = "Authentication chronology failed and the exact generation could not be retired. Relaunch Capture before another attempt."
                        self.log("auth_start_terminal_retirement_failed", [
                            "generation": String(token.diagnosticGeneration),
                            "error": error.localizedDescription
                        ])
                        return
                    }
                    self.currentConnectionToken = nil
                    self.localBLESettlementToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authentication chronology failed closed before the Tuya connection request. The exact generation was retired without sampling the broken clock again."
                    self.log("auth_start_clock_regressed", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication-start lifecycle mutation failed closed before the Tuya connection request: \(error.localizedDescription)",
                        kind: "auth_start_lifecycle_rejected"
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
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication promotion failed closed because monotonic chronology regressed.",
                        kind: "session_auth_promotion_clock_regressed"
                    )
                } catch {
                    await invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication promotion violated the current internal session lifecycle: \(error.localizedDescription)",
                        kind: "session_auth_promotion_rejected"
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
                await invalidateInternalLifecycle(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed. The exact generation was retired without resampling that clock.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return
            }
        }
    }

    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            await invalidateSourceAuthority(
                token: token,
                message: "Tuya account/device source authority changed before the SDK failure callback was classified.",
                kind: "sdk_source_authority_lost_before_auth_failure"
            )
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
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                self.message = "Authentication terminal chronology failed and the exact generation could not be retired. Relaunch Capture before another attempt."
                log("authentication_terminal_retirement_failed", [
                    "generation": String(token.diagnosticGeneration),
                    "error": error.localizedDescription
                ])
                return
            }
        } catch {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                self.message = "Authentication failure could not terminally retire the exact generation. Relaunch Capture before another attempt."
                log("authentication_terminal_retirement_failed", [
                    "generation": String(token.diagnosticGeneration),
                    "error": error.localizedDescription
                ])
                return
            }
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
        guard !acceptanceCutIsClosed else {
            log("application_update_after_acceptance_cut_ignored", [
                "generation": String(token.diagnosticGeneration)
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

        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
            message = "Receiving same-generation scooter application data · \(applicationUpdateCount) update(s). Canonical readiness still depends on the sealed observation horizon."
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateInternalLifecycle(
                token: token,
                message: "Application receipt chronology failed closed because the monotonic clock regressed.",
                kind: "application_receipt_clock_regressed"
            )
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
            await mirrorAlreadyTerminalObservationContinuity(
                token: token,
                message: "Application receipt crossed the package-owned continuous-observation horizon. The package already retired this generation; no disconnect is claimed.",
                kind: "application_observation_continuity_invalidated"
            )
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch {
            await invalidateInternalLifecycle(
                token: token,
                message: "Application receipt violated the current internal session lifecycle: \(error.localizedDescription)",
                kind: "application_update_lifecycle_rejected"
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
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated observation chronology regressed. The exact generation was retired without sampling the broken clock again.",
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
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated liveness chronology regressed. The exact generation was retired without another clock sample.",
                        kind: "session_liveness_clock_regressed"
                    )
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                    await self.mirrorAlreadyTerminalObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness crossed the package-owned continuous-observation horizon. The package already retired this generation; no disconnect is claimed.",
                        kind: "session_liveness_continuity_invalidated"
                    )
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
                    self.log("stale_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    self.log("sealed_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated liveness violated the current internal session lifecycle: \(error.localizedDescription)",
                        kind: "session_liveness_lifecycle_rejected"
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
                    guard self.applicationUpdateAdmissionsInFlight == 0 else {
                        break
                    }
                    self.acceptanceCutIsClosed = true
                    // Freeze only the current physical attempt. Older failed-attempt diagnostics stay
                    // available in the live controller log but cannot contaminate accepted evidence.
                    let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))
                    do {
                        try await sessionLedger.sealAcceptedObservation(for: token)
                        guard self.buildIdentity.isAuthoritativeFieldBuild,
                              self.accountIdentityLeaseIsAuthorized else {
                            self.currentConnectionToken = nil
                            self.localBLESettlementToken = nil
                            self.sdkLocalBLEOnline = false
                            self.driver = nil
                            self.phase = .failed
                            self.message = "Source authority changed while canonical acceptance was sealing. Restart from OFF1; the sealed package chronology is diagnostic only."
                            self.log("source_authority_changed_during_acceptance_seal", [
                                "generation": String(token.diagnosticGeneration)
                            ])
                            return
                        }
                        guard let driver = self.driver else {
                            self.currentConnectionToken = nil
                            self.localBLESettlementToken = nil
                            self.sdkLocalBLEOnline = false
                            self.phase = .failed
                            self.message = "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Restart from OFF1; no disconnect time is inferred."
                            self.log("sdk_local_ble_authority_missing_after_acceptance_seal", [
                                "generation": String(token.diagnosticGeneration)
                            ])
                            return
                        }
                        let postSealLocalBLEOnline = driver.isLocallyConnected(uuid: self.tuyaUUID)
                        self.sdkLocalBLEOnline = postSealLocalBLEOnline
                        guard postSealLocalBLEOnline else {
                            self.currentConnectionToken = nil
                            self.localBLESettlementToken = nil
                            self.driver = nil
                            self.phase = .failed
                            self.message = "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Restart from OFF1; no disconnect time is inferred."
                            self.log("sdk_local_ble_not_current_after_acceptance_seal", [
                                "generation": String(token.diagnosticGeneration)
                            ])
                            return
                        }
                        self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut
                        self.currentConnectionToken = nil
                        self.sealedAcceptedExport = self.makeExport(
                            exportedAt: Date(),
                            phase: .accepted,
                            events: acceptedEventPrefixAtCut
                        )
                        self.exportData = nil
                        self.phase = .accepted
                        self.message = "Secure scooter link established. Canonical readiness and the complete accepted artifact were frozen before UI acceptance; delayed callbacks cannot mutate accepted evidence."
                        self.log("acceptance_sealed", [
                            "generation": String(token.diagnosticGeneration),
                            "applicationUpdates": String(self.applicationUpdateCount),
                            "buildIdentifier": self.buildIdentity.buildIdentifier,
                            "sourceCommitSHA": self.buildIdentity.sourceCommitSHA
                        ])
                        await self.refreshLedgerSnapshot()
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical acceptance sealing encountered a monotonic-clock regression.",
                            kind: "accepted_prefix_seal_clock_regressed"
                        )
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                        await self.mirrorAlreadyTerminalObservationContinuity(
                            token: token,
                            message: "Canonical acceptance crossed the package-owned continuous-observation horizon. The package already retired this generation; no disconnect is claimed.",
                            kind: "accepted_prefix_seal_continuity_invalidated"
                        )
                    } catch {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical readiness sealing violated the current internal session lifecycle: \(error.localizedDescription)",
                            kind: "accepted_prefix_seal_lifecycle_rejected"
                        )
                    }
                    return

                case .blocked:
                    break
                }

                if self.applicationUpdateAdmissionsInFlight == 0,
                   (self.canonicalObservedAgeSeconds ?? 0) > 60,
                   self.applicationUpdateCount == 0 {
                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "The application-observation deadline encountered a monotonic-clock regression.",
                            kind: "application_timeout_clock_regressed"
                        )
                        return
                    } catch {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "The application-observation terminal could not complete safely: \(error.localizedDescription)",
                            kind: "application_timeout_lifecycle_rejected"
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
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                message = "Observed local-BLE loss could not retire the exact ledger generation. Relaunch Capture before another attempt."
                log("transport_loss_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
        } catch {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                message = "Observed local-BLE loss encountered an unrecoverable terminal lifecycle mismatch. Relaunch Capture before another attempt."
                log("transport_loss_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
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
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                self.message = "Source-authority retirement encountered invalid chronology and could not retire the exact generation. Relaunch Capture."
                log("source_authority_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
        } catch {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                self.message = "Source-authority retirement could not close the exact ledger generation. Relaunch Capture."
                log("source_authority_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
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

    /// Mirrors a terminal continuity verdict already committed by the package mutation that threw
    /// `observationContinuityInvalidated`. That package path clears its current token before
    /// throwing, so calling another ledger terminal here would manufacture a false retirement
    /// failure. This helper changes app-local ownership/presentation only; it does not claim BLE
    /// disconnect, source loss, a new clock receipt, or a second terminal event.
    private func mirrorAlreadyTerminalObservationContinuity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        watchdog?.cancel()
        watchdog = nil
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
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                self.message = "Observation-continuity retirement encountered invalid chronology and could not retire the exact generation. Relaunch Capture."
                log("observation_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
        } catch {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                self.message = "Observation-continuity retirement could not close the exact ledger generation. Relaunch Capture."
                log("observation_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
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

    private func invalidateInternalLifecycle(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markInternalLifecycleFailure(for: token)
        } catch {
            // Do not discard app ownership when package retirement itself is unproven. Keeping the
            // token blocks generic reset/retry and makes relaunch the only safe recovery.
            phase = .failed
            self.message = "Internal session authority could not be terminally retired. Relaunch Capture before another attempt."
            log("internal_lifecycle_terminal_retirement_failed", [
                "generation": String(token.diagnosticGeneration),
                "requestedKind": kind,
                "error": error.localizedDescription
            ])
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

    private func invalidatePreparedMutableExport() {
        guard phase != .accepted else { return }
        exportData = nil
    }

    private func refreshLedgerSnapshot() async {
        ledgerSnapshot = await sessionLedger.currentPreflightSnapshot()
        invalidatePreparedMutableExport()
    }

    private func makeExport(exportedAt: Date, phase: Phase, events: [Event]) -> Export {
        Export(
            schemaVersion: 9,
            purpose: "Sanitized Tuya authenticated read-only stationary preflight",
            exportedAt: exportedAt,
            buildIdentifier: buildIdentity.buildIdentifier,
            sourceCommitSHA: buildIdentity.sourceCommitSHA,
            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,
            tuyaDeviceID: deviceID,
            tuyaUUID: tuyaUUID,
            productID: productID,
            selectedPeripheralID: selectedID?.uuidString,
            targetCorrelationMethod: targetCorrelationMethod,
            targetCorrelationWindowCount: targetCorrelationWindowCount,
            targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed,
            targetCorrelationProvenance: correlationProvenance,
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
    }

    func prepareExport() {
        let envelope: Export
        if phase == .accepted {
            guard let sealedAcceptedExport else {
                exportData = nil
                message = "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Restart from OFF1 rather than rebuilding accepted evidence from mutable post-seal state."
                return
            }
            envelope = sealedAcceptedExport
        } else {
            envelope = makeExport(
                exportedAt: Date(),
                phase: phase,
                events: events
            )
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            exportData = try encoder.encode(envelope)
            exportName = "Nembra-Secure-Link-\(deviceID.prefix(8))-Diagnostics.json"
            message = "Sanitized diagnostics ready with exact compiled source + reviewed Tuya dependency-lock provenance. No account UID, AppKey/AppSecret, password, account token, local_key, session key, raw FD50 claim, DP query, or DP command is exported."
        } catch {
            exportData = nil
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

    private func resetDiscoverySessionOnly() {
        acceptanceCutIsClosed = false
        sealedAcceptedEventPrefix = nil
        sealedAcceptedExport = nil
        correlationSession?.abandonCurrentWindow()
        correlationSession = nil
        correlationProvenance = nil
        targetCorrelationMethod = nil
        targetCorrelationWindowCount = nil
        targetCorrelationOperatorConfirmed = false
        watchdog?.cancel()
        watchdog = nil
        driver = nil
        localBLESettlementToken = nil
        byID.removeAll()
        candidates.removeAll()
        selectedID = nil
        pendingCorrelatedTargetID = nil
        sdkLocalBLEOnline = false
        exportData = nil
        // Active authenticated generations must be terminally retired by their
        // owning outcome path before a new discovery attempt. Generic reset never
        // manufactures a transport-disconnect terminal.
        assert(currentConnectionToken == nil)
    }

    private func failLocally(_ text: String, _ kind: String) {
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }
        pendingCorrelatedTargetID = nil
        watchdog?.cancel()
        watchdog = nil
        phase = .failed
        message = text
        log(kind, ["message": text])
    }

    private func log(_ kind: String, _ details: [String: String] = [:]) {
        invalidatePreparedMutableExport()
        events.append(Event(at: Date(), kind: kind, details: details))
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
    @State private var showEngineeringDetails = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let stageLabels = ["Target", "Secure link", "Observe", "Seal"]

    init(device: TuyaAccountBridge.LinkedDevice) {
        _test = StateObject(wrappedValue: SecureLinkController(device: device))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.white.opacity(0.09), Color.clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 520
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        hero
                        stageRail
                        primarySurface
                        engineeringDisclosure
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 44)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .onChange(of: test.correlationProgress?.isSeriesInvalidated == true) { _, invalidated in
                if invalidated {
                    test.consumeCorrelationAsyncInvalidation()
                }
            }
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
            if test.phase == .accepted && test.exportData == nil { test.prepareExport() }
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
            if loggedIn { test.verifySDKMembership() }
            else { test.invalidateSDKMembership() }
        }
        .onChange(of: test.phase == .accepted) { _, accepted in
            if accepted && test.exportData == nil { test.prepareExport() }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("NEMBRA CAPTURE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Label(
                    test.fieldBuildIsAuthoritative ? "Field build" : "Build blocked",
                    systemImage: test.fieldBuildIsAuthoritative ? "checkmark.shield.fill" : "exclamationmark.shield"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(test.fieldBuildIsAuthoritative ? Color.green : Color.orange)
            }

            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(heroAccent.opacity(0.14))
                        .frame(width: 64, height: 64)
                    Circle()
                        .stroke(heroAccent.opacity(0.32), lineWidth: 1)
                        .frame(width: 64, height: 64)
                    Image(systemName: heroSymbol)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(heroAccent)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(phaseKicker)
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(heroAccent)
                    Text(phaseTitle)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(phaseSubtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stageRail: some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 10) {
                Text("Step \(currentStageIndex + 1) of 4")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(stageLabels[currentStageIndex])
                    .font(.headline)
                Spacer()
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 8) {
                ForEach(Array(stageLabels.enumerated()), id: \.offset) { index, label in
                    VStack(spacing: 7) {
                        ZStack {
                            Circle()
                                .fill(index <= currentStageIndex ? heroAccent : Color.white.opacity(0.08))
                                .frame(width: 26, height: 26)
                            if index < currentStageIndex || test.phase == .accepted {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(index <= currentStageIndex ? Color.black : Color.secondary)
                            } else {
                                Text("\(index + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(index == currentStageIndex ? Color.black : Color.secondary)
                            }
                        }
                        Text(label)
                            .font(.caption2.weight(index == currentStageIndex ? .bold : .regular))
                            .foregroundStyle(index <= currentStageIndex ? Color.primary : Color.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Step \(index + 1), \(label)\(index == currentStageIndex ? ", current" : index < currentStageIndex ? ", complete" : ", upcoming")")
                }
            }
        }
    }

    @ViewBuilder
    private var primarySurface: some View {
        switch test.phase {
        case .accepted:
            completionPanel
        case .failed:
            failurePanel
        case .baseline, .scanning, .powerOn, .correlated:
            correlationPanel
        case .selected, .authenticating, .observing:
            secureObservationPanel
        default:
            if test.privateConfig && !sdkAccount.loggedIn {
                sdkAuthorizationPanel
            } else {
                preflightPanel
            }
        }
    }

    private var preflightPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(authorityReady ? "READY" : "PREFLIGHT")
                        .font(.caption2.bold())
                        .tracking(1.2)
                        .foregroundStyle(authorityReady ? Color.green : Color.orange)
                    Text(authorityReady ? "Ready to find this scooter" : "Prove the field setup")
                        .font(.title2.bold())
                    Text(authorityReady
                         ? "The next step is passive Bluetooth correlation. Keep the scooter stationary and begin with it powered off."
                         : "Capture stays locked until the exact field build, Tuya SDK session, and this scooter's current account membership are all proven.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    requirementRow("Exact field build", ready: test.fieldBuildIsAuthoritative)
                    requirementRow("Official Tuya SDK", ready: test.privateConfig)
                    requirementRow("Tuya account", ready: test.sdkAccountLoggedIn)
                    requirementRow("This scooter in account", ready: test.sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized)
                }

                if test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized) {
                    Button(test.membershipBusy ? "Checking scooter…" : "Verify this scooter") {
                        test.verifySDKMembership()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(test.membershipBusy)
                }

                if authorityReady {
                    Button {
                        test.startBaseline()
                    } label: {
                        Label("Start with scooter OFF", systemImage: "power")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Starts the first passive Bluetooth correlation window.")
                }
            }
        }
    }

    private var correlationPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FIND SCOOTER")
                            .font(.caption2.bold())
                            .tracking(1.2)
                            .foregroundStyle(.cyan)
                        Text(test.phase == .correlated ? "Scooter signal found" : test.correlationWindowLabel)
                            .font(.title2.bold())
                    }
                    Spacer()
                    Text("\(min(test.correlationCompletedWindowCount + 1, 4))/4")
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                }

                if test.phase == .correlated {
                    Text("One Bluetooth target repeated through the full OFF → ON → OFF → ON pattern. Confirm it for this attempt before Tuya takes over the secure link.")
                        .foregroundStyle(.secondary)
                    Button {
                        test.confirmCorrelatedTarget()
                    } label: {
                        Label("Confirm this scooter signal", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
                } else if test.phase == .powerOn {
                    Text(test.correlationWindowInstruction)
                        .foregroundStyle(.secondary)
                    Button {
                        test.startNextCorrelationWindow()
                    } label: {
                        Label("Start \(test.correlationWindowLabel)", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text(test.correlationWindowInstruction)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Label(
                            test.correlationWindowIsScanning ? "Listening" : "Starting Bluetooth…",
                            systemImage: test.correlationWindowIsScanning ? "wave.3.right.circle.fill" : "hourglass"
                        )
                        .foregroundStyle(test.correlationWindowIsScanning ? Color.green : Color.secondary)
                        Spacer()
                        Text("\(test.correlationObservedCandidateCount) signal\(test.correlationObservedCandidateCount == 1 ? "" : "s")")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        test.finishCorrelationWindow()
                    } label: {
                        Label("Finish \(test.correlationWindowLabel)", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!test.correlationWindowIsScanning)
                    .accessibilityHint("Finishes only when the package-owned scan window has earned its required evidence duration.")
                }

                Text("Historical UUID, name, RSSI, FD50, and Tuya hints never authorize the target.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var secureObservationPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 18) {
                if test.phase == .selected {
                    Text("SECURE LINK")
                        .font(.caption2.bold())
                        .tracking(1.2)
                        .foregroundStyle(.cyan)
                    Text("Target confirmed")
                        .font(.title2.bold())
                    Text("Tuya can now become the sole Bluetooth owner. Capture remains read-only and sends no scooter control or DP query.")
                        .foregroundStyle(.secondary)

                    Button {
                        test.authenticate()
                    } label: {
                        Label("Start secure read-only link", systemImage: "key.horizontal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!authorityReady || test.membershipBusy)
                } else if test.phase == .authenticating {
                    ProgressView()
                        .controlSize(.large)
                    Text("Establishing secure link")
                        .font(.title2.bold())
                    Text("Tuya owns Bluetooth now. Capture is waiting for the supported local session to become current.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("OBSERVE")
                        .font(.caption2.bold())
                        .tracking(1.2)
                        .foregroundStyle(.cyan)
                    Text("Hold steady")
                        .font(.title2.bold())
                    Text("Keep Capture in the foreground and leave the scooter untouched while the accepted observation horizon is earned.")
                        .foregroundStyle(.secondary)

                    let age = test.canonicalObservedAgeSeconds ?? 0
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Authenticated observation")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Int(min(age, 45))) / 45 s")
                                .font(.subheadline.monospacedDigit().bold())
                        }
                        ProgressView(value: min(age / 45, 1))
                        requirementRow("Secure local link", ready: test.sdkLocalBLEOnline)
                        requirementRow("Scooter data received", ready: test.applicationUpdateCount > 0)
                    }
                }
            }
        }
    }

    private var failurePanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 16) {
                Label("Capture paused", systemImage: "exclamationmark.circle")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text(test.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Nothing was promoted after the blocker. Fix the condition above, then restart from a fresh OFF1 attempt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    test.startBaseline()
                } label: {
                    Label("Restart from scooter OFF", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!authorityReady || test.membershipBusy)
            }
        }
    }

    private var completionPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CAPTURE COMPLETE")
                            .font(.caption2.bold())
                            .tracking(1.3)
                            .foregroundStyle(.green)
                        Text("Ready for analysis")
                            .font(.title.bold())
                    }
                }

                Text("The accepted artifact is sealed. Later callbacks, account changes, or diagnostics cannot rewrite what this capture proved.")
                    .foregroundStyle(.secondary)

                if let data = test.exportData {
                    ShareLink(item: SecureTransfer(data: data, name: test.exportName), preview: SharePreview(test.exportName)) {
                        Label("Share Capture", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Shares the immutable accepted Capture artifact for analysis.")
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Preparing sealed capture…")
                            .foregroundStyle(.secondary)
                    }
                    .task { test.prepareExport() }
                }

                Button(showEngineeringDetails ? "Hide details" : "View details") {
                    showEngineeringDetails.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var sdkAuthorizationPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 16) {
                Text("TUYA ACCOUNT")
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(.cyan)
                Text("Use the account that owns this scooter")
                    .font(.title2.bold())
                Text("Nembra uses Tuya's official verification-code login. Your password is never requested or stored.")
                    .foregroundStyle(.secondary)
                Text(sdkAccount.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Login method", selection: $sdkAccount.method) {
                    ForEach(OfficialTuyaAccountAuthorizer.LoginMethod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("+")
                        .foregroundStyle(.secondary)
                    TextField("Country code", text: $sdkAccount.countryCode)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .inputSurface()

                TextField(sdkAccount.method == .email ? "Tuya account email" : "Tuya account phone number", text: $sdkAccount.account)
                    .keyboardType(sdkAccount.method == .email ? .emailAddress : .phonePad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .inputSurface()

                Button(sdkAccount.busy ? "Contacting Tuya…" : "Send verification code") {
                    sdkAccount.sendCode()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(sdkAccount.busy)

                if sdkAccount.codeSent {
                    SecureField("Verification code", text: $sdkAccount.verificationCode)
                        .keyboardType(.numberPad)
                        .privacySensitive()
                        .inputSurface()
                    Button("Continue") { sdkAccount.login() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(sdkAccount.busy || sdkAccount.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var engineeringDisclosure: some View {
        DisclosureGroup(isExpanded: $showEngineeringDetails) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Build", value: test.fieldBuildIdentifier)
                LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)
                LabeledContent("SDK account", value: test.sdkAccountLoggedIn ? "Logged in" : "Not logged in")
                LabeledContent("Exact scooter membership", value: test.sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized ? "Verified" : "Not verified")
                LabeledContent("Connection generation", value: String(test.ledgerSnapshot.connectionGeneration))
                LabeledContent("Tuya local BLE", value: test.sdkLocalBLEOnline ? "Online" : "Not proven")
                LabeledContent("Accepted application updates", value: String(test.applicationUpdateCount))
                Text(test.preflightVerdictText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(test.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !test.candidates.isEmpty {
                    Divider().overlay(Color.white.opacity(0.12))
                    Text("Bluetooth evidence")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(test.candidates.prefix(8)) { candidate in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.title).font(.caption.bold())
                            Text(candidate.id.uuidString)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text(candidate.evidence.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Application values are sanitized SDK-level projections, not raw FD50 bytes. No DP query or scooter command is authorized by this surface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        } label: {
            Label("Engineering details", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.weight(.semibold))
        }
        .tint(.secondary)
        .padding(.horizontal, 2)
    }

    private func requirementRow(_ title: String, ready: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text(ready ? "Ready" : "Required")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ready ? Color.green : Color.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(ready ? "ready" : "required")")
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
    }

    private var authorityReady: Bool {
        test.fieldBuildIsAuthoritative
            && test.privateConfig
            && test.sdkAccountLoggedIn
            && test.sdkDeviceMembershipVerified
            && test.accountIdentityLeaseIsAuthorized
            && !test.membershipBusy
    }

    private var currentStageIndex: Int {
        switch test.phase {
        case .idle, .failed, .baseline, .scanning, .powerOn, .correlated: return 0
        case .selected, .authenticating: return 1
        case .observing: return 2
        case .accepted: return 3
        }
    }

    private var phaseKicker: String {
        switch test.phase {
        case .accepted: return "SEALED"
        case .failed: return "STOPPED SAFELY"
        case .baseline, .scanning, .powerOn, .correlated: return "TARGET CORRELATION"
        case .selected, .authenticating: return "SECURE LINK"
        case .observing: return "OBSERVATION"
        default: return "PREFLIGHT"
        }
    }

    private var phaseTitle: String {
        switch test.phase {
        case .accepted: return "Capture complete"
        case .failed: return "Capture paused"
        case .baseline, .scanning, .powerOn: return "Find this scooter"
        case .correlated: return "Scooter signal found"
        case .selected, .authenticating: return "Secure the link"
        case .observing: return "Hold steady"
        default: return authorityReady ? "Ready to find your scooter" : "Prepare Capture"
        }
    }

    private var phaseSubtitle: String {
        switch test.phase {
        case .accepted:
            return "Your read-only evidence is sealed and ready to share for analysis."
        case .failed:
            return "No evidence was promoted past the blocker. Fix the condition and restart from scooter OFF."
        case .baseline, .scanning, .powerOn, .correlated:
            return "A fresh four-window power pattern identifies the nearby Bluetooth target for this attempt only."
        case .selected, .authenticating:
            return "Tuya becomes the sole Bluetooth owner while Capture stays read-only."
        case .observing:
            return "Keep the scooter stationary and Capture in the foreground until the accepted horizon is sealed."
        default:
            return authorityReady
                ? "Everything required for a passive current-attempt target correlation is ready."
                : "Prove the exact field build and same-account Tuya authority before Bluetooth starts."
        }
    }

    private var heroSymbol: String {
        switch test.phase {
        case .accepted: return "checkmark"
        case .failed: return "exclamationmark"
        case .baseline, .scanning, .powerOn, .correlated: return "scope"
        case .selected, .authenticating: return "key.horizontal.fill"
        case .observing: return "waveform.path.ecg"
        default: return "shield.lefthalf.filled"
        }
    }

    private var heroAccent: Color {
        switch test.phase {
        case .accepted: return .green
        case .failed: return .orange
        default: return .cyan
        }
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
    func inputSurface() -> some View {
        padding(12)
            .frame(minHeight: 50)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
    }
}
