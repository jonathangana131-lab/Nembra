from pathlib import Path
import subprocess

EXPECTED_PARENT = "bf44f3e5c0b7ce3109bfdd3ecb760cfeafe04440"
APP_PATH = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST_PATH = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift")
DONOR_TEST = "c7eda205d85da2d889e818cb9e15035ed8f4aa0a"
START = "@MainActor\nprivate struct CaptureP0Root: View {"
END = "@MainActor\nprivate final class SecureLinkController"

parent = subprocess.check_output(["git", "rev-parse", "HEAD^"], text=True).strip()
if parent != EXPECTED_PARENT:
    raise SystemExit(f"Refusing stale root materialization: expected parent {EXPECTED_PARENT}, got {parent}")

source = APP_PATH.read_text(encoding="utf-8")
start = source.find(START)
end = source.find(END, start)
if start < 0 or end < 0:
    raise SystemExit("Capture root splice markers not found")

replacement = r'''@MainActor
private struct CaptureP0Root: View {
    @StateObject private var tuya = TuyaAccountBridge()
    @State private var showEngineeringDetails = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                        hero
                        preflightRail
                        accountPanel
                        if tuya.isLinked { devicePanel }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("NEMBRA CAPTURE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Label(rootStatusLabel, systemImage: rootStatusSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rootStatusTint)
            }

            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(rootStatusTint.opacity(0.14))
                        .frame(width: 64, height: 64)
                    Circle()
                        .stroke(rootStatusTint.opacity(0.30), lineWidth: 1)
                        .frame(width: 64, height: 64)
                    Image(systemName: tuya.isLinked ? "scooter" : "link.badge.plus")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(rootStatusTint)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(tuya.isLinked ? "PREFLIGHT" : "ACCOUNT LINK")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(rootStatusTint)
                    Text(tuya.isLinked ? "Choose your scooter" : "Prepare Capture")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tuya.isLinked
                         ? "Select the scooter that belongs to this Tuya account. The next screen will guide target correlation and read-only observation."
                         : "Link the Tuya account that owns your scooter before Bluetooth discovery begins.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var preflightRail: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Label("1. Link account", systemImage: tuya.isLinked ? "checkmark.circle.fill" : "1.circle.fill")
                Label("2. Choose scooter", systemImage: tuya.selectedDeviceID == nil ? "2.circle" : "checkmark.circle.fill")
                Label("3. Begin secure capture", systemImage: "3.circle")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .contain)
        } else {
            HStack(spacing: 8) {
                rootStep("Account", index: 1, complete: tuya.isLinked, current: !tuya.isLinked)
                rootStep("Scooter", index: 2, complete: tuya.selectedDeviceID != nil, current: tuya.isLinked)
                rootStep("Capture", index: 3, complete: false, current: false)
            }
        }
    }

    private var accountPanel: some View {
        rootPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TUYA ACCOUNT")
                            .font(.caption2.bold())
                            .tracking(1.2)
                            .foregroundStyle(.cyan)
                        Text(tuya.isLinked ? "Account linked" : "Link the scooter owner account")
                            .font(.title2.bold())
                    }
                    Spacer()
                    Image(systemName: tuya.isLinked ? "checkmark.circle.fill" : "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundStyle(tuya.isLinked ? Color.green : Color.cyan)
                        .accessibilityHidden(true)
                }

                Text(tuya.isLinked
                     ? "Tuya account access is ready. Choose the exact scooter below before starting Capture."
                     : "Use Tuya's approval flow so Nembra can read the devices already bound to your account.")
                    .foregroundStyle(.secondary)

                if !tuya.isLinked {
                    TextField("Tuya user code", text: $tuya.userCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHint("Enter the user code for the Tuya account that owns this scooter.")

                    Button {
                        tuya.requestApproval()
                    } label: {
                        Label(tuya.phase == .requestingApproval ? "Preparing approval…" : "Create approval QR", systemImage: "qrcode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(tuya.phase == .requestingApproval)
                }

                if let data = tuya.qrPNGData,
                   let image = UIImage(data: data),
                   !tuya.isLinked {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Approve in Tuya, then return to Nembra")
                            .font(.headline)
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 230)
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .accessibilityLabel("Tuya approval QR code")
                        Button("I approved it · check now") {
                            tuya.checkApprovalNow()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }

                if tuya.phase == .failed {
                    Text("Account approval did not complete. Nothing has started over Bluetooth.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("Reset account link") { tuya.resetLink() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var devicePanel: some View {
        rootPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR SCOOTER")
                            .font(.caption2.bold())
                            .tracking(1.2)
                            .foregroundStyle(.cyan)
                        Text("Choose the exact device")
                            .font(.title2.bold())
                    }
                    Spacer()
                    if tuya.devices.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text("Capture will not begin discovery until you explicitly choose a device from this linked account.")
                    .foregroundStyle(.secondary)

                if tuya.devices.isEmpty {
                    Button("Refresh Tuya devices") { tuya.refreshDevices() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }

                ForEach(tuya.devices) { device in
                    let isSelected = tuya.selectedDeviceID == device.id
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "scooter")
                                    .foregroundStyle(isSelected ? Color.green : Color.secondary)
                            }
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name.isEmpty ? "Tuya scooter" : device.name)
                                    .font(.headline)
                                let metadata = [device.productName, device.category].filter { !$0.isEmpty }.joined(separator: " · ")
                                if !metadata.isEmpty {
                                    Text(metadata)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if isSelected {
                                Label("Selected", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }

                        HStack(spacing: 10) {
                            Button(isSelected ? "Refresh metadata" : "Use this scooter") {
                                tuya.selectDevice(device)
                            }
                            .buttonStyle(.bordered)

                            if isSelected,
                               tuya.phase == .ready,
                               !device.productID.isEmpty,
                               !device.uuid.isEmpty {
                                NavigationLink {
                                    SecureLinkView(device: device)
                                } label: {
                                    Label("Continue to Capture", systemImage: "arrow.right")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(isSelected ? 0.075 : 0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isSelected ? Color.green.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
                    }
                }
            }
        }
    }

    private var engineeringDisclosure: some View {
        DisclosureGroup(isExpanded: $showEngineeringDetails) {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Account bridge", value: tuya.isLinked ? "Linked" : "Not linked")
                LabeledContent("Known devices", value: String(tuya.devices.count))
                if let selectedDeviceID = tuya.selectedDeviceID {
                    LabeledContent("Selected device ID", value: selectedDeviceID)
                        .privacySensitive()
                }
                Text(tuya.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Capture keeps this stage passive. Bluetooth correlation and authenticated observation begin only in the guided Capture flow.")
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

    private func rootStep(_ title: String, index: Int, complete: Bool, current: Bool) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(complete || current ? rootStatusTint : Color.white.opacity(0.08))
                    .frame(width: 26, height: 26)
                if complete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.black)
                } else {
                    Text("\(index)")
                        .font(.caption2.bold())
                        .foregroundStyle(current ? Color.black : Color.secondary)
                }
            }
            Text(title)
                .font(.caption2.weight(current ? .bold : .regular))
                .foregroundStyle(complete || current ? Color.primary : Color.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index), \(title), \(complete ? "complete" : current ? "current" : "upcoming")")
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

    private var rootStatusLabel: String {
        if tuya.isLinked { return "Account ready" }
        if tuya.phase == .failed { return "Setup blocked" }
        return "Preflight"
    }

    private var rootStatusSymbol: String {
        if tuya.isLinked { return "checkmark.shield.fill" }
        if tuya.phase == .failed { return "exclamationmark.shield" }
        return "shield"
    }

    private var rootStatusTint: Color {
        if tuya.isLinked { return .green }
        if tuya.phase == .failed { return .orange }
        return .cyan
    }
}'''

updated = source[:start] + replacement + "\n\n" + source[end:]
APP_PATH.write_text(updated, encoding="utf-8")

test = subprocess.check_output(["git", "show", f"{DONOR_TEST}:{TEST_PATH.as_posix()}"], text=True)
TEST_PATH.write_text(test, encoding="utf-8")

root = updated[updated.index("private struct CaptureP0Root: View"):updated.index(END)]
required = [
    "NEMBRA CAPTURE",
    "Engineering details",
    "tuya.requestApproval()",
    "tuya.checkApprovalNow()",
    "tuya.refreshDevices()",
    "tuya.selectDevice(device)",
    "SecureLinkView(device: device)",
]
for needle in required:
    if needle not in root:
        raise SystemExit(f"root repair lost required contract: {needle}")
for forbidden in ["P0 · TUYA AUTHENTICATION", "Prove the secure scooter link first.", "Read-only control boundary", "local_key", "No DP query", ".card()"]:
    if forbidden in root:
        raise SystemExit(f"root repair retained forbidden primary-surface copy: {forbidden}")
if "No DP query or scooter command is authorized by this surface." not in updated:
    raise SystemExit("guided Secure Link engineering truth boundary was lost")
