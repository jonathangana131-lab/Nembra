#!/usr/bin/env python3
from pathlib import Path


def once(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"{label}: expected 1 match, found {n}")
    return text.replace(old, new, 1)

root = Path(__file__).resolve().parents[2]
entry_path = root / "NembraApp/App/NembraCaptureEntrypoint.swift"
visual_path = root / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/CaptureP0RootVisualAcceptanceTests.swift"
product_path = root / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift"

entry = entry_path.read_text()

status_marker = "    private var buildAuthorityStatus: some View {\n"
detail = '''    private var buildAuthorityDetail: String {
        if dynamicTypeSize.isAccessibilitySize {
            return fieldBuildIsAuthoritative
                ? "Provenance is present. Account and scooter checks are still required."
                : "Public build: account metadata only. Bluetooth and physical Capture stay locked."
        }

        return fieldBuildIsAuthoritative
            ? "Exact source, reviewed Tuya dependency, and stationary-procedure provenance are present. Account and scooter authority must still be verified before Bluetooth starts."
            : "This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence. Install the reviewed field build before a physical Capture."
    }

'''
entry = once(entry, status_marker, detail + status_marker, "authority detail insertion")
entry = once(
    entry,
    '''                Text(
                    fieldBuildIsAuthoritative
                        ? "Exact source, reviewed Tuya dependency, and stationary-procedure provenance are present. Account and scooter authority must still be verified before Bluetooth starts."
                        : "This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence. Install the reviewed field build before a physical Capture."
                )
                .font(.subheadline)
''',
    '''                Text(buildAuthorityDetail)
                .font(dynamicTypeSize.isAccessibilitySize ? .footnote : .subheadline)
''',
    "compact authority detail",
)
entry = once(entry, ".padding(dynamicTypeSize.isAccessibilitySize ? 14 : 16)\n", ".padding(dynamicTypeSize.isAccessibilitySize ? 12 : 16)\n", "authority padding")

old_account = '''    private var accountSetupPanel: some View {
        rootPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label(
                    tuya.isLinked ? "Account metadata ready" : "Prepare account metadata",
                    systemImage: tuya.isLinked ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark"
                )
                .font(.title3.bold())
                .foregroundStyle(tuya.isLinked ? Color.green : Color.primary)

                Text("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(tuya.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !tuya.isLinked {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Tuya Smart user code")
                            .font(.subheadline.weight(.semibold))
                        TextField("Paste user code", text: $tuya.userCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityLabel("Tuya Smart user code")
                            .accessibilityHint("Used only to create the Tuya account approval QR for metadata setup.")
                    }

                    Button {
                        tuya.requestApproval()
                    } label: {
                        Label("Create approval QR", systemImage: "qrcode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Creates the account-metadata approval QR. It does not start Bluetooth or physical Capture.")
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
    }
'''
new_account = '''    private var accountSetupPanel: some View {
        rootPanel {
            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 10 : 14) {
                Label(
                    tuya.isLinked ? "Account metadata ready" : "Prepare account metadata",
                    systemImage: tuya.isLinked ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark"
                )
                .font(.title3.bold())
                .foregroundStyle(tuya.isLinked ? Color.green : Color.primary)

                if dynamicTypeSize.isAccessibilitySize {
                    accountMetadataPrimaryAction
                    accountMetadataSupportingCopy
                } else {
                    accountMetadataSupportingCopy
                    accountMetadataPrimaryAction
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
    }

    @ViewBuilder
    private var accountMetadataPrimaryAction: some View {
        if !tuya.isLinked {
            VStack(alignment: .leading, spacing: 7) {
                Text("Tuya Smart user code")
                    .font(.subheadline.weight(.semibold))
                TextField("Paste user code", text: $tuya.userCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("Tuya Smart user code")
                    .accessibilityHint("Used only to create the Tuya account approval QR for metadata setup.")
            }

            Button {
                tuya.requestApproval()
            } label: {
                Label("Create approval QR", systemImage: "qrcode")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("nembra.capture.root.account-link-action")
            .accessibilityHint("Creates the account-metadata approval QR. It does not start Bluetooth or physical Capture.")
        }
    }

    @ViewBuilder
    private var accountMetadataSupportingCopy: some View {
        Text("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Text(tuya.statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
'''
entry = once(entry, old_account, new_account, "account action ordering")
entry_path.write_text(entry)

visual = visual_path.read_text()
anchor = '        #expect(root.contains(".accessibilityAddTraits(.isHeader)"))\n'
extra = '''        #expect(root.contains("private var buildAuthorityDetail: String"))
        #expect(root.contains("Public build: account metadata only. Bluetooth and physical Capture stay locked."))
        #expect(root.contains("private var accountMetadataPrimaryAction: some View"))
        #expect(root.contains("private var accountMetadataSupportingCopy: some View"))
        #expect(root.contains("nembra.capture.root.account-link-action"))

        let panel = String(try section(
            in: root,
            from: "private var accountSetupPanel: some View",
            to: "private var accountMetadataPrimaryAction: some View"
        ))
        let ax = try #require(panel.range(of: "if dynamicTypeSize.isAccessibilitySize"))
        let primary = try #require(panel.range(of: "accountMetadataPrimaryAction", range: ax.upperBound..<panel.endIndex))
        let supporting = try #require(panel.range(of: "accountMetadataSupportingCopy", range: primary.upperBound..<panel.endIndex))
        #expect(primary.lowerBound < supporting.lowerBound)
'''
visual = once(visual, anchor, anchor + extra, "visual AX contract")
visual_path.write_text(visual)

product = product_path.read_text()
anchor = '        #expect(root.contains("TextField(\\"Paste user code\\""))\n'
extra = '''        #expect(root.contains("private var buildAuthorityDetail: String"))
        #expect(root.contains("private var accountMetadataPrimaryAction: some View"))
        #expect(root.contains("private var accountMetadataSupportingCopy: some View"))
        #expect(root.contains("nembra.capture.root.account-link-action"))

        let panel = String(try section(
            in: root,
            from: "private var accountSetupPanel: some View",
            to: "private var accountMetadataPrimaryAction: some View"
        ))
        let ax = try #require(panel.range(of: "if dynamicTypeSize.isAccessibilitySize"))
        let primary = try #require(panel.range(of: "accountMetadataPrimaryAction", range: ax.upperBound..<panel.endIndex))
        let supporting = try #require(panel.range(of: "accountMetadataSupportingCopy", range: primary.upperBound..<panel.endIndex))
        #expect(primary.lowerBound < supporting.lowerBound)
'''
product = once(product, anchor, anchor + extra, "product AX contract")
legacy_marker = '    @Test("legacy card-based Capture root is retired from the metadata bridge")\n'
cloud_test = '''    @Test("metadata preparation bridge remains cloud-only and command-free")
    func metadataBridgeCannotAcquireBluetoothOrScooterCommandAuthority() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(bridge.contains("Official Tuya Smart account-link preflight"))
        #expect(bridge.contains("read-only Device Sharing endpoints"))
        #expect(bridge.contains("signedGET(path:"))
        #expect(!bridge.contains("import CoreBluetooth"))
        #expect(!bridge.contains("ThingSmartBLEManager"))
        #expect(!bridge.contains("connectBLE"))
        #expect(!bridge.contains("disconnectBLE"))
        #expect(!bridge.contains("publishDps"))
        #expect(!bridge.contains("queryDps"))
        #expect(!bridge.contains("writeValue"))
        #expect(!bridge.contains("setDp"))
    }

'''
product = once(product, legacy_marker, cloud_test + legacy_marker, "cloud-only bridge contract")
product_path.write_text(product)

print("Reapplied AX/truth correction to current #2612 parent files.")
