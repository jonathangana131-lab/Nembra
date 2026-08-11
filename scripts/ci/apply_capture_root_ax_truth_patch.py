#!/usr/bin/env python3
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


root = Path(__file__).resolve().parents[2]
entry_path = root / "NembraApp/App/NembraCaptureEntrypoint.swift"
visual_test_path = root / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/CaptureP0RootVisualAcceptanceTests.swift"
product_test_path = root / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift"

entry = entry_path.read_text()

entry = replace_once(
    entry,
    'Text(fieldBuildIsAuthoritative ? "Field build authority: ready" : "Field build authority: locked")',
    'Text(fieldBuildIsAuthoritative ? "Build provenance: ready" : "Build provenance: locked")',
    "engineering provenance label",
)

old_status = '''    private var buildAuthorityStatus: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: fieldBuildIsAuthoritative ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(fieldBuildIsAuthoritative ? Color.green : Color.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(fieldBuildIsAuthoritative ? "Field build ready" : "Physical capture locked")
                    .font(.headline)
                    .foregroundStyle(fieldBuildIsAuthoritative ? Color.green : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    fieldBuildIsAuthoritative
                        ? "Exact source, reviewed Tuya dependency, and stationary-procedure provenance are present. Account and scooter authority must still be verified before Bluetooth starts."
                        : "This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence. Install the reviewed field build before a physical Capture."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(dynamicTypeSize.isAccessibilitySize ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill((fieldBuildIsAuthoritative ? Color.green : Color.orange).opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke((fieldBuildIsAuthoritative ? Color.green : Color.orange).opacity(0.26), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fieldBuildIsAuthoritative ? "Field build ready" : "Physical capture locked")
        .accessibilityValue(
            fieldBuildIsAuthoritative
                ? "Build provenance is ready. Account and scooter authority are still required before Bluetooth starts."
                : "This public build can prepare account metadata only. Bluetooth and physical evidence collection are locked."
        )
    }
'''

new_status = '''    private var buildAuthorityDetail: String {
        if dynamicTypeSize.isAccessibilitySize {
            return fieldBuildIsAuthoritative
                ? "Provenance is present. Account and scooter checks are still required."
                : "Public build: account metadata only. Bluetooth and physical Capture stay locked."
        }

        return fieldBuildIsAuthoritative
            ? "Exact source, reviewed Tuya dependency, and stationary-procedure provenance are present. Account and scooter authority must still be verified before Bluetooth starts."
            : "This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence. Install the reviewed field build before a physical Capture."
    }

    private var buildAuthorityStatus: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: fieldBuildIsAuthoritative ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(fieldBuildIsAuthoritative ? Color.green : Color.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")
                    .font(.headline)
                    .foregroundStyle(fieldBuildIsAuthoritative ? Color.green : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)

                Text(buildAuthorityDetail)
                    .font(dynamicTypeSize.isAccessibilitySize ? .footnote : .subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(dynamicTypeSize.isAccessibilitySize ? 12 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill((fieldBuildIsAuthoritative ? Color.green : Color.orange).opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke((fieldBuildIsAuthoritative ? Color.green : Color.orange).opacity(0.26), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")
        .accessibilityValue(
            fieldBuildIsAuthoritative
                ? "Build provenance is ready. Account and scooter authority are still required before Bluetooth starts."
                : "This public build can prepare account metadata only. Bluetooth and physical evidence collection are locked."
        )
    }
'''
entry = replace_once(entry, old_status, new_status, "build authority block")

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
entry = replace_once(entry, old_account, new_account, "account setup block")
entry = replace_once(
    entry,
    'NavigationLink(fieldBuildIsAuthoritative ? "Continue to Capture" : "View locked preflight")',
    'NavigationLink(fieldBuildIsAuthoritative ? "Continue to preflight" : "View locked preflight")',
    "preflight navigation label",
)
entry_path.write_text(entry)

visual = visual_test_path.read_text()
visual = visual.replace(
    'Text(fieldBuildIsAuthoritative ? \\"Field build ready\\" : \\"Physical capture locked\\")',
    'Text(fieldBuildIsAuthoritative ? \\"Build provenance ready\\" : \\"Physical capture locked\\")',
)
visual = visual.replace(
    'NavigationLink(fieldBuildIsAuthoritative ? \\"Continue to Capture\\" : \\"View locked preflight\\")',
    'NavigationLink(fieldBuildIsAuthoritative ? \\"Continue to preflight\\" : \\"View locked preflight\\")',
)
anchor = '        #expect(root.contains(".accessibilityIdentifier(\\"capture.p0-root\\")"))\n'
addition = '''        #expect(root.contains("private var buildAuthorityDetail: String"))
        #expect(root.contains("Public build: account metadata only. Bluetooth and physical Capture stay locked."))
        #expect(root.contains("private var accountMetadataPrimaryAction: some View"))
        #expect(root.contains("private var accountMetadataSupportingCopy: some View"))
        #expect(root.contains("nembra.capture.root.account-link-action"))

        let panel = String(try section(
            in: root,
            from: "private var accountSetupPanel: some View",
            to: "private var accountMetadataPrimaryAction: some View"
        ))
        let accessibilityBranch = try #require(panel.range(of: "if dynamicTypeSize.isAccessibilitySize"))
        let primary = try #require(panel.range(of: "accountMetadataPrimaryAction", range: accessibilityBranch.upperBound..<panel.endIndex))
        let supporting = try #require(panel.range(of: "accountMetadataSupportingCopy", range: primary.upperBound..<panel.endIndex))
        #expect(primary.lowerBound < supporting.lowerBound)
'''
visual = replace_once(visual, anchor, anchor + addition, "visual AX contract anchor")
visual_test_path.write_text(visual)

product = product_test_path.read_text()
product = product.replace(
    'Text(fieldBuildIsAuthoritative ? \\"Field build ready\\" : \\"Physical capture locked\\")',
    'Text(fieldBuildIsAuthoritative ? \\"Build provenance ready\\" : \\"Physical capture locked\\")',
)
product = product.replace(
    'NavigationLink(fieldBuildIsAuthoritative ? \\"Continue to Capture\\" : \\"View locked preflight\\")',
    'NavigationLink(fieldBuildIsAuthoritative ? \\"Continue to preflight\\" : \\"View locked preflight\\")',
)
anchor = '        #expect(root.contains("TextField(\\"Paste user code\\""))\n'
addition = '''        #expect(root.contains("private var buildAuthorityDetail: String"))
        #expect(root.contains("Build provenance ready"))
        #expect(root.contains("private var accountMetadataPrimaryAction: some View"))
        #expect(root.contains("private var accountMetadataSupportingCopy: some View"))
        #expect(root.contains("nembra.capture.root.account-link-action"))

        let panel = String(try section(
            in: root,
            from: "private var accountSetupPanel: some View",
            to: "private var accountMetadataPrimaryAction: some View"
        ))
        let accessibilityBranch = try #require(panel.range(of: "if dynamicTypeSize.isAccessibilitySize"))
        let primary = try #require(panel.range(of: "accountMetadataPrimaryAction", range: accessibilityBranch.upperBound..<panel.endIndex))
        let supporting = try #require(panel.range(of: "accountMetadataSupportingCopy", range: primary.upperBound..<panel.endIndex))
        #expect(primary.lowerBound < supporting.lowerBound)
'''
product = replace_once(product, anchor, anchor + addition, "product AX contract anchor")
product_test_path.write_text(product)

print("Applied Capture root AX/truth convergence patch.")
