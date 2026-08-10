#!/usr/bin/env python3
from pathlib import Path
import subprocess

BRANCH = "product/v14-capture-premium-root-recovery-sol"
APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift")
WORKFLOW = Path(".github/workflows/apply-capture-premium-root-recovery.yml")
SELF = Path("scripts/ci/apply_capture_premium_root_recovery.py")


def run(*args: str) -> None:
    subprocess.run(args, check=True)


source = APP.read_text(encoding="utf-8")
start_marker = "@MainActor\nprivate struct CaptureP0Root: View {"
end_marker = "@MainActor\nprivate final class SecureLinkController"
start = source.index(start_marker)
end = source.index(end_marker, start)

replacement = r'''@MainActor
private struct CaptureP0Root: View {
    @StateObject private var tuya = TuyaAccountBridge()
    @State private var showEngineeringDetails = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.cyan.opacity(0.15), Color.clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 520
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        hero
                        readinessRail
                        if tuya.isLinked {
                            deviceSelectionSurface
                        } else {
                            accountLinkSurface
                        }
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
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
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
                    tuya.isLinked ? "Account linked" : "Preflight",
                    systemImage: tuya.isLinked ? "checkmark.shield.fill" : "shield.lefthalf.filled"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(tuya.isLinked ? Color.green : Color.cyan)
            }

            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.14))
                        .frame(width: 64, height: 64)
                    Circle()
                        .stroke(Color.cyan.opacity(0.32), lineWidth: 1)
                        .frame(width: 64, height: 64)
                    Image(systemName: "scope")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.cyan)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(tuya.isLinked ? "SCOOTER ACCOUNT FOUND" : "PREFLIGHT")
                        .font(.caption2.bold())
                        .tracking(1.2)
                        .foregroundStyle(tuya.isLinked ? Color.green : Color.cyan)
                    Text(tuya.isLinked ? "Choose your scooter" : "Prepare Capture")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tuya.isLinked
                         ? "Choose the scooter already linked to this Tuya account, then continue into the secure read-only capture flow."
                         : "Link the Tuya account that already owns this scooter. Capture verifies live authority again before Bluetooth discovery starts.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var readinessRail: some View {
        HStack(spacing: 10) {
            readinessStep("Account", ready: tuya.isLinked)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            readinessStep("Scooter", ready: tuya.selectedDeviceID != nil)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            readinessStep("Capture", ready: false)
        }
        .accessibilityElement(children: .contain)
    }

    private func readinessStep(_ title: String, ready: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ready ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(title), \(ready ? "ready" : "not ready")")
    }

    private var accountLinkSurface: some View {
        surface {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LINK SCOOTER ACCOUNT")
                        .font(.caption2.bold())
                        .tracking(1.2)
                        .foregroundStyle(.cyan)
                    Text("Use the account that already owns this scooter")
                        .font(.title2.bold())
                    Text("This step discovers the scooter account only. It does not authorize Bluetooth or create physical evidence.")
                        .foregroundStyle(.secondary)
                }

                Text(tuya.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Tuya Smart User Code", text: $tuya.userCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .frame(minHeight: 50)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    }
                    .accessibilityHint("Enter the Tuya Smart User Code used to create account approval.")

                Button("Create secure approval") { tuya.requestApproval() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(tuya.phase == .requestingApproval)

                if let data = tuya.qrPNGData,
                   let image = UIImage(data: data) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Approve in Tuya")
                            .font(.headline)
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 230)
                            .padding(12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .accessibilityLabel("Tuya account approval QR code")
                        Button("I approved it · Check now") { tuya.checkApprovalNow() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
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

    private var deviceSelectionSurface: some View {
        surface {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("CHOOSE SCOOTER")
                        .font(.caption2.bold())
                        .tracking(1.2)
                        .foregroundStyle(.cyan)
                    Text("Which scooter should Capture prepare?")
                        .font(.title2.bold())
                    Text("Selection identifies the intended Tuya device. The next screen still has to prove current field-build, account, membership, target, and local-link authority.")
                        .foregroundStyle(.secondary)
                }

                Text(tuya.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if tuya.devices.isEmpty {
                    Button("Refresh scooters") { tuya.refreshDevices() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                ForEach(tuya.devices) { device in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: tuya.selectedDeviceID == device.id ? "checkmark.circle.fill" : "scooter")
                                .font(.title3)
                                .foregroundStyle(tuya.selectedDeviceID == device.id ? Color.green : Color.cyan)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name.isEmpty ? "Tuya scooter" : device.name)
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

                        HStack(spacing: 10) {
                            Button(tuya.selectedDeviceID == device.id ? "Refresh" : "Use this scooter") {
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
                    .padding(16)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(tuya.selectedDeviceID == device.id ? Color.cyan.opacity(0.32) : Color.white.opacity(0.08), lineWidth: 1)
                    }
                }
            }
        }
    }

    private var engineeringDisclosure: some View {
        DisclosureGroup(isExpanded: $showEngineeringDetails) {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Account bridge", value: tuya.isLinked ? "Linked" : "Not linked")
                LabeledContent("Devices found", value: String(tuya.devices.count))
                LabeledContent("Scooter selected", value: tuya.selectedDeviceID == nil ? "No" : "Yes")
                Text("Account and device metadata on this screen are discovery inputs only. Capture promotes evidence only after the next screen's independent authority gates succeed.")
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

    private func surface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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

APP.write_text(source[:start] + replacement + source[end:], encoding="utf-8")

updated = APP.read_text(encoding="utf-8")
root = updated[updated.index("private struct CaptureP0Root: View"):updated.index(end_marker)]
for forbidden in (
    "P0 · TUYA AUTHENTICATION",
    "Prove the secure scooter link first.",
    "Read-only control boundary",
    "local_key",
    "No DP query",
    ".card()",
):
    if forbidden in root:
        raise SystemExit(f"premium root still contains forbidden primary-flow token: {forbidden}")
for required in (
    "NEMBRA CAPTURE",
    "Engineering details",
    "tuya.requestApproval()",
    "tuya.checkApprovalNow()",
    "tuya.refreshDevices()",
    "tuya.selectDevice(device)",
    "SecureLinkView(device: device)",
):
    if required not in root:
        raise SystemExit(f"premium root lost required authority/product token: {required}")
if "No DP query or scooter command is authorized by this surface." not in updated:
    raise SystemExit("guided Secure Link command boundary disappeared")

run("git", "diff", "--check")
run("swift", "test", "--package-path", "Packages/NembraBluetoothCapture", "--filter", "TuyaCaptureRootProductSurfaceSourceTests")
WORKFLOW.unlink()
SELF.unlink()
run("git", "add", str(APP), str(TEST), str(WORKFLOW), str(SELF))
run("git", "diff", "--cached", "--check")
run("git", "config", "user.name", "nembra-swarm-bot")
run("git", "config", "user.email", "nembra-swarm-bot@users.noreply.github.com")
run("git", "commit", "-m", "fix(capture): make standalone root a guided preflight")
run("git", "push", "origin", f"HEAD:{BRANCH}")
