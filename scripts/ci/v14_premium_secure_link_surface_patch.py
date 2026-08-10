from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkProductSurfaceSourceTests.swift")

source = APP.read_text()
start_marker = "@MainActor\nprivate struct SecureLinkView: View {"
end_marker = "\nprivate struct SecureTransfer: Transferable"
start = source.find(start_marker)
end = source.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit("SecureLinkView source anchors changed")

replacement = r'''@MainActor
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
'''

source = source[:start] + replacement + source[end:]
APP.write_text(source)

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Secure Link product surface")
struct TuyaSecureLinkProductSurfaceSourceTests {
    @Test("primary flow is a guided premium instrument rather than an engineering card stack")
    func guidedPrimaryFlowHidesEngineeringJargon() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)

        #expect(body.contains("NEMBRA CAPTURE"))
        #expect(body.contains("stageLabels = [\"Target\", \"Secure link\", \"Observe\", \"Seal\"]"))
        #expect(body.contains("private var engineeringDisclosure"))
        #expect(body.contains("Label(\"Engineering details\""))
        #expect(body.contains("Connection generation"))
        #expect(!body.contains("Canonical acceptance"))
        #expect(!body.contains("Prepare sanitized diagnostic JSON"))
        #expect(!body.contains("Share diagnostic JSON"))
        #expect(body.contains("navigationTitle(\"Capture\")"))
    }

    @Test("accepted experience prepares the sealed artifact and makes Share Capture primary")
    func acceptedExperienceIsCaptureCompleteShareFlow() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)

        #expect(body.contains("CAPTURE COMPLETE"))
        #expect(body.contains("Ready for analysis"))
        #expect(body.contains("Label(\"Share Capture\""))
        #expect(body.contains("if accepted && test.exportData == nil { test.prepareExport() }"))
        #expect(body.contains("Button(showEngineeringDetails ? \"Hide details\" : \"View details\")"))
        #expect(body.contains("accepted artifact is sealed"))
    }

    @Test("truth gates remain visible in the guided product surface")
    func truthGatesRemainProductVisible() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)

        #expect(body.contains("test.fieldBuildIsAuthoritative"))
        #expect(body.contains("test.accountIdentityLeaseIsAuthorized"))
        #expect(body.contains("test.correlationWindowIsScanning"))
        #expect(body.contains("test.confirmCorrelatedTarget()"))
        #expect(body.contains("test.authenticate()"))
        #expect(body.contains("test.sdkLocalBLEOnline"))
        #expect(body.contains("test.applicationUpdateCount > 0"))
        #expect(body.contains("Historical UUID, name, RSSI, FD50, and Tuya hints never authorize the target."))
        #expect(body.contains("No DP query or scooter command is authorized by this surface."))
    }

    @Test("large Dynamic Type receives a recomposed stage indicator")
    func accessibilityStageRailRecomposes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)

        #expect(body.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(body.contains("Step \\(currentStageIndex + 1) of 4"))
        #expect(body.contains("accessibilityHint"))
        #expect(body.contains("accessibilityLabel"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \\(start) ... \\(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
''')

# Portable product/structure checks. Apple SwiftUI type checking and screenshots belong to Xcode 27.
app = APP.read_text()
surface = app[app.index("private struct SecureLinkView: View"):app.index("private struct SecureTransfer: Transferable")]
assert "CAPTURE COMPLETE" in surface
assert "Ready for analysis" in surface
assert 'Label("Share Capture"' in surface
assert 'Label("Engineering details"' in surface
assert "Prepare sanitized diagnostic JSON" not in surface
assert "Canonical acceptance" not in surface
assert "test.confirmCorrelatedTarget()" in surface
assert "test.authenticate()" in surface
assert "test.accountIdentityLeaseIsAuthorized" in surface
assert "dynamicTypeSize.isAccessibilitySize" in surface

# Do not touch the controller's canonical truth machinery in this visual/product slice.
controller = app[app.index("private final class SecureLinkController"):app.index("private protocol OfficialTuyaDriver")]
for authority_anchor in (
    "captureAttemptEventStartIndex",
    "applicationUpdateAdmissionsInFlight",
    "acceptanceCutIsClosed",
    "sealedAcceptedExport",
    "sessionLedger.sealAcceptedObservation",
    "consumeCorrelationAsyncInvalidation",
):
    assert authority_anchor in controller, authority_anchor
