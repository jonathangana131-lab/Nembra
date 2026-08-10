from pathlib import Path
import subprocess

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
PRODUCT_DONOR = "d5915a97c1359846b103f08602db78eac815a47f"
ROOT_TEST_DONOR = "c7eda205d85da2d889e818cb9e15035ed8f4aa0a"
RECOVERY_TEST_DONOR = "3a6c0004c80ed9b3dff04e67d05358bc9d64c8a0"


def git_show(ref: str, path: str) -> str:
    return subprocess.check_output(["git", "show", f"{ref}:{path}"], text=True)


def replace_section(source: str, start: str, end: str, replacement: str) -> str:
    start_index = source.index(start)
    end_index = source.index(end, start_index)
    return source[:start_index] + replacement + source[end_index:]


def copy_from(ref: str, path: str) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(git_show(ref, path))


source = APP.read_text()
donor = git_show(PRODUCT_DONOR, APP.as_posix())

# Preserve the entire current controller/export/procedure stack. Only transplant the
# reviewed product surface tail from the prior product donor, then repair it against
# the current truth contracts.
view_marker = "@MainActor\nprivate struct SecureLinkView: View {"
donor_tail = donor[donor.index(view_marker):]

# The current field procedure is schema-10 authority and must remain visible in the
# engineering disclosure after the presentation transplant.
procedure_anchor = '                LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n'
if procedure_anchor not in donor_tail:
    raise SystemExit("product donor source-commit engineering anchor missing")
donor_tail = donor_tail.replace(
    procedure_anchor,
    procedure_anchor + '                LabeledContent("Procedure", value: test.fieldProcedureIdentifier)\n',
    1,
)

# Do not make view appearance a retry loop for a failed artifact encode. The single
# accepted transition may prepare automatically; after failure the operator gets an
# explicit retry from the already-frozen sealedAcceptedExport.
donor_tail = donor_tail.replace(
    '            if test.phase == .accepted && test.exportData == nil { test.prepareExport() }\n',
    '',
    1,
)

failure_start = "    private var failurePanel: some View {\n"
failure_end = "    private var completionPanel: some View {\n"
new_failure = '''    private var failurePanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 16) {
                Label("Capture paused", systemImage: "exclamationmark.circle")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text(test.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if test.failedAttemptCanRestartFromOFF1 {
                    Text("The previous attempt is fully retired. Fix the blocker above, then begin a fresh OFF1 correlation.")
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
                } else {
                    Label("Relaunch Capture", systemImage: "arrow.clockwise.circle")
                        .font(.headline)
                    Text("This attempt still retains package-generation authority. Close and reopen Capture before another OFF1 attempt; do not retry in this process.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

'''
donor_tail = replace_section(donor_tail, failure_start, failure_end, new_failure)

completion_start = "    private var completionPanel: some View {\n"
completion_end = "    private var sdkAuthorizationPanel: some View {\n"
new_completion = '''    private var completionPanel: some View {
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
                        if let data = test.exportData {
                            Text("Ready for analysis")
                                .font(.title.bold())
                            Text("The accepted artifact is sealed and shareable. Later callbacks, account changes, or diagnostics cannot rewrite what this capture proved.")
                                .foregroundStyle(.secondary)
                            ShareLink(item: SecureTransfer(data: data, name: test.exportName), preview: SharePreview(test.exportName)) {
                                Label("Share Capture", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityHint("Shares the immutable accepted Capture artifact for analysis.")
                        } else {
                            Text("Evidence sealed")
                                .font(.title.bold())
                            Text(test.message)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("The accepted evidence is frozen, but the shareable artifact is not ready yet. Retry only the encoding of that sealed artifact.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button {
                                test.prepareExport()
                            } label: {
                                Label("Retry sealed export", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
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
donor_tail = replace_section(donor_tail, completion_start, completion_end, new_completion)

donor_tail = donor_tail.replace(
    '        case .accepted:\n            return "Your read-only evidence is sealed and ready to share for analysis."\n        case .failed:\n            return "No evidence was promoted past the blocker. Fix the condition and restart from scooter OFF."',
    '        case .accepted:\n            return test.exportData != nil\n                ? "The sealed artifact is ready to share for analysis."\n                : "Evidence is sealed. Prepare the share artifact to continue."\n        case .failed:\n            return test.failedAttemptCanRestartFromOFF1\n                ? "No evidence was promoted past the blocker. A fresh OFF1 attempt is available after the issue is fixed."\n                : "No evidence was promoted past the blocker. Relaunch Capture before another attempt."',
    1,
)
if "Your read-only evidence is sealed and ready to share for analysis." in donor_tail:
    raise SystemExit("accepted hero still overclaims share readiness")

source = source[:source.index(view_marker)] + donor_tail

# Recovery authority belongs to the controller, not generic field readiness.
controller_anchor = '    var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }\n'
if controller_anchor not in source:
    raise SystemExit("current procedure authority anchor missing")
source = source.replace(
    controller_anchor,
    controller_anchor + '    var failedAttemptCanRestartFromOFF1: Bool { phase == .failed && currentConnectionToken == nil }\n',
    1,
)

# Replace the standalone first screen too. This is the screen the real no-authority
# Simulator evidence harness actually captures, so it must be product-quality rather
# than an engineering P0 console.
root_start = "@MainActor\nprivate struct CaptureP0Root: View {\n"
root_end = "@MainActor\nprivate final class SecureLinkController"
new_root = '''@MainActor
private struct CaptureP0Root: View {
    @StateObject private var tuya = TuyaAccountBridge()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.cyan.opacity(0.12), Color.clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 560
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        rootHero
                        accountSurface
                        if tuya.isLinked { scooterSurface }
                        rootEngineeringDetails
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 44)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var rootHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("NEMBRA CAPTURE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Label(tuya.isLinked ? "Account linked" : "Preflight", systemImage: tuya.isLinked ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tuya.isLinked ? Color.green : Color.cyan)
            }

            Text(tuya.isLinked ? "Choose your scooter" : "Prepare Capture")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(tuya.isLinked
                 ? "Select the scooter already bound to this account. Nembra will verify it again before any Bluetooth correlation begins."
                 : "Link the Tuya account that already owns your scooter. Nothing starts scanning until the guided preflight proves the required authority.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var accountSurface: some View {
        rootPanel {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1 · ACCOUNT")
                        .font(.caption2.bold())
                        .tracking(1.2)
                        .foregroundStyle(.cyan)
                    Text(tuya.isLinked ? "Account ready" : "Link the account that owns this scooter")
                        .font(.title2.bold())
                    Text(tuya.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !tuya.isLinked {
                    TextField("Tuya account code", text: $tuya.userCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .frame(minHeight: 50)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        }

                    Button(tuya.phase == .requestingApproval ? "Creating approval…" : "Create approval QR") {
                        tuya.requestApproval()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("Tuya account approval QR code")
                    Button("I approved it · check now") { tuya.checkApprovalNow() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }

                if tuya.phase == .failed {
                    Button("Reset account link") { tuya.resetLink() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
        }
    }

    private var scooterSurface: some View {
        rootPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("2 · SCOOTER")
                            .font(.caption2.bold())
                            .tracking(1.2)
                            .foregroundStyle(.cyan)
                        Text("Choose the scooter to capture")
                            .font(.title2.bold())
                    }
                    Spacer()
                    Button("Refresh") { tuya.refreshDevices() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if tuya.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No scooters loaded yet", systemImage: "scooter")
                            .font(.headline)
                        Text("Refresh the account devices. Capture will stay blocked until one exact device is selected and verified.")
                            .foregroundStyle(.secondary)
                        Button("Refresh Tuya devices") { tuya.refreshDevices() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }

                ForEach(tuya.devices) { device in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: tuya.selectedDeviceID == device.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(tuya.selectedDeviceID == device.id ? Color.green : Color.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name.isEmpty ? "Unnamed scooter" : device.name)
                                    .font(.headline)
                                let detail = [device.productName, device.category].filter { !$0.isEmpty }.joined(separator: " · ")
                                if !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }

                        if tuya.selectedDeviceID == device.id,
                           tuya.phase == .ready,
                           !device.productID.isEmpty,
                           !device.uuid.isEmpty {
                            NavigationLink {
                                SecureLinkView(device: device)
                            } label: {
                                Label("Continue to Capture", systemImage: "arrow.right.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            Button(tuya.selectedDeviceID == device.id ? "Refresh scooter metadata" : "Use this scooter") {
                                tuya.selectDevice(device)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
                }
            }
        }
    }

    private var rootEngineeringDetails: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("Account approval and device metadata establish which already-bound scooter continues into the guided Capture flow.")
                Text("Bluetooth target correlation, authenticated observation, immutable sealing, and export provenance remain separately evidence-gated inside Capture.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
        } label: {
            Label("Engineering details", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.weight(.semibold))
        }
        .tint(.secondary)
        .padding(.horizontal, 2)
    }

    private func rootPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
    }
}

'''
source = replace_section(source, root_start, root_end, new_root)

APP.write_text(source)

# Bring the reviewed product, recovery, root, and standalone visual evidence contracts
# onto this exact current-spine product repair.
copy_from(PRODUCT_DONOR, "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkProductSurfaceSourceTests.swift")
copy_from(ROOT_TEST_DONOR, "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift")
copy_from(RECOVERY_TEST_DONOR, "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkProductRecoveryTruthSourceTests.swift")
copy_from(PRODUCT_DONOR, "scripts/ci/capture_standalone_visual_evidence.sh")
copy_from(PRODUCT_DONOR, "scripts/ci/tests/test_capture_standalone_visual_evidence.py")
copy_from(PRODUCT_DONOR, ".github/workflows/capture-standalone-visual-acceptance.yml")

# Exact current-procedure guard: a product transplant may never regress schema-10 or
# the canonical physical recipe rendezvous.
final = APP.read_text()
required = [
    'schemaVersion: 10',
    'procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier',
    'var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }',
    'LabeledContent("Procedure", value: test.fieldProcedureIdentifier)',
    'var failedAttemptCanRestartFromOFF1: Bool { phase == .failed && currentConnectionToken == nil }',
    'if let data = test.exportData',
    'Label("Retry sealed export"',
    'Label("Relaunch Capture"',
    'Text("NEMBRA CAPTURE")',
]
missing = [item for item in required if item not in final]
if missing:
    raise SystemExit(f"current product repair missing required contracts: {missing}")
for forbidden in [
    'P0 · TUYA AUTHENTICATION',
    'Read-only control boundary',
    'Your read-only evidence is sealed and ready to share for analysis.',
    '.task { test.prepareExport() }',
]:
    if forbidden in final:
        raise SystemExit(f"superseded product source survived: {forbidden}")

print("current-spine premium Capture product patch: PASS")
