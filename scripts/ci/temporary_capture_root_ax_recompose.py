from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")
root_start = source.index("private struct CaptureP0Root: View")
root_end = source.index("@MainActor\nprivate final class SecureLinkController", root_start)
root = source[root_start:root_end]
if "@Environment(\\.dynamicTypeSize) private var dynamicTypeSize" in root:
    print("CaptureP0Root accessibility recompose is already present.")
    raise SystemExit(0)


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    source = source.replace(old, new, 1)


replace_once(
    """    @StateObject private var tuya = TuyaAccountBridge()
    @State private var showEngineeringDetails = false
""",
    """    @StateObject private var tuya = TuyaAccountBridge()
    @State private var showEngineeringDetails = false
    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize
""",
    "root dynamic type environment",
)

replace_once(
    """                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(\"NEMBRA CAPTURE\")
                                .font(.caption2.bold())
                                .tracking(1.5)
                                .foregroundStyle(.cyan)
                            Text(\"Prepare the scooter link\")
                                .font(.largeTitle.bold())
                            Text(\"One guided setup establishes the account and bound-device context Nembra will use before passive target correlation begins.\")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        rootPanel {
""",
    """                    VStack(alignment: .leading, spacing: rootContentSpacing) {
                        rootHero

                        rootPanel {
""",
    "root hero composition",
)

replace_once(
    """                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(\"Choose this scooter\")
                                            .font(.title3.bold())
                                        Text(\"Nembra will verify the selected device again inside the official SDK before Bluetooth discovery.\")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    if tuya.devices.isEmpty {
                                        Button(\"Refresh\") { tuya.refreshDevices() }
                                            .buttonStyle(.bordered)
                                    }
                                }
""",
    """                                scooterChooserHeader
""",
    "scooter chooser header",
)

replace_once(
    """                                    HStack(spacing: 10) {
                                        Button(tuya.selectedDeviceID == device.id ? \"Refresh metadata\" : \"Use this scooter\") {
                                            tuya.selectDevice(device)
                                        }
                                        .buttonStyle(.bordered)

                                        if tuya.selectedDeviceID == device.id,
                                           tuya.phase == .ready,
                                           !device.productID.isEmpty,
                                           !device.uuid.isEmpty {
                                            NavigationLink(\"Continue to Capture\") { SecureLinkView(device: device) }
                                                .buttonStyle(.borderedProminent)
                                        }
                                    }
""",
    """                                    scooterActions(for: device)
""",
    "scooter action layout",
)

replace_once(
    """                    .frame(maxWidth: 720)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 44)
                    .frame(maxWidth: .infinity)
""",
    """                    .frame(maxWidth: 720)
                    .padding(.horizontal, rootHorizontalPadding)
                    .padding(.top, rootTopPadding)
                    .padding(.bottom, rootBottomPadding)
                    .frame(maxWidth: .infinity)
""",
    "root adaptive outer spacing",
)

replace_once(
    """    @ViewBuilder
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
""",
    """    @ViewBuilder
    private var rootHero: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(\"NEMBRA CAPTURE\")
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(.cyan)
                Text(\"Prepare the scooter link\")
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(\"Link the Tuya account that owns this scooter before passive target correlation begins.\")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(\"NEMBRA CAPTURE\")
                    .font(.caption2.bold())
                    .tracking(1.5)
                    .foregroundStyle(.cyan)
                Text(\"Prepare the scooter link\")
                    .font(.largeTitle.bold())
                Text(\"One guided setup establishes the account and bound-device context Nembra will use before passive target correlation begins.\")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var scooterChooserHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                scooterChooserCopy
                if tuya.devices.isEmpty {
                    Button(\"Refresh\") { tuya.refreshDevices() }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
        } else {
            HStack {
                scooterChooserCopy
                Spacer(minLength: 8)
                if tuya.devices.isEmpty {
                    Button(\"Refresh\") { tuya.refreshDevices() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var scooterChooserCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(\"Choose this scooter\")
                .font(.title3.bold())
            Text(\"Nembra will verify the selected device again inside the official SDK before Bluetooth discovery.\")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func scooterActions(for device: TuyaAccountBridge.LinkedDevice) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                scooterSelectionButton(for: device)
                    .frame(maxWidth: .infinity, alignment: .leading)
                continueToCaptureLink(for: device)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 10) {
                scooterSelectionButton(for: device)
                continueToCaptureLink(for: device)
            }
        }
    }

    private func scooterSelectionButton(for device: TuyaAccountBridge.LinkedDevice) -> some View {
        Button(tuya.selectedDeviceID == device.id ? \"Refresh metadata\" : \"Use this scooter\") {
            tuya.selectDevice(device)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func continueToCaptureLink(for device: TuyaAccountBridge.LinkedDevice) -> some View {
        if tuya.selectedDeviceID == device.id,
           tuya.phase == .ready,
           !device.productID.isEmpty,
           !device.uuid.isEmpty {
            NavigationLink(\"Continue to Capture\") { SecureLinkView(device: device) }
                .buttonStyle(.borderedProminent)
        }
    }

    private var rootContentSpacing: CGFloat { dynamicTypeSize.isAccessibilitySize ? 14 : 22 }
    private var rootHorizontalPadding: CGFloat { dynamicTypeSize.isAccessibilitySize ? 16 : 20 }
    private var rootTopPadding: CGFloat { dynamicTypeSize.isAccessibilitySize ? 8 : 22 }
    private var rootBottomPadding: CGFloat { dynamicTypeSize.isAccessibilitySize ? 32 : 44 }
    private var rootPanelPadding: CGFloat { dynamicTypeSize.isAccessibilitySize ? 14 : 18 }
    private var rootPanelCornerRadius: CGFloat { dynamicTypeSize.isAccessibilitySize ? 20 : 24 }

    @ViewBuilder
    private func rootPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(rootPanelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: rootPanelCornerRadius, style: .continuous)
                    .fill(.white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: rootPanelCornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.09), lineWidth: 1)
                    )
            )
    }
""",
    "root accessibility helpers",
)

path.write_text(source, encoding="utf-8")
print("Applied CaptureP0Root Accessibility XXXL recompose.")
