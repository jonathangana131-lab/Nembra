from pathlib import Path
import subprocess

DONOR_PARENT = "dee52e17577d25dd6d928378b2fb530f321923bb"
DONOR_HEAD = "3d96865457a4dbdd22aed11d25e61c8a4de0af3b"
RED_RECOVERY = "3a6c0004c80ed9b3dff04e67d05358bc9d64c8a0"
RED_RESTART = "c693f2eb9a037341abfd7c3b1b18cbef116dfe02"
RED_ROOT = "c7eda205d85da2d889e818cb9e15035ed8f4aa0a"
APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return source.replace(old, new, 1)


# Reuse the reviewed guided-product donor blob, then reapply every Entrypoint byte
# introduced by the already-composed procedure rendezvous. The donor's parent and
# current flagship differ in this file only by those five procedure/schema lines.
run("git", "checkout", DONOR_HEAD, "--", "NembraApp/App/NembraCaptureEntrypoint.swift")
run("git", "checkout", DONOR_HEAD, "--", "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkProductSurfaceSourceTests.swift")
for commit, path in [
    (RED_RECOVERY, "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkProductRecoveryTruthSourceTests.swift"),
    (RED_RESTART, "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkRestartAuthoritySourceTests.swift"),
    (RED_ROOT, "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift"),
]:
    content = subprocess.check_output(["git", "show", f"{commit}:{path}"], text=True)
    Path(path).write_text(content, encoding="utf-8")

source = APP.read_text(encoding="utf-8")

# Restore the procedure rendezvous already accepted on the live flagship.
source = replace_once(
    source,
    "        let tuyaDependencyLockSHA256: String\n        let tuyaDeviceID: String\n",
    "        let tuyaDependencyLockSHA256: String\n        let procedureIdentifier: String\n        let tuyaDeviceID: String\n",
    "export procedure field",
)
source = replace_once(
    source,
    "    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }\n    var sdkAccountLoggedIn: Bool",
    "    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }\n    var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }\n    var sdkAccountLoggedIn: Bool",
    "procedure UI projection",
)
source = replace_once(source, "            schemaVersion: 9,\n", "            schemaVersion: 10,\n", "schema 10")
source = replace_once(
    source,
    "            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n            tuyaDeviceID: deviceID,\n",
    "            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n            procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier,\n            tuyaDeviceID: deviceID,\n",
    "procedure export value",
)
source = replace_once(
    source,
    "                LabeledContent(\"Source commit\", value: test.fieldBuildSourceCommitSHA)\n",
    "                LabeledContent(\"Source commit\", value: test.fieldBuildSourceCommitSHA)\n                LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)\n",
    "procedure engineering detail",
)

# Replace the standalone launch root rather than restoring the deleted generic card helper.
start = source.index("@MainActor\nprivate struct CaptureP0Root: View {")
end = source.index("@MainActor\nprivate final class SecureLinkController: NSObject, ObservableObject {", start)
root = '''@MainActor
private struct CaptureP0Root: View {
    @StateObject private var tuya = TuyaAccountBridge()
    @State private var showEngineeringDetails = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.cyan.opacity(0.13), Color.clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 560
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NEMBRA CAPTURE")
                                .font(.caption2.bold())
                                .tracking(1.5)
                                .foregroundStyle(.cyan)
                            Text("Prepare the scooter link")
                                .font(.largeTitle.bold())
                            Text("One guided setup proves the account and scooter Nembra will use before passive target correlation begins.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        rootPanel {
                            VStack(alignment: .leading, spacing: 14) {
                                Label(tuya.isLinked ? "Account link ready" : "Link your scooter account", systemImage: tuya.isLinked ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark")
                                    .font(.title3.bold())
                                    .foregroundStyle(tuya.isLinked ? Color.green : Color.primary)
                                Text(tuya.statusMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if !tuya.isLinked {
                                    TextField("Tuya Smart User Code", text: $tuya.userCode)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .padding(12)
                                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    Button("Create approval QR") { tuya.requestApproval() }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.large)
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
                                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    Button("I approved it · check now") { tuya.checkApprovalNow() }
                                        .buttonStyle(.bordered)
                                        .controlSize(.large)
                                }

                                if tuya.phase == .failed {
                                    Button("Reset account link") { tuya.resetLink() }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }

                        if tuya.isLinked {
                            rootPanel {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Choose this scooter")
                                                .font(.title3.bold())
                                            Text("Nembra will verify the selected device again inside the official SDK before Bluetooth discovery.")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 8)
                                        if tuya.devices.isEmpty {
                                            Button("Refresh") { tuya.refreshDevices() }
                                                .buttonStyle(.bordered)
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
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                Spacer()
                                                if tuya.selectedDeviceID == device.id {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(.green)
                                                        .accessibilityLabel("Selected")
                                                }
                                            }

                                            HStack(spacing: 10) {
                                                Button(tuya.selectedDeviceID == device.id ? "Refresh metadata" : "Use this scooter") {
                                                    tuya.selectDevice(device)
                                                }
                                                .buttonStyle(.bordered)

                                                if tuya.selectedDeviceID == device.id,
                                                   tuya.phase == .ready,
                                                   !device.productID.isEmpty,
                                                   !device.uuid.isEmpty {
                                                    NavigationLink("Continue to Capture") { SecureLinkView(device: device) }
                                                        .buttonStyle(.borderedProminent)
                                                }
                                            }
                                        }
                                        .padding(14)
                                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                }
                            }
                        }

                        DisclosureGroup(isExpanded: $showEngineeringDetails) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Account approval and device metadata only establish setup context. Capture independently verifies the current official SDK session and exact scooter membership before discovery.")
                                Text("No scooter commands are sent by this setup flow.")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        } label: {
                            Label("Engineering details", systemImage: "wrench.and.screwdriver")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(.secondary)
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 44)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Nembra Capture")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func rootPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.09), lineWidth: 1)
                    )
            )
    }
}

'''
source = source[:start] + root + source[end:]

# Controller-owned recovery authority: generic field readiness is insufficient if a
# terminal failure deliberately retained the exact package generation.
source = replace_once(
    source,
    "    var correlationCompletedWindowCount: Int { correlationProgress?.completedWindowCount ?? 0 }\n",
    "    var correlationCompletedWindowCount: Int { correlationProgress?.completedWindowCount ?? 0 }\n"
    "    var failedAttemptCanRestartFromOFF1: Bool {\n"
    "        phase == .failed && currentConnectionToken == nil && localBLESettlementToken == nil && driver == nil\n"
    "    }\n"
    "    var canRestartFromFreshOFF1: Bool { failedAttemptCanRestartFromOFF1 }\n",
    "failed restart authority",
)

# Accepted evidence is not analysis-ready until the immutable sealed envelope has
# successfully encoded into shareable bytes. Prepare once at the acceptance event;
# failed encoding remains an explicit retryable presentation state.
source = replace_once(
    source,
    "                        self.exportData = nil\n                        self.phase = .accepted\n                        self.message = \"Secure scooter link established. Canonical readiness and the complete accepted artifact were frozen before UI acceptance; delayed callbacks cannot mutate accepted evidence.\"\n                        self.log(\"acceptance_sealed\", [\n",
    "                        self.exportData = nil\n                        self.phase = .accepted\n                        self.prepareExport()\n                        self.log(\"acceptance_sealed\", [\n",
    "acceptance prepares sealed export once",
)
source = replace_once(
    source,
    "            if sdkAccount.loggedIn { test.verifySDKMembership() }\n            if test.phase == .accepted && test.exportData == nil { test.prepareExport() }\n",
    "            if sdkAccount.loggedIn { test.verifySDKMembership() }\n",
    "remove task export loop",
)
source = replace_once(
    source,
    "        .onChange(of: test.phase == .accepted) { _, accepted in\n            if accepted && test.exportData == nil { test.prepareExport() }\n        }\n",
    "",
    "remove accepted onChange exporter",
)

old_failure = '''    private var failurePanel: some View {
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
'''
new_failure = '''    private var failurePanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 16) {
                Label("Capture paused", systemImage: "exclamationmark.circle")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text(test.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if test.failedAttemptCanRestartFromOFF1 && test.canRestartFromFreshOFF1 {
                    Text("Nothing was promoted after the blocker. Re-establish the required field authority, then begin a fresh OFF1 attempt.")
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
                } else {
                    Label("Relaunch Capture before another attempt", systemImage: "arrow.clockwise.circle")
                        .font(.headline)
                    Text("The prior session generation was not proven retired in-process, so Capture will not offer an OFF1 restart here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
'''
source = replace_once(source, old_failure, new_failure, "failure panel")

completion_start = source.index("    private var completionPanel: some View {")
completion_end = source.index("    private var sdkAuthorizationPanel: some View {", completion_start)
completion = '''    private var completionPanel: some View {
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

'''
source = source[:completion_start] + completion + source[completion_end:]

source = replace_once(
    source,
    '        case .accepted: return "Capture complete"\n',
    '        case .accepted: return test.exportData == nil ? "Capture sealed" : "Capture complete"\n',
    "accepted hero title",
)
source = replace_once(
    source,
    '        case .accepted:\n            return "Your read-only evidence is sealed and ready to share for analysis."\n',
    '        case .accepted:\n            return test.exportData == nil\n                ? "The evidence horizon is sealed. Prepare the immutable artifact before sharing it for analysis."\n                : "The immutable accepted artifact is encoded and ready to share for analysis."\n',
    "accepted hero subtitle",
)

# Preserve an explicit product-level read-only authority sentence outside the root.
source = replace_once(
    source,
    '                    Text("Tuya can now become the sole Bluetooth owner. Capture remains read-only and sends no scooter control or DP query.")\n',
    '                    Text("Tuya can now become the sole Bluetooth owner. Capture remains read-only. No DP query or scooter command is authorized by this surface.")\n',
    "secure-link command boundary copy",
)

APP.write_text(source, encoding="utf-8")

# Static contract checks on the authored bytes. These do not replace Xcode/runtime acceptance.
root_body = source[source.index("private struct CaptureP0Root: View"):source.index("@MainActor\nprivate final class SecureLinkController")]
controller_body = source[source.index("private final class SecureLinkController"):source.index("private protocol OfficialTuyaDriver")]
failure_body = source[source.index("private var failurePanel: some View"):source.index("private var completionPanel: some View")]
completion_body = source[source.index("private var completionPanel: some View"):source.index("private var sdkAuthorizationPanel: some View")]
assert "NEMBRA CAPTURE" in root_body
assert "Engineering details" in root_body
assert ".card()" not in root_body
assert "local_key" not in root_body
assert "P0 · TUYA AUTHENTICATION" not in root_body
assert "var failedAttemptCanRestartFromOFF1: Bool" in controller_body
assert "var canRestartFromFreshOFF1: Bool" in controller_body
assert "currentConnectionToken == nil" in controller_body
assert "test.canRestartFromFreshOFF1" in failure_body
assert ".disabled(!authorityReady" not in failure_body
assert "if let data = test.exportData" in completion_body
assert completion_body.index("Ready for analysis") > completion_body.index("if let data = test.exportData")
assert "test.message" in completion_body
assert "Retry" in completion_body
assert ".task { test.prepareExport() }" not in completion_body
assert "read-only evidence is sealed and ready to share for analysis." not in source
assert "schemaVersion: 10" in source and "schemaVersion: 9" not in source
assert "procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier" in source
assert "No DP query or scooter command is authorized by this surface." in source
