#!/usr/bin/env python3
from pathlib import Path

ENTRYPOINT = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/CaptureP0RootVisualAcceptanceTests.swift")

source = ENTRYPOINT.read_text(encoding="utf-8")
start_marker = "@MainActor\nprivate struct CaptureP0Root: View {"
end_marker = "\n@MainActor\nprivate final class SecureLinkController:"
start = source.index(start_marker)
end = source.index(end_marker, start)

new_root = r'''@MainActor
private struct CaptureP0Root: View {
    @StateObject private var tuya = TuyaAccountBridge()
    @State private var showEngineeringDetails = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let buildIdentity = NembraCaptureBuildIdentity.current

    private var fieldBuildIsAuthoritative: Bool {
        buildIdentity.isAuthoritativeFieldBuild
    }

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
                    VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 22) {
                        rootHero
                        buildAuthorityStatus
                        accountSetupPanel

                        if tuya.isLinked {
                            scooterChooserPanel
                        }

                        DisclosureGroup(isExpanded: $showEngineeringDetails) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(fieldBuildIsAuthoritative ? "Field build authority: ready" : "Field build authority: locked")
                                Text("Account approval and device metadata only establish setup context. Capture independently verifies the current official SDK session and exact scooter membership before discovery.")
                                Text("No scooter commands are sent by this setup flow.")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                        } label: {
                            Label("Engineering details", systemImage: "wrench.and.screwdriver")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(.secondary)
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 20)
                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 14 : 22)
                    .padding(.bottom, 44)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Nembra Capture")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("capture.p0-root")
    }

    @ViewBuilder
    private var rootHero: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 6 : 8) {
            if !dynamicTypeSize.isAccessibilitySize {
                Text("NEMBRA CAPTURE")
                    .font(.caption2.bold())
                    .tracking(1.5)
                    .foregroundStyle(.cyan)
            }

            Text(
                dynamicTypeSize.isAccessibilitySize
                    ? (fieldBuildIsAuthoritative ? "Prepare Capture" : "Capture locked")
                    : "Prepare the scooter link"
            )
            .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())
            .fixedSize(horizontal: false, vertical: true)

            Text(
                dynamicTypeSize.isAccessibilitySize
                    ? (fieldBuildIsAuthoritative
                        ? "Link the account that owns this scooter before discovery."
                        : "Account setup only in this public build.")
                    : "One guided setup establishes account and bound-device context before passive target correlation. Physical Capture still depends on the field-build gate below."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var buildAuthorityStatus: some View {
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

    private var accountSetupPanel: some View {
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

    private var scooterChooserPanel: some View {
        rootPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose this scooter")
                            .font(.title3.bold())
                        Text("Nembra verifies the selected device again inside the official SDK before Bluetooth discovery.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
                                NavigationLink(fieldBuildIsAuthoritative ? "Continue to Capture" : "View locked preflight") {
                                    SecureLinkView(device: device)
                                }
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

    @ViewBuilder
    private func rootPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(dynamicTypeSize.isAccessibilitySize ? 14 : 18)
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
}'''

patched = source[:start] + new_root + source[end:]
ENTRYPOINT.write_text(patched, encoding="utf-8")

TEST.parent.mkdir(parents=True, exist_ok=True)
TEST.write_text(r'''import Foundation
import Testing

@Suite("Capture P0 root visual acceptance")
struct CaptureP0RootVisualAcceptanceTests {
    @Test("public root visibly fails closed while preserving metadata-only setup")
    func publicRootShowsFieldAuthorityBeforeAccountSetup() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = try section(
            in: source,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController:"
        )
        let body = String(root)

        #expect(body.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(body.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(body.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(body.contains("Text(fieldBuildIsAuthoritative ? \"Field build ready\" : \"Physical capture locked\")"))
        #expect(body.contains("This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence."))
        #expect(body.contains("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."))
        #expect(body.contains("NavigationLink(fieldBuildIsAuthoritative ? \"Continue to Capture\" : \"View locked preflight\")"))

        let heroUse = try #require(body.range(of: "rootHero\n                        buildAuthorityStatus\n                        accountSetupPanel"))
        #expect(heroUse.lowerBound < body.endIndex)
    }

    @Test("Accessibility XXXL receives a compact root hero and labeled metadata input")
    func accessibilityRootRecomposesInsteadOfScalingMarketingCopy() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController:"
        ))

        #expect(root.contains("if !dynamicTypeSize.isAccessibilitySize"))
        #expect(root.contains("fieldBuildIsAuthoritative ? \"Prepare Capture\" : \"Capture locked\""))
        #expect(root.contains("Account setup only in this public build."))
        #expect(root.contains(".font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())"))
        #expect(root.contains("Text(\"Tuya Smart user code\")"))
        #expect(root.contains("TextField(\"Paste user code\""))
        #expect(root.contains(".accessibilityLabel(\"Tuya Smart user code\")"))
        #expect(root.contains(".accessibilityIdentifier(\"capture.p0-root\")"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
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
''', encoding="utf-8")

bootstrap_paths = [
    Path("scripts/ci/v14_apply_capture_root_preflight_patch.py"),
    Path(".github/workflows/v14-capture-root-preflight-bootstrap.yml"),
]
for path in bootstrap_paths:
    if path.exists():
        path.unlink()

print("Applied Capture P0 root truth/accessibility repair and removed bootstrap files.")
