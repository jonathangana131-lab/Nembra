import AuthenticationServices
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
    @State private var showEngineeringDetails = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let buildIdentity = NembraCaptureBuildIdentity.current

    private var fieldBuildIsAuthoritative: Bool {
        buildIdentity.isAuthoritativeFieldBuild
    }

    private var isAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                LinearGradient(
                    colors: [Color.cyan.opacity(0.10), Color.clear, Color.black.opacity(0.35)],
                    startPoint: .topTrailing,
                    endPoint: .center
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: isAccessibilityLayout ? 16 : 22) {
                        rootHero
                        buildAuthorityStatus
                        accountSetupPanel

                        if tuya.isLinked {
                            scooterChooserPanel
                        }

                        engineeringDisclosure
                    }
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 20)
                    .padding(.top, isAccessibilityLayout ? 12 : 22)
                    .padding(.bottom, 44)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .tint(.cyan)
            .navigationTitle("Nembra Capture")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("capture.p0-root")
    }

    @ViewBuilder
    private var rootHero: some View {
        if !isAccessibilityLayout {
            VStack(alignment: .leading, spacing: 8) {
                Text("Prepare the scooter link")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Link the Tuya Smart account that owns this scooter. Bluetooth and physical evidence stay locked until the reviewed field build and fresh scooter authority are verified.")
                    .font(.body)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(verbatim: "Link the Tuya Smart account that owns this scooter. Bluetooth and physical evidence stay locked until the reviewed field build and fresh scooter authority are verified."))
            }
        }
    }

    private var buildAuthorityStatus: some View {
        HStack(alignment: .center, spacing: isAccessibilityLayout ? 8 : 12) {
            Image(systemName: fieldBuildIsAuthoritative ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(isAccessibilityLayout ? .body : .title3)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(fieldBuildIsAuthoritative ? Color.green : Color.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(
                    fieldBuildIsAuthoritative
                        ? (isAccessibilityLayout ? "Build ready" : "Build provenance ready")
                        : (isAccessibilityLayout ? "Capture locked" : "Physical capture locked")
                )
                .font(isAccessibilityLayout ? .body.weight(.semibold) : .headline)
                .foregroundStyle(fieldBuildIsAuthoritative ? Color.green : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

                if !isAccessibilityLayout {
                    Text(
                        fieldBuildIsAuthoritative
                            ? "The reviewed build is ready. Account and scooter authority must still be verified before Bluetooth starts."
                            : "Account setup is available. Bluetooth scanning, connection, and physical evidence stay locked until the reviewed field build is installed."
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, isAccessibilityLayout ? 2 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")
        .accessibilityValue(
            fieldBuildIsAuthoritative
                ? "Build provenance is ready. Account and scooter authority are still required before Bluetooth starts."
                : "This public build can prepare account metadata only. Bluetooth and physical evidence collection are locked."
        )
    }

    private var accountSetupPanel: some View {
        rootSection {
            VStack(alignment: .leading, spacing: isAccessibilityLayout ? 12 : 14) {
                HStack(alignment: .top, spacing: 12) {
                    if !isAccessibilityLayout {
                        Image(systemName: tuya.isLinked ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(tuya.isLinked ? Color.green : Color.cyan)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.06), in: Circle())
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            tuya.isLinked
                                ? "Account metadata ready"
                                : (isAccessibilityLayout ? "Account setup" : "Prepare account metadata")
                        )
                        .font(isAccessibilityLayout ? .headline : .title3.bold())
                        .accessibilityAddTraits(.isHeader)
                        .foregroundStyle(tuya.isLinked ? Color.green : Color.primary)

                        if !isAccessibilityLayout || tuya.isLinked {
                            Text(
                                tuya.isLinked
                                    ? "Account context is ready for scooter selection."
                                    : "Use the Tuya Smart user code for the account that owns this scooter."
                            )
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.74))
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if tuya.isLinked {
                    statusText
                } else {
                    if !isAccessibilityLayout {
                        Text("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings.")
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                        statusText
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(isAccessibilityLayout ? "Tuya user code" : "Tuya Smart user code")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityHidden(true)
                        TextField(isAccessibilityLayout ? "Tuya user code" : "Paste user code", text: $tuya.userCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(Color.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            }
                            .accessibilityLabel("Tuya Smart user code")
                            .accessibilityHint("Used only to create the Tuya account approval QR for metadata setup.")
                    }

                    Button {
                        tuya.requestApproval()
                    } label: {
                        Label(isAccessibilityLayout ? "Create QR" : "Create approval QR", systemImage: "qrcode")
                            .font(isAccessibilityLayout ? .body.bold() : .headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .foregroundStyle(.black)
                    .accessibilityIdentifier("nembra.capture.root.account-link-action")
                    .accessibilityLabel("Create approval QR")
                    .accessibilityHint("Creates the account-metadata approval QR. It does not start Bluetooth or physical Capture.")

                    if isAccessibilityLayout, tuya.phase != .needsUserCode {
                        statusText
                    }
                }

                if let data = tuya.qrPNGData,
                   let image = UIImage(data: data),
                   !tuya.isLinked {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 230)
                            .padding(10)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityLabel("Tuya account approval QR code")

                        Button("I approved it · check now") { tuya.checkApprovalNow() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: isAccessibilityLayout ? .infinity : nil, alignment: .leading)
                    }
                }

                if tuya.phase == .failed {
                    Button("Reset account link") { tuya.resetLink() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
        }
    }

    private var statusText: some View {
        Text(tuya.statusMessage)
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var scooterChooserPanel: some View {
        rootSection {
            VStack(alignment: .leading, spacing: 14) {
                if isAccessibilityLayout {
                    VStack(alignment: .leading, spacing: 10) {
                        scooterSectionHeading
                        if tuya.devices.isEmpty {
                            Button("Refresh scooters") { tuya.refreshDevices() }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        scooterSectionHeading
                        Spacer(minLength: 8)
                        if tuya.devices.isEmpty {
                            Button("Refresh") { tuya.refreshDevices() }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                ForEach(tuya.devices) { device in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name.isEmpty ? "Unnamed Tuya device" : device.name)
                                    .font(.headline)
                                let detail = [device.productName, device.category].filter { !$0.isEmpty }.joined(separator: " · ")
                                if !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(Color.white.opacity(0.70))
                                }
                            }
                            Spacer()
                            if tuya.selectedDeviceID == device.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Selected")
                            }
                        }

                        if isAccessibilityLayout {
                            VStack(alignment: .leading, spacing: 10) {
                                scooterSelectionButton(for: device)
                                continueButton(for: device)
                            }
                        } else {
                            HStack(spacing: 10) {
                                scooterSelectionButton(for: device)
                                continueButton(for: device)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private var scooterSectionHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Choose this scooter")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Nembra verifies the selected device again inside the official SDK before Bluetooth discovery.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func scooterSelectionButton(for device: TuyaAccountBridge.LinkedDevice) -> some View {
        Button(tuya.selectedDeviceID == device.id ? "Refresh metadata" : "Use this scooter") {
            tuya.selectDevice(device)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @ViewBuilder
    private func continueButton(for device: TuyaAccountBridge.LinkedDevice) -> some View {
        if tuya.selectedDeviceID == device.id,
           tuya.phase == .ready,
           !device.productID.isEmpty,
           !device.uuid.isEmpty {
            NavigationLink(fieldBuildIsAuthoritative ? "Continue to preflight" : "View locked preflight") {
                SecureLinkView(device: device)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var engineeringDisclosure: some View {
        DisclosureGroup(isExpanded: $showEngineeringDetails) {
            VStack(alignment: .leading, spacing: 8) {
                Text(fieldBuildIsAuthoritative ? "Build provenance: ready" : "Build provenance: locked")
                Text("Account approval and device metadata only establish setup context. Capture independently verifies the current official SDK session and exact scooter membership before discovery.")
                Text("No scooter commands are sent by this setup flow.")
            }
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.70))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        } label: {
            Label(isAccessibilityLayout ? "Details" : "Engineering details", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel("Engineering details")
        }
        .tint(Color.white.opacity(0.76))
        .padding(.top, isAccessibilityLayout ? 2 : 4)
    }

    @ViewBuilder
    private func rootSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, isAccessibilityLayout ? 12 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 1)
            }
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

    enum LocalBLEEvidenceState: String, Codable {
        /// The controller's latest retained direct official-SDK local-BLE sample was online.
        /// Diagnostic exports do not promote this into an export-time currentness claim.
        case observedOnlineAtLatestDirectSample = "observed-online-at-latest-direct-sample"
        /// No current online proof is retained. This must never be interpreted as an observed
        /// offline/disconnect fact; actual transport loss remains separate timestamped evidence.
        case notProven = "not-proven"
    }

    struct Export: Codable {
        let schemaVersion: Int
        let purpose: String
        let exportedAt: Date
        let buildIdentifier: String
        let sourceCommitSHA: String
        let tuyaDependencyLockSHA256: String
        let procedureIdentifier: String
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
        let sdkLocalBLEEvidenceState: LocalBLEEvidenceState
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
    @Published private(set) var diagnosticExportError: String?
    @Published private(set) var exportName = "Nembra-Secure-Link-Diagnostics.json"

    let deviceID: String
    let deviceName: String
    let productID: String
    let tuyaUUID: String

    private let buildIdentity = NembraCaptureBuildIdentity.current
    private var byID: [UUID: Candidate] = [:]
    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?
    private var processCorrelationLease: UUID?
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
    private var acceptsViewScopedMembershipRequests = false
    private var foregroundIntegrityLossHandled = false
    private var officialConnectionRequestID = UUID()

    init(device: TuyaAccountBridge.LinkedDevice) {
        deviceID = device.id
        deviceName = device.name
        productID = device.productID
        tuyaUUID = device.uuid
        super.init()
        log("controller_created")
    }

    deinit { watchdog?.cancel() }

    func activateMembershipRequestsForView() {
        // A fast inactive -> active transition must not reset the duplicate-retirement fence
        // while an authenticated generation is terminalizing. Once the official Tuya driver has
        // been handed out, package correlation is permanently retired for this process and the
        // foreground-loss recovery contract is relaunch rather than silently reopening authority.
        guard currentConnectionToken == nil,
              OfficialTuyaFactory.packageCorrelationMayStart else { return }
        foregroundIntegrityLossHandled = false
        acceptsViewScopedMembershipRequests = true
    }

    func abandonCorrelationForViewExit() {
        // Close the screen-lifetime admission boundary before revoking every already-issued grant.
        // A later SwiftUI/account callback must not mint a replacement membership probe off-screen.
        acceptsViewScopedMembershipRequests = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Exact scooter membership must be verified again after Capture leaves Secure Link authority."
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
        watchdog?.cancel()
        watchdog = nil

        // Foreground loss already owns the terminal retirement for this view lifetime.
        // Avoid racing a second terminal task when backgrounding is followed by onDisappear.
        if foregroundIntegrityLossHandled { return }

        if let token = currentConnectionToken {
            phase = .failed
            message = "Authenticated observation stopped because Capture left Secure Link. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
            log("authenticated_session_abandoned_on_view_exit", ["generation": String(token.diagnosticGeneration)])
            Task { @MainActor [self] in
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "Authenticated observation stopped because Capture left Secure Link. Relaunch before another authenticated attempt; no BLE disconnect is claimed.",
                    kind: "authenticated_session_abandoned_on_view_exit"
                )
            }
            return
        }

        if phase == .authenticating {
            // Driver handoff happened, but no package generation exists yet. The request-id fence
            // below forces the pending ledger task to retire its generation before SDK connect.
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            phase = .failed
            message = "Authentication start stopped because Capture left Secure Link. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
            log("authentication_start_abandoned_on_view_exit")
            return
        }

        if phase == .correlated || phase == .selected {
            pendingCorrelatedTargetID = nil
            selectedID = nil
            targetCorrelationOperatorConfirmed = false
            phase = .failed
            message = "Capture left Secure Link after Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; the prior target cannot cross a view lifetime. Completed correlation evidence remains available for diagnostics."
            log("target_correlation_abandoned_on_view_exit")
            return
        }
        guard processCorrelationLease != nil || correlationSession != nil else { return }
        // Existing helper stops package transport before releasing this controller's lease.
        abandonPackageCorrelation()
        phase = .failed
        message = "Bluetooth correlation was interrupted when Capture left Secure Link. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series."
        log("target_correlation_abandoned_on_view_exit")
    }

    func appDidLoseForeground() {
        // A sealed accepted artifact is immutable and already closed to new evidence. Backgrounding
        // after acceptance must not downgrade or rebuild that frozen result.
        guard phase != .accepted else { return }
        guard !foregroundIntegrityLossHandled else { return }
        foregroundIntegrityLossHandled = true

        // Capture evidence is foreground-only. Close view-scoped account authority and revoke
        // already-issued asynchronous grants before inspecting any radio/session state.
        acceptsViewScopedMembershipRequests = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Exact scooter membership must be verified again after Capture leaves Secure Link authority."
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
        watchdog?.cancel()
        watchdog = nil

        if processCorrelationLease != nil || correlationSession != nil {
            // The full discovery reset preserves scanner-first lease retirement and also erases
            // every actionable target-selection bit earned by the interrupted correlation.
            resetDiscoverySessionOnly()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        if phase == .correlated || phase == .selected {
            // Final-window sealing already retired the scanner/lease. Revoke target reuse authority
            // without erasing the completed OFF1→ON1→OFF2→ON2 evidence needed for diagnostics.
            pendingCorrelatedTargetID = nil
            selectedID = nil
            targetCorrelationOperatorConfirmed = false
            phase = .failed
            message = "Capture left the foreground after Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; the prior correlated/selected target cannot cross a foreground-integrity break. Completed correlation evidence remains available for diagnostics."
            log("foreground_integrity_lost_after_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
            if phase == .authenticating {
                // OfficialTuyaFactory.make() permanently retires package correlation for this
                // process, even if no package generation existed before foreground loss.
                localBLESettlementToken = nil
                sdkLocalBLEOnline = false
                driver = nil
                phase = .failed
                message = "Capture left the foreground during authentication. Relaunch Capture before a new stationary read-only attempt; no BLE disconnect is claimed."
                log("foreground_integrity_lost_before_observation")
            }
            return
        }

        let wasObserving = phase == .observing
        phase = .failed
        message = wasObserving
            ? "Capture left the foreground during authenticated observation. Relaunch Capture before a new stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch Capture before a new stationary read-only attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        // This finite terminal task must outlive SwiftUI StateObject teardown. Exact-token fencing
        // prevents a stale retirement from touching a later generation.
        Task { @MainActor [self] in
            guard self.currentConnectionToken == token else { return }
            if wasObserving {
                await self.invalidateObservationContinuity(
                    token: token,
                    message: "App foreground integrity was lost during authenticated observation. Relaunch Capture before a new stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_during_observation"
                )
            } else {
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "App foreground integrity was lost before authenticated observation. Relaunch Capture before a new stationary read-only attempt; no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_before_observation"
                )
            }
        }
    }

    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }
    var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }
    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }
    var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }
    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }
    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }
    var selected: Candidate? { selectedID.flatMap { byID[$0] } }
    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }
    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }
    var correlationWindowIsScanning: Bool { correlationProgress?.isScanning == true }
    var correlationObservedCandidateCount: Int { correlationProgress?.currentObservedCandidateCount ?? 0 }
    var correlationCompletedWindowCount: Int { correlationProgress?.completedWindowCount ?? 0 }
    var failedAttemptCanRestartFromOFF1: Bool {
        phase == .failed
            && currentConnectionToken == nil
            && localBLESettlementToken == nil
            && driver == nil
            && OfficialTuyaFactory.packageCorrelationMayStart
    }
    var canRestartFromFreshOFF1: Bool { failedAttemptCanRestartFromOFF1 }

    func consumeCorrelationAsyncInvalidation() {
        guard phase == .baseline || phase == .scanning else { return }
        if OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) {
            abandonPackageCorrelation()
            failLocally(
                "Tuya regained local-BLE ownership while package correlation was active. This correlation window is invalid; power the scooter OFF, let Tuya local BLE clear, and restart from OFF1.",
                "sdk_local_ble_reacquired_during_target_correlation"
            )
            return
        }
        guard correlationProgress?.isSeriesInvalidated == true else { return }
        abandonPackageCorrelation()
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
            isLoggedIn: sdkAccountLoggedIn,
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

    var applicationEvidenceSurvivedHistoricalWindow: Bool {
        guard let authenticatedAt = ledgerSnapshot.authenticatedAtUptimeNanoseconds,
              let latestPayload = ledgerSnapshot.latestApplicationPayloadUptimeNanoseconds,
              latestPayload >= authenticatedAt else { return false }
        return latestPayload - authenticatedAt >= TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
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
        guard OfficialTuyaFactory.packageCorrelationMayStart else {
            failLocally(
                "Package Bluetooth correlation is already active elsewhere in Capture, or Tuya BLE ownership was already attempted in this app process. Finish the active attempt or relaunch with the scooter OFF before a fresh OFF1→ON1→OFF2→ON2 series.",
                "process_tuya_ble_ownership_blocks_scan"
            )
            return
        }
        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {
            failLocally(
                "Tuya still reports a current local-BLE session for this scooter. Power the scooter OFF and wait for that session to clear, or relaunch Capture. Package-owned correlation will not scan while Tuya still owns local BLE.",
                "existing_sdk_local_ble_ownership_blocks_scan"
            )
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
        guard let processLease = OfficialTuyaFactory.acquirePackageCorrelationLease() else {
            failLocally(
                "Another Capture controller already owns package Bluetooth correlation, or Tuya BLE ownership was attempted in this app process. Finish/relaunch before a fresh OFF1 series.",
                "process_package_correlation_ownership_unavailable"
            )
            return
        }
        processCorrelationLease = processLease
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
            abandonPackageCorrelation()
            failLocally("SDK account/device authority changed before the next correlation window.", "sdk_authority_changed_during_target_correlation")
            return
        }
        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {
            abandonPackageCorrelation()
            failLocally(
                "Tuya local-BLE ownership is active before this correlation window. The package scanner will not start; power the scooter OFF, let Tuya local BLE clear, and restart from OFF1.",
                "sdk_local_ble_ownership_blocks_correlation_window"
            )
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
            abandonPackageCorrelation()
            failLocally("The \(label) correlation window failed closed: \(error.localizedDescription). Restart from OFF1.", "target_correlation_window_start_failed")
        }
    }

    func finishCorrelationWindow() {
        guard phase == .baseline || phase == .scanning,
              let session = correlationSession else { return }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            abandonPackageCorrelation()
            failLocally("SDK account/device authority changed during Bluetooth correlation. Restart from OFF1 after re-verifying membership.", "sdk_authority_changed_during_target_correlation")
            return
        }

        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {
            abandonPackageCorrelation()
            failLocally(
                "Tuya local-BLE ownership appeared before this correlation window could be sealed. The window is invalid; power the scooter OFF, let Tuya local BLE clear, and restart from OFF1.",
                "sdk_local_ble_ownership_invalidates_correlation_window"
            )
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
                abandonPackageCorrelation()
                failLocally("\(sealedLabel) failed closed (\(String(describing: error))). Restart the complete OFF1→ON1→OFF2→ON2 series.", "target_correlation_window_failed")
            }
        } catch {
            abandonPackageCorrelation()
            failLocally("\(sealedLabel) failed closed: \(error.localizedDescription). Restart the complete correlation series.", "target_correlation_window_failed")
        }
    }

    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {
        // `finishCurrentWindow()` has already synchronously retired the final package scanner.
        // Release the process lease only after that radio transport is no longer live, so another
        // controller can never acquire Tuya ownership while package scanning still exists.
        correlationSession = nil
        releasePackageCorrelationLease()

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
        if phase == .correlated || phase == .selected {
            // Final-window sealing already retired package scanning. Account authority loss must
            // revoke target reuse without deleting the completed physical-correlation receipts.
            pendingCorrelatedTargetID = nil
            selectedID = nil
            targetCorrelationOperatorConfirmed = false
            phase = .failed
            message = "SDK account authority changed after Bluetooth target correlation. Restart from OFF1 after re-verifying exact scooter membership; completed correlation evidence remains available for diagnostics."
            log("sdk_membership_invalidated_after_target_correlation")
        }
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            abandonPackageCorrelation()
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
        guard acceptsViewScopedMembershipRequests else {
            completion?(false)
            return
        }
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

    func retry() {
        guard phase == .failed, canRestartFromFreshOFF1 else {
            message = "This failed attempt still retains session authority. Relaunch Capture before another OFF1 attempt."
            log("in_process_retry_rejected")
            return
        }
        startBaseline()
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

        let connectionRequestID = UUID()
        officialConnectionRequestID = connectionRequestID
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
                guard self.officialConnectionRequestID == connectionRequestID,
                      self.phase == .authenticating else {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication generation was retired because Secure Link left before SDK connection could start. No BLE disconnect is claimed.",
                        kind: "authentication_generation_abandoned_before_sdk_connect"
                    )
                    return
                }
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
                guard self.officialConnectionRequestID == connectionRequestID,
                      self.currentConnectionToken == token,
                      self.phase == .authenticating else {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication generation was retired because Secure Link left before SDK connection could start. No BLE disconnect is claimed.",
                        kind: "authentication_generation_abandoned_before_sdk_connect"
                    )
                    return
                }
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
                        self?.admitApplicationUpdateCallback(update, token: token)
                    },
                    sourceAuthorityFailure: { [weak self] in
                        guard let self,
                              self.currentConnectionToken == token else { return }

                        // SmartLifeDriver has already latched application forwarding closed.
                        // Own the app acceptance cut on this same MainActor callback turn before
                        // exact-token package retirement is scheduled. A ready watchdog continuation
                        // can therefore no longer seal while source authority is merely queued to retire.
                        self.acceptanceCutIsClosed = true
                        self.watchdog?.cancel()
                        self.watchdog = nil
                        self.phase = .failed
                        self.message = "SmartLife application callback source no longer matched the selected scooter. The exact session is being retired; relaunch Capture before another attempt."

                        Task { @MainActor [weak self] in
                            await self?.invalidateSourceAuthority(
                                token: token,
                                message: "SmartLife application callback source no longer matched the selected scooter. The generation was retired without admitting that payload or claiming Bluetooth disconnected.",
                                kind: "sdk_application_callback_source_mismatch"
                            )
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

                    // Both ledger actor hops above can interleave foreground/view/account retirement.
                    // Never repaint an already-retired generation as authenticated observation.
                    guard currentConnectionToken == token else {
                        log("stale_auth_promotion_resume_ignored", [
                            "generation": String(token.diagnosticGeneration)
                        ])
                        return
                    }
                    guard phase == .authenticating else {
                        log("auth_promotion_resume_phase_changed_ignored", [
                            "generation": String(token.diagnosticGeneration)
                        ])
                        return
                    }
                    guard sdkAccountLoggedIn,
                          sdkDeviceMembershipVerified,
                          accountIdentityLeaseIsAuthorized else {
                        await invalidateSourceAuthority(
                            token: token,
                            message: "Tuya account/device source authority changed while authentication promotion was suspended.",
                            kind: "sdk_source_authority_lost_during_auth_promotion"
                        )
                        return
                    }

                    guard let promotionDriver = self.driver else {
                        await invalidateSourceAuthority(
                            token: token,
                            message: "Official Tuya driver authority disappeared while authentication promotion was suspended.",
                            kind: "sdk_driver_authority_lost_during_auth_promotion"
                        )
                        return
                    }
                    let promotionLocalBLEOnline = promotionDriver.isLocallyConnected(uuid: tuyaUUID)
                    sdkLocalBLEOnline = promotionLocalBLEOnline
                    guard promotionLocalBLEOnline else {
                        await recordObservedTransportLoss(token: token)
                        return
                    }

                    phase = .observing
                    message = "Authenticated generation \(token.diagnosticGeneration) is live. Waiting for repeated same-generation scooter data, including data that stays live beyond the startup rejection window, plus the canonical 45-second observation horizon…"
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

    private func admitApplicationUpdateCallback(
        _ update: [String: String],
        token: TuyaReadOnlyConnectionToken
    ) {
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.invalidateSourceAuthority(
                    token: token,
                    message: "SDK account/device source authority changed before callback receipt admission.",
                    kind: "sdk_source_authority_changed_before_callback_receipt"
                )
            }
            return
        }
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            Task { @MainActor [weak self] in
                await self?.recordObservedTransportLoss(token: token)
            }
            return
        }
        guard let applicationDelivery = sessionLedger.captureApplicationDelivery(for: token) else {
            log("application_receipt_authority_unavailable", ["generation": String(token.diagnosticGeneration)])
            return
        }

        applicationUpdateAdmissionsInFlight += 1
        Task { @MainActor [self] in
            defer { applicationUpdateAdmissionsInFlight -= 1 }
            await receivedApplicationUpdate(update, delivery: applicationDelivery, token: token)
        }
    }

    private func receivedApplicationUpdate(
        _ update: [String: String],
        delivery: TuyaReadOnlyApplicationReceipt,
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

        // Snapshot the exact account identity while the admission checks above are still
        // synchronously true. The actor hops below may interleave foreground/account teardown;
        // export custody must never re-read mutable membership state after that suspension.
        guard let leasedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !leasedAccountUID.isEmpty else {
            await invalidateSourceAuthority(
                token: token,
                message: "Verified Tuya account identity disappeared before application evidence could enter export custody.",
                kind: "sdk_account_identity_missing_before_application_custody"
            )
            return
        }
        let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)

        do {
            var applicationReceiptRecorded = false
            while !applicationReceiptRecorded {
                do {
                    try await sessionLedger.recordApplicationUpdate(delivery: delivery, for: token)
                    applicationReceiptRecorded = true
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationReceiptOrderPending {
                    guard currentConnectionToken == token,
                          phase == .observing,
                          !acceptanceCutIsClosed else { return }
                    await Task.yield()
                }
            }
            await refreshLedgerSnapshot()

            // The ledger hops above may interleave account/view lifecycle changes. Revalidate
            // the exact generation and account lease immediately before immutable event custody.
            guard currentConnectionToken == token,
                  phase == .observing,
                  !acceptanceCutIsClosed,
                  sdkAccountLoggedIn,
                  sdkDeviceMembershipVerified,
                  accountIdentityLeaseIsAuthorized,
                  membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines) == leasedAccountUID else {
                if currentConnectionToken == token {
                    await invalidateSourceAuthority(
                        token: token,
                        message: "SDK account/device authority changed before application evidence could enter event custody.",
                        kind: "sdk_source_authority_changed_before_application_event_custody"
                    )
                }
                return
            }
            var eventDetails = custodySafeUpdate
            eventDetails["generation"] = String(token.diagnosticGeneration)
            log("tuya_application_update", eventDetails)
            message = "Receiving same-generation scooter application data · \(applicationUpdateCount) update(s). Canonical readiness still depends on the sealed observation horizon."
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateInternalLifecycle(
                token: token,
                message: "Scooter data timing became invalid, so this observation stopped safely. Relaunch Capture and start again from scooter OFF.",
                kind: "application_receipt_clock_regressed"
            )
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
            await mirrorAlreadyTerminalObservationContinuity(
                token: token,
                message: "Scooter data arrived after this observation window was no longer valid. This does not prove Bluetooth disconnected. Relaunch Capture and start again from scooter OFF.",
                kind: "application_observation_continuity_invalidated"
            )
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached {
            await mirrorAlreadyTerminalIncompleteObservationHorizon(
                token: token,
                message: "Scooter data did not become sufficient within 60 seconds. Keep the scooter stationary, relaunch Capture, and start again from scooter OFF.",
                kind: "application_authenticated_incomplete_readiness_horizon_reached"
            )
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch {
            await invalidateInternalLifecycle(
                token: token,
                message: "Scooter data could not be accepted into this observation. Relaunch Capture and start again from scooter OFF.",
                kind: "application_update_lifecycle_rejected"
            )
        }
    }

    private func redactedApplicationEventDetails(
        _ update: [String: String],
        accountUID: String
    ) -> [String: String] {
        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update.sorted(by: { $0.key < $1.key }) {
            let redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            let redactedValue = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )

            // Redacting malformed keys can collapse two distinct SDK entries onto one key.
            // Preserve every admitted opaque value under a deterministic redaction-safe suffix.
            // `generation` is Nembra-owned event provenance. Preserve an opaque SDK
            // field with the same spelling under an application namespace instead of
            // allowing the trusted token stamp below to destroy admitted evidence.
            let reservedCustodyKey = redactedKey == "generation"
                ? "application.generation"
                : redactedKey
            var custodyKey = reservedCustodyKey
            var collisionOrdinal = 2
            while redacted[custodyKey] != nil {
                custodyKey = "\(reservedCustodyKey)#\(collisionOrdinal)"
                collisionOrdinal += 1
            }
            redacted[custodyKey] = redactedValue
        }
        return redacted
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

                if self.applicationUpdateAdmissionsInFlight > 0 {
                    try? await Task.sleep(for: .milliseconds(25))
                    continue
                }
                guard self.applicationUpdateAdmissionsInFlight == 0 else {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Application callback admission drain became internally inconsistent.",
                        kind: "application_admission_drain_invalid"
                    )
                    return
                }

                do {
                    try await self.sessionLedger.observeCurrentConnection(for: token)
                    await self.refreshLedgerSnapshot()
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationReceiptPending {
                    try? await Task.sleep(for: .milliseconds(25))
                    continue
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Observation timing became invalid, so this capture stopped safely. Relaunch Capture and start again from scooter OFF.",
                        kind: "session_liveness_clock_regressed"
                    )
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                    await self.mirrorAlreadyTerminalObservationContinuity(
                        token: token,
                        message: "Scooter data stopped satisfying the continuous observation window. This does not prove Bluetooth disconnected. Relaunch Capture and start again from scooter OFF.",
                        kind: "session_liveness_continuity_invalidated"
                    )
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached {
                    await self.mirrorAlreadyTerminalIncompleteObservationHorizon(
                        token: token,
                        message: "Scooter data did not become sufficient within 60 seconds. Keep the scooter stationary, relaunch Capture, and start again from scooter OFF.",
                        kind: "session_authenticated_incomplete_readiness_horizon_reached"
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
                        message: "This observation could not continue safely. Relaunch Capture and start again from scooter OFF.",
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
                        // The package seal retires ledger callback authority before this MainActor
                        // continuation resumes. A late SDK terminal/view lifecycle callback may run
                        // in that suspension window, so app-side generation + phase authority must
                        // still match the exact observing generation before accepted promotion.
                        // Do not attempt a second ledger terminal here: the package seal is already
                        // immutable; this fence only prevents stale app-side state from repainting
                        // a concurrent terminal lifecycle result as accepted.
                        guard self.currentConnectionToken == token,
                              self.phase == .observing else {
                            self.currentConnectionToken = nil
                            self.localBLESettlementToken = nil
                            self.sdkLocalBLEOnline = false
                            self.driver = nil
                            self.phase = .failed
                            self.message = "Authenticated session authority changed while canonical acceptance was sealing. Relaunch Capture before a new stationary read-only attempt; the sealed package chronology is diagnostic only."
                            self.log("session_authority_changed_during_acceptance_seal", [
                                "generation": String(token.diagnosticGeneration)
                            ])
                            return
                        }
                        guard self.buildIdentity.isAuthoritativeFieldBuild,
                              self.accountIdentityLeaseIsAuthorized else {
                            self.currentConnectionToken = nil
                            self.localBLESettlementToken = nil
                            self.sdkLocalBLEOnline = false
                            self.driver = nil
                            self.phase = .failed
                            self.message = "Source authority changed while canonical acceptance was sealing. Relaunch Capture before a new stationary read-only attempt; the sealed package chronology is diagnostic only."
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
                            self.message = "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred."
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
                            self.message = "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred."
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
                        self.prepareExport()
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
        message = "Tuya's current local-BLE session ended before acceptance. Export diagnostics; relaunch Capture before any new stationary read-only attempt."
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

    /// Mirrors the bounded incomplete-readiness terminal already committed atomically by the
    /// package mutation that threw `incompleteObservationHorizonReached`. The package has already
    /// revoked callback authority, so this helper performs app-local cleanup only and never issues
    /// another ledger mutation, liveness receipt, transport-loss inference, or disconnect claim.
    private func mirrorAlreadyTerminalIncompleteObservationHorizon(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        watchdog?.cancel()
        watchdog = nil
        currentConnectionToken = nil
        localBLESettlementToken = nil
        // Clear current local-BLE proof only. In product copy/export semantics false means
        // “Not proven”; this does not create an observed transport-loss receipt.
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
            schemaVersion: 11,
            purpose: "Sanitized Tuya authenticated read-only stationary preflight",
            exportedAt: exportedAt,
            buildIdentifier: buildIdentity.buildIdentifier,
            sourceCommitSHA: buildIdentity.sourceCommitSHA,
            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,
            procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier,
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
            sdkLocalBLEEvidenceState: sdkLocalBLEOnline ? .observedOnlineAtLatestDirectSample : .notProven,
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
        diagnosticExportError = nil
        let envelope: Export
        if phase == .accepted {
            guard let sealedAcceptedExport else {
                exportData = nil
                message = "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Relaunch Capture before a new stationary read-only attempt; do not rebuild accepted evidence from mutable post-seal state."
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
            if phase == .accepted {
      exportName = "Nembra-Capture-\(deviceID.prefix(8)).json"
  } else {
      exportName = "Nembra-Secure-Link-\(deviceID.prefix(8))-Diagnostics.json"
  }
            if phase != .failed {
                message = "Sanitized diagnostics ready with exact compiled source + reviewed Tuya dependency-lock provenance. No account UID, AppKey/AppSecret, password, account token, local_key, session key, raw FD50 claim, DP query, or DP command is exported."
            }
        } catch {
            exportData = nil
            let exportError = "Diagnostic export failed: \(error.localizedDescription)"
            if phase == .failed {
                diagnosticExportError = exportError
            } else {
                message = exportError
            }
        }
    }

    private func abandonPackageCorrelation() {
        // Radio transport first, process lease second. The owner token prevents an old controller
        // from clearing a lease that belongs to a newer correlation attempt.
        correlationSession?.abandonCurrentWindow()
        correlationSession = nil
        releasePackageCorrelationLease()
    }

    private func releasePackageCorrelationLease() {
        guard let processCorrelationLease else { return }
        OfficialTuyaFactory.releasePackageCorrelationLease(processCorrelationLease)
        self.processCorrelationLease = nil
    }

    private func resetDiscoverySessionOnly() {
        acceptanceCutIsClosed = false
        sealedAcceptedEventPrefix = nil
        sealedAcceptedExport = nil
        abandonPackageCorrelation()
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
        diagnosticExportError = nil
        // Active authenticated generations must be terminally retired by their
        // owning outcome path before a new discovery attempt. Generic reset never
        // manufactures a transport-disconnect terminal.
        assert(currentConnectionToken == nil)
    }

    private func failLocally(_ text: String, _ kind: String) {
        // A process lease is acquired before the first window advances presentation `phase`.
        // Session construction/start failures must therefore release by lease ownership too.
        if processCorrelationLease != nil || phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            abandonPackageCorrelation()
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
        onApplicationUpdate: @MainActor @escaping ([String: String]) -> Void,
        sourceAuthorityFailure: @escaping @MainActor () -> Void,
        success: @escaping () -> Void,
        failure: @escaping () -> Void
    )
    func isLocallyConnected(uuid: String) -> Bool
}

@MainActor
private enum OfficialTuyaFactory {
    private static var didBootstrap = false
    private static var packageCorrelationRetiredForProcess = false
    private static var activePackageCorrelationOwner: UUID?

    static var packageCorrelationMayStart: Bool {
        !packageCorrelationRetiredForProcess && activePackageCorrelationOwner == nil
    }

    static func acquirePackageCorrelationLease() -> UUID? {
        guard !packageCorrelationRetiredForProcess, activePackageCorrelationOwner == nil else { return nil }
        let lease = UUID()
        activePackageCorrelationOwner = lease
        return lease
    }

    static func releasePackageCorrelationLease(_ lease: UUID) {
        guard activePackageCorrelationOwner == lease else { return }
        activePackageCorrelationOwner = nil
    }

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

    static func isLocallyConnected(uuid: String) -> Bool {
#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)
        guard bootstrap(), !uuid.isEmpty else { return false }
        return ThingSmartBLEManager.sharedInstance().deviceStatue(withUUID: uuid)
#else
        return false
#endif
    }

    static func make() -> OfficialTuyaDriver? {
#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)
        guard !packageCorrelationRetiredForProcess,
              activePackageCorrelationOwner == nil,
              bootstrap(),
              accountLoggedIn,
              currentAccountUID != nil else { return nil }
        // A process-global Tuya BLE manager may outlive any one controller. Once a
        // supported Tuya driver is handed out, package-owned correlation stays retired
        // until app relaunch; later failures must not recreate competing BLE ownership.
        packageCorrelationRetiredForProcess = true
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
    private var expectedDeviceID: String?
    private var onApplicationUpdate: (@MainActor ([String: String]) -> Void)?
    private var onSourceAuthorityFailure: (@MainActor () -> Void)?

    func connect(
        deviceID: String,
        uuid: String,
        productID: String,
        onApplicationUpdate: @MainActor @escaping ([String: String]) -> Void,
        sourceAuthorityFailure: @escaping @MainActor () -> Void,
        success: @escaping () -> Void,
        failure: @escaping () -> Void
    ) {
        guard OfficialTuyaFactory.bootstrap() else {
            failure()
            return
        }
        expectedDeviceID = deviceID
        self.onApplicationUpdate = onApplicationUpdate
        onSourceAuthorityFailure = sourceAuthorityFailure
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
        guard let callbackDeviceID = device?.deviceModel.devId,
              callbackDeviceID == expectedDeviceID else {
            onApplicationUpdate = nil
            self.device?.delegate = nil
            onSourceAuthorityFailure?()
            onSourceAuthorityFailure = nil
            expectedDeviceID = nil
            return
        }
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in Self.sortedApplicationEntries(dps) {
            let keyString = String(describing: key)
            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            let baseCustodyKey = Self.redactKnownSecretValues(in: keyString)
            var custodyKey = baseCustodyKey
            var collisionIndex = 2
            while sanitized[custodyKey] != nil {
                custodyKey = "\(baseCustodyKey)#\(collisionIndex)"
                collisionIndex += 1
            }
            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                sanitized[custodyKey] = "<redacted>"
            } else {
                sanitized[custodyKey] = Self.redactedApplicationDescription(value)
            }
        }
        onApplicationUpdate?(sanitized)
    }

    // Assign collision suffixes only after traversing the original SDK keys in a
    // deterministic order. Otherwise Dictionary hash order can decide which admitted
    // evidence value receives the base redacted key versus #2/#3. Tuya application
    // dictionaries use scalar AnyHashable keys; spelling, concrete scalar type, then
    // scalar reflection provide a stable pre-redaction identity for that bounded input.
    private static func sortedApplicationEntries(
        _ dictionary: [AnyHashable: Any]
    ) -> [(key: AnyHashable, value: Any)] {
        dictionary.sorted { left, right in
            let leftDescription = String(describing: left.key)
            let rightDescription = String(describing: right.key)
            if leftDescription != rightDescription {
                return leftDescription < rightDescription
            }

            let leftType = String(reflecting: type(of: left.key.base))
            let rightType = String(reflecting: type(of: right.key.base))
            if leftType != rightType {
                return leftType < rightType
            }

            return String(reflecting: left.key.base) < String(reflecting: right.key.base)
        }
    }

    private static let secretKeyFragments = [
        "localkey",
        "sessionkey",
        "appkey",
        "appsecret",
        "password",
        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "authkey",
        "seckey",
    ]

    private static var exactSecretValues: [String] {
#if canImport(NembraTuyaPrivateConfig)
        Set([NembraTuyaPrivateIdentity.appKey, NembraTuyaPrivateIdentity.appSecret])
            .filter { !$0.isEmpty }
            .sorted { left, right in
                if left.count != right.count { return left.count > right.count }
                return left < right
            }
#else
        []
#endif
    }

    private static func redactKnownSecretValues(in text: String) -> String {
        var redacted = text
        for secret in exactSecretValues {
            redacted = redacted.replacingOccurrences(of: secret, with: "<redacted>")
        }
        return redacted
    }

    private static func redactedApplicationDescription(_ object: Any) -> String {
        redactKnownSecretValues(in: String(describing: redactApplicationSecrets(object)))
    }

    private static func redactApplicationSecrets(_ object: Any) -> Any {
        if let dictionary = object as? [AnyHashable: Any] {
            var sanitized: [String: Any] = [:]
            for (key, value) in sortedApplicationEntries(dictionary) {
                let keyString = String(describing: key)
                let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
                let baseCustodyKey = redactKnownSecretValues(in: keyString)
                var custodyKey = baseCustodyKey
                var collisionIndex = 2
                while sanitized[custodyKey] != nil {
                    custodyKey = "\(baseCustodyKey)#\(collisionIndex)"
                    collisionIndex += 1
                }
                if secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                    sanitized[custodyKey] = "<redacted>"
                } else {
                    sanitized[custodyKey] = redactApplicationSecrets(value)
                }
            }
            return sanitized
        }
        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        let description = String(describing: object)
        let redactedDescription = redactKnownSecretValues(in: description)
        return redactedDescription == description ? object : redactedDescription
    }
}
#endif

private enum AppleAccountAuthorizationError: LocalizedError {
    case unexpectedCredential

    var errorDescription: String? {
        "Apple authorization returned an unexpected credential type."
    }
}

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
            : "SDK initialized. Use Sign in with Apple or a Tuya verification code for the account that owns this scooter; account login alone does not count as exact scooter authority."
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
                        self?.status = "Tuya could not send the verification code: \(Self.redactedError(error, submittedIdentity: identity, submittedVerificationCode: ""))"
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
                        self?.status = "Tuya could not send the verification code: \(Self.redactedError(error, submittedIdentity: identity, submittedVerificationCode: ""))"
                    }
                }
            )
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    func loginWithApple(credential: ASAuthorizationAppleIDCredential) {
        guard OfficialTuyaFactory.bootstrap() else {
            status = "Tuya SDK initialization failed closed."
            return
        }
        guard !loggedIn else { return }
        let country = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !country.isEmpty else {
            status = "Enter the country code before using Sign in with Apple."
            return
        }
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              !identityToken.isEmpty else {
            status = "Apple did not provide an identity token, so Tuya login remains locked."
            return
        }
#if canImport(ThingSmartHomeKit)
        guard let user = ThingSmartUser.sharedInstance() else {
            status = "Official Tuya SDK account service is unavailable. Exact scooter membership remains locked."
            return
        }
        let appleUserIdentifier = credential.user
        let appleEmail = credential.email
        let appleNickname = credential.fullName?.nickname
        var extraInfo: [String: Any] = ["userIdentifier": appleUserIdentifier]
        if let appleEmail, !appleEmail.isEmpty { extraInfo["email"] = appleEmail }
        if let appleNickname, !appleNickname.isEmpty {
            extraInfo["nickname"] = appleNickname
            extraInfo["snsNickname"] = appleNickname
        }
        busy = true
        codeSent = false
        verificationCode = ""
        status = "Completing Sign in with Apple through the official Tuya SDK…"
        user.loginByAuth2(
            withType: "ap",
            countryCode: country,
            accessToken: identityToken,
            extraInfo: extraInfo,
            success: { [weak self] in
                Task { @MainActor in self?.finishLoginSuccess() }
            },
            failure: { [weak self] error in
                Task { @MainActor in self?.finishAppleLoginFailure(error) }
            }
        )
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    func handleAppleAuthorizationFailure(_ error: Error) {
        _ = error
        busy = false
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Sign in with Apple did not complete. Exact scooter membership remains locked."
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
                failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error, submittedIdentity: identity, submittedVerificationCode: code) } }
            )
        case .phone:
            ThingSmartUser.sharedInstance()?.login(
                withMobile: identity,
                countryCode: country,
                code: code,
                success: { [weak self] in Task { @MainActor in self?.finishLoginSuccess() } },
                failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error, submittedIdentity: identity, submittedVerificationCode: code) } }
            )
        }
#else
        status = "Official Tuya SmartLife SDK is not compiled into this build."
#endif
    }

    func signOut() {
        guard !busy else { return }
        guard loggedIn || OfficialTuyaFactory.accountLoggedIn else {
            bootstrap()
            return
        }
#if canImport(ThingSmartHomeKit)
        guard let user = ThingSmartUser.sharedInstance() else {
            loggedIn = OfficialTuyaFactory.accountLoggedIn
            status = loggedIn
                ? "Tuya SDK reports an account, but its user session is unavailable. Capture remains locked; relaunch before trying another account."
                : "No Tuya SDK account is active. Use the account that owns this scooter."
            return
        }
        busy = true
        status = "Signing out of the current Tuya SDK account…"
        user.loginOut({ [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                self.verificationCode = ""
                self.codeSent = false
                self.loggedIn = OfficialTuyaFactory.accountLoggedIn
                if self.loggedIn {
                    self.status = "Tuya returned logout success, but the SDK still reports a current account. Capture remains locked; try again or relaunch Capture."
                } else {
                    self.account = ""
                    self.status = "Signed out. Use the Tuya account that owns this scooter."
                }
            }
        }, failure: { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                let submittedIdentity = self.account
                self.busy = false
                self.loggedIn = OfficialTuyaFactory.accountLoggedIn
                self.status = "Tuya could not sign out of the current SDK account: \(Self.redactedError(error, submittedIdentity: submittedIdentity, submittedVerificationCode: ""))"
            }
        })
#else
        loggedIn = false
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

    private func finishLoginFailure(_ error: Error?, submittedIdentity: String, submittedVerificationCode: String) {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya SDK login failed: \(Self.redactedError(error, submittedIdentity: submittedIdentity, submittedVerificationCode: submittedVerificationCode))"
    }

    private func finishAppleLoginFailure(_ error: Error?) {
        busy = false
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        let code = (error as NSError?)?.code ?? -1
        status = "Tuya rejected the Apple-account login (code \(code)). Exact scooter membership remains locked."
    }

    private static func redactedError(_ error: Error?, submittedIdentity: String, submittedVerificationCode: String) -> String {
        var redacted = error?.localizedDescription ?? "unknown error"
        let identity = submittedIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identity.isEmpty {
            redacted = redacted.replacingOccurrences(
                of: identity,
                with: "<redacted-account>",
                options: [.caseInsensitive, .literal]
            )
        }
        let verificationCode = submittedVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !verificationCode.isEmpty {
            redacted = redacted.replacingOccurrences(
                of: verificationCode,
                with: "<redacted-verification-code>",
                options: [.literal]
            )
        }
        return redacted
    }
}

@MainActor
private struct SecureLinkView: View {
    @StateObject private var test: SecureLinkController
    @StateObject private var sdkAccount = OfficialTuyaAccountAuthorizer()
    @State private var showEngineeringDetails = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

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
            if scenePhase == .active {
                test.activateMembershipRequestsForView()
            } else {
                test.appDidLoseForeground()
            }
            sdkAccount.bootstrap()
            if scenePhase == .active, sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
                test.consumeCorrelationAsyncInvalidation()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                test.activateMembershipRequestsForView()
                if sdkAccount.loggedIn { test.verifySDKMembership() }
            } else {
                test.appDidLoseForeground()
            }
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
            if loggedIn { test.verifySDKMembership() }
            else { test.invalidateSDKMembership() }
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
                if !dynamicTypeSize.isAccessibilitySize {
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
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(phaseKicker)
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(heroAccent)
                    Text(phaseTitle)
                        .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(phaseSubtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var stageRail: some View {
        if test.phase == .failed {
            HStack(spacing: 10) {
                Image(systemName: "stop.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Attempt stopped")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                    Text(test.canRestartFromFreshOFF1
                         ? "Begin again from scooter OFF"
                         : "Relaunch before another attempt")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Capture attempt stopped")
            .accessibilityValue(test.canRestartFromFreshOFF1
                                ? "Restore the requirement, then begin a new attempt from scooter off"
                                : "Relaunch Capture before another attempt")
        } else if dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 10) {
                Text("Step \(currentStageIndex + 1) of 4")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(stageLabels[currentStageIndex])
                    .font(.headline)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                test.phase == .accepted
                    ? "All 4 Capture steps complete, Seal"
                    : "Step \(currentStageIndex + 1) of 4, \(stageLabels[currentStageIndex])"
            )
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
                    .accessibilityLabel("Step \(index + 1), \(label)\(test.phase == .accepted || index < currentStageIndex ? ", complete" : index == currentStageIndex ? ", current" : ", upcoming")")
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
            if !test.fieldBuildIsAuthoritative || !test.privateConfig {
                VStack(spacing: 16) {
                    failureRecoveryContextPanel
                    preflightPanel
                }
            } else if test.canRestartFromFreshOFF1 && (!sdkAccount.loggedIn || !test.sdkAccountLoggedIn) {
                VStack(spacing: 16) {
                    failureRecoveryContextPanel
                    sdkAuthorizationPanel
                }
            } else if test.canRestartFromFreshOFF1 && test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized) {
                VStack(spacing: 16) {
                    failureRecoveryContextPanel
                    preflightPanel
                }
            } else {
                failurePanel
            }
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
                         ? "Next, Nembra will match this scooter by its OFF → ON → OFF → ON signal pattern. Keep the scooter stationary and begin with it powered off."
                         : "Capture stays locked until this Capture build, your Tuya account, and this scooter in that account are all confirmed.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    requirementRow("Capture build", ready: test.fieldBuildIsAuthoritative)
                    requirementRow("Tuya secure service", ready: test.privateConfig)
                    requirementRow("Tuya account", ready: test.sdkAccountLoggedIn)
                    requirementRow("This scooter in account", ready: test.sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized)
                }

                if test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(test.membershipStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(test.membershipBusy ? "Checking scooter…" : "Verify this scooter") {
                            test.verifySDKMembership()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(test.membershipBusy || sdkAccount.busy)

                        Button("Use a different Tuya account") {
                            sdkAccount.signOut()
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .disabled(test.membershipBusy || sdkAccount.busy)
                        .accessibilityHint("Signs out of the official Tuya SDK account so you can log in with the account that owns this scooter.")
                    }
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
                    .accessibilityHint("Starts the first read-only signal check with the scooter powered off.")
                }
            }
        }
    }

    private var correlationDisplayedWindowOrdinal: Int {
        test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)
    }

    private var correlationPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 18) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FIND SCOOTER")
                                .font(.caption2.bold())
                                .tracking(1.2)
                                .foregroundStyle(.cyan)
                            Text(test.phase == .correlated ? "Scooter signal found" : test.correlationWindowLabel)
                                .font(.title2.bold())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("\(correlationDisplayedWindowOrdinal)/4")
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Correlation progress")
                            .accessibilityValue("\(correlationDisplayedWindowOrdinal) of 4 windows")
                    }
                } else {
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
                        Text("\(correlationDisplayedWindowOrdinal)/4")
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Correlation progress")
                            .accessibilityValue("\(correlationDisplayedWindowOrdinal) of 4 windows")
                    }
                }

                if test.phase == .correlated {
                    Text("One nearby signal repeated through the full OFF → ON → OFF → ON pattern. Confirm this signal for the current attempt before Nembra opens the secure read-only link.")
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
                    .accessibilityHint("Finishes only after this read-only signal check has run long enough to be valid.")
                }

                Text("Only the full OFF → ON → OFF → ON pattern can authorize the nearby signal for this attempt.")
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
                    Text("Scooter signal confirmed")
                        .font(.title2.bold())
                    Text("Nembra can now open the secure Tuya link. Capture stays read-only and cannot send scooter commands.")
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
                    Text("Tuya owns the secure Bluetooth link now. Capture is waiting for this scooter's current read-only session.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("OBSERVE")
                        .font(.caption2.bold())
                        .tracking(1.2)
                        .foregroundStyle(.cyan)
                    Text("Hold steady")
                        .font(.title2.bold())
                    Text("Keep Capture in the foreground and leave the scooter untouched until this read-only observation is complete.")
                        .foregroundStyle(.secondary)

                    let age = test.canonicalObservedAgeSeconds ?? 0
                    VStack(alignment: .leading, spacing: 8) {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Read-only observation")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(Int(min(age, 45))) / 45 s")
                                    .font(.subheadline.monospacedDigit().bold())
                            }
                        } else {
                            HStack {
                                Text("Read-only observation")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Int(min(age, 45))) / 45 s")
                                    .font(.subheadline.monospacedDigit().bold())
                            }
                        }
                        ProgressView(value: min(age / 45, 1))
                            .accessibilityLabel("Read-only observation progress")
                            .accessibilityValue("\(Int(min(age, 45))) of 45 seconds")
                        requirementRow("Secure local link", ready: test.sdkLocalBLEOnline)
                        requirementRow("Repeated scooter data", ready: test.applicationUpdateCount >= TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount)
                        requirementRow("Scooter data stayed live", ready: test.applicationEvidenceSurvivedHistoricalWindow)
                    }
                }
            }
        }
    }

    private var failureRecoveryContextPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Capture stopped", systemImage: "exclamationmark.circle")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text(test.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Restore the missing requirement below. This stopped attempt will not be reused.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                failureDiagnosticsControls
            }
        }
    }

    private var failurePanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 16) {
                Label("Capture stopped", systemImage: "exclamationmark.circle")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text(test.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                failureDiagnosticsControls

                if test.canRestartFromFreshOFF1 {
                    Text("Nothing from the stopped attempt will carry forward. Restore the required setup, then begin again with the scooter powered off.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        test.retry()
                    } label: {
                        Label("Restart from scooter OFF", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!authorityReady || test.membershipBusy)
                } else {
                    Label("Relaunch Capture before another attempt", systemImage: "arrow.clockwise.circle")
                        .font(.headline)
                    Text("The previous secure session did not fully close inside the app, so Capture will not start another attempt until you relaunch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var failureDiagnosticsControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(Color.white.opacity(0.08))

            if let data = test.exportData {
                Text("Sanitized diagnostics ready")
                    .font(.subheadline.weight(.semibold))
                ShareLink(item: SecureTransfer(data: data, name: test.exportName), preview: SharePreview(test.exportName)) {
                    Label("Share diagnostics", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Shares only sanitized failed-attempt diagnostic evidence. It is not an accepted Capture artifact.")
            } else {
                Button {
                    test.prepareExport()
                } label: {
                    Label("Prepare diagnostics", systemImage: "doc.badge.gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Prepares sanitized evidence from this stopped attempt for troubleshooting. It does not accept the Capture.")
            }

            if let diagnosticExportError = test.diagnosticExportError {
                Label(diagnosticExportError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Diagnostic preparation error")
                    .accessibilityValue(diagnosticExportError)
            }

            Text("Diagnostics preserve legitimate failed-attempt evidence for analysis. They never turn this stopped attempt into an accepted Capture.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var completionPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 18) {
                if let data = test.exportData {
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

                    Text("The accepted artifact is sealed and encoded. Later callbacks, account changes, or diagnostics cannot rewrite the bytes being shared.")
                        .foregroundStyle(.secondary)

                    ShareLink(item: SecureTransfer(data: data, name: test.exportName), preview: SharePreview(test.exportName)) {
                        Label("Share Capture", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Shares the immutable accepted Capture artifact for analysis.")
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CAPTURE SEALED")
                                .font(.caption2.bold())
                                .tracking(1.3)
                                .foregroundStyle(.cyan)
                            Text("Artifact preparation needed")
                                .font(.title2.bold())
                        }
                    }
                    Text(test.message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        test.prepareExport()
                    } label: {
                        Label("Retry sealed Capture preparation", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Retries encoding only the already sealed immutable Capture artifact.")
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
                Text("Use the same account method that owns this scooter in Tuya. Apple ID uses Apple's system sign-in through Tuya's documented account transport; email/phone verification remains available. Nembra never requests your password.")
                    .foregroundStyle(.secondary)
                Text(sdkAccount.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { @MainActor in
                        switch result {
                        case let .success(authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                                sdkAccount.handleAppleAuthorizationFailure(AppleAccountAuthorizationError.unexpectedCredential)
                                return
                            }
                            sdkAccount.loginWithApple(credential: credential)
                        case let .failure(error):
                            sdkAccount.handleAppleAuthorizationFailure(error)
                        }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .disabled(sdkAccount.busy)
                .accessibilityHint("Uses Apple's system authorization, then hands the transient identity token directly to Tuya for account login. Exact scooter membership is still verified separately.")

                HStack(spacing: 10) {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    Text("or use Tuya verification code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                }
                .accessibilityHidden(true)

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
                LabeledContent("Procedure", value: test.fieldProcedureIdentifier)
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
            Label(dynamicTypeSize.isAccessibilitySize ? "Details" : "Engineering details", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.weight(.semibold))
                .accessibilityLabel("Engineering details")
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
        case .baseline, .scanning, .powerOn, .correlated: return "FIND SCOOTER"
        case .selected, .authenticating: return "SECURE LINK"
        case .observing: return "OBSERVATION"
        default: return "PREFLIGHT"
        }
    }

    private var phaseTitle: String {
        switch test.phase {
        case .accepted: return test.exportData == nil ? "Capture sealed" : "Capture complete"
        case .failed: return "Capture stopped"
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
            return test.exportData == nil
                ? "The evidence horizon is sealed. Prepare the immutable artifact before sharing it for analysis."
                : "The immutable accepted artifact is encoded and ready to share for analysis."
        case .failed:
            return test.canRestartFromFreshOFF1
                ? "Nothing from the stopped attempt will carry forward. Restore the missing requirement, then restart with the scooter powered off."
                : "The stopped attempt cannot be safely retired inside the app. Relaunch Capture before another attempt."
        case .baseline, .scanning, .powerOn, .correlated:
            return "The OFF → ON → OFF → ON signal pattern identifies the nearby scooter for this attempt only."
        case .selected, .authenticating:
            return "Nembra opens one secure Tuya connection while Capture stays read-only."
        case .observing:
            return "Keep the scooter stationary and Capture in the foreground until the read-only observation is complete."
        default:
            return authorityReady
                ? "Everything required to find this scooter by its current signal pattern is ready."
                : "Confirm this Capture build and the Tuya account that owns the scooter before Bluetooth starts."
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
