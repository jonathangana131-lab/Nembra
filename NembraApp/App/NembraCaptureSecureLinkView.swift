import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SecureLinkView: View {
    @StateObject private var test: SecureLinkController
    @StateObject private var sdkAccount: OfficialTuyaAccountAuthorizer

    init(device: TuyaAccountBridge.LinkedDevice) {
        _test = StateObject(wrappedValue: SecureLinkController(device: device))
        _sdkAccount = StateObject(wrappedValue: OfficialTuyaAccountAuthorizer())
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
                    statusCard
                    sdkCard
                    if test.sdkCompiled && test.privateConfig && !test.sdkAccountAuthorized {
                        sdkAuthorizationCard
                    }
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
        .task { sdkAccount.bootstrap() }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(test.passed ? "Secure scooter link established" : test.phase == .failed ? "Secure-link test stopped" : "Authentication preflight")
                    .font(.headline)
                Spacer()
                Text("\(test.applicationUpdateCount)")
                    .monospacedDigit()
            }
            Text(test.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let age = test.secureSessionAgeSeconds {
                LabeledContent("Canonical authenticated age", value: String(format: "%.1f s", age))
                ProgressView(value: min(age / 45, 1))
            }
            LabeledContent("Connection generation", value: String(test.preflightSnapshot.connectionGeneration))
            LabeledContent("Scooter membership", value: test.membershipLoading ? "Checking…" : test.scooterMembershipVerified ? "Verified" : "Not verified")
            LabeledContent("Tuya local BLE", value: test.sdkLocalBLEOnline ? "Online" : "Not proven")
            LabeledContent("Accepted application updates", value: String(test.applicationUpdateCount))
            if let reason = test.preflightBlockReason, !test.passed {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .captureCard()
    }

    private var sdkCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Official Tuya gate", systemImage: "checkmark.shield")
                .font(.headline)
            LabeledContent("SDK compiled in", value: test.sdkCompiled ? "Yes" : "No")
            LabeledContent("Private app config", value: test.privateConfig ? "Yes" : "No")
            LabeledContent("SDK account authorized", value: test.sdkAccountAuthorized ? "Yes" : "No")
            LabeledContent("Exact scooter membership", value: test.scooterMembershipVerified ? "Verified" : "Required before BLE")
            if let reason = test.scooterMembershipBlockReason,
               test.sdkAccountAuthorized,
               !test.membershipLoading,
               !test.scooterMembershipVerified {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !test.sdkCompiled || !test.privateConfig || !test.sdkAccountAuthorized {
                Text("NO PHYSICAL TEST YET: Tuya's official SDK/security component, matching private app credentials, and an authorized SDK account session must all be ready. Metadata QR approval alone is not BLE authentication.")
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            }
        }
        .captureCard()
    }

    private var discoveryCard: some View {
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
        .captureCard()
    }

    private func authenticationCard(_ candidate: SecureLinkController.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Authentication gate", systemImage: "key.horizontal")
                .font(.headline)
            Text(candidate.evidence.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(test.membershipLoading ? "Verifying scooter membership…" : "Verify membership + start secure test") {
                test.authenticate()
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                test.membershipLoading
                    || !candidate.likely
                    || !test.sdkCompiled
                    || !test.privateConfig
                    || !test.sdkAccountAuthorized
                    || [.authenticating, .observing, .accepted].contains(test.phase)
            )
        }
        .captureCard()
    }

    private var acceptanceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Acceptance", systemImage: test.passed ? "checkmark.seal.fill" : "hourglass")
                .font(.headline)
                .foregroundStyle(test.passed ? .green : .white)
            Text("PASS requires exact scooter membership in the current official SDK account, then Nembra's canonical authenticated-session authority: current generation, accepted SmartLife provenance, a genuine non-empty decoded application update, valid monotonic chronology, and at least 45 seconds of SDK-local continuity. No DP meaning is inferred here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if test.passed {
                Text("Secure scooter link established\nReceiving scooter data")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
            }
        }
        .captureCard()
    }

    private var exportCard: some View {
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
            Text("Export includes candidate evidence, exact-account membership verdict, canonical generation/verdict/chronology, SDK-local status, failures, and opaque decoded application values. It explicitly marks raw FD50 bytes as not captured and excludes passwords, verification codes, account tokens, local_key, and AppSecret.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .captureCard()
    }

    private var sdkAuthorizationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Authorize the official SDK session", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            Text(sdkAccount.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Login method", selection: $sdkAccount.method) {
                ForEach(OfficialTuyaAccountAuthorizer.LoginMethod.allCases) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            TextField("Country code (for example 1)", text: $sdkAccount.countryCode)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            TextField(
                sdkAccount.method == .email ? "Tuya account email" : "Tuya account phone number",
                text: $sdkAccount.account
            )
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
                Button("Authorize SDK account") { sdkAccount.login() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        sdkAccount.busy
                            || sdkAccount.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
            Text("Nembra does not ask for or persist the Tuya account password here. Verification codes stay in memory and are cleared after the login attempt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .captureCard()
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

extension View {
    func captureCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}
