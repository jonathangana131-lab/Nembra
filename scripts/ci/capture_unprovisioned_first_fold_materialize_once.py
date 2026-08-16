from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
STRINGS = Path("NembraApp/Resources/Localizable.strings")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/CaptureFirstFoldCopySourceTests.swift")


def replace_region(text: str, start: str, end: str, replacement: str) -> str:
    if text.count(start) != 1 or text.count(end) != 1:
        raise SystemExit(f"region markers are not unique: {start!r} -> {end!r}")
    left = text.index(start)
    right = text.index(end, left)
    return text[:left] + replacement + text[right:]


source = APP.read_text(encoding="utf-8")

root_hero = '''    @ViewBuilder
    private var rootHero: some View {
        if !isAccessibilityLayout {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("RESEARCH CAPTURE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.46))

                    Spacer(minLength: 12)

                    Label(
                        fieldBuildIsAuthoritative ? "FIELD BUILD" : "CAPTURE LOCKED",
                        systemImage: fieldBuildIsAuthoritative ? "checkmark.shield.fill" : "lock.fill"
                    )
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(fieldBuildIsAuthoritative ? Color.green : Color.orange)
                }

                Text("Connect your scooter")
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(
                    fieldBuildIsAuthoritative
                        ? "Link the Tuya Smart account that already owns this scooter. Account and scooter verification still happen before Bluetooth starts."
                        : "Link the Tuya Smart account that already owns this scooter. Capture stays locked until the reviewed field build is installed."
                )
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

'''
source = replace_region(
    source,
    '    @ViewBuilder\n    private var rootHero: some View {',
    '    private var buildAuthorityStatus: some View {',
    root_hero,
)

build_status = '''    private var buildAuthorityStatus: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: fieldBuildIsAuthoritative ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(isAccessibilityLayout ? .body : .headline)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(fieldBuildIsAuthoritative ? Color.green : Color.orange)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(fieldBuildIsAuthoritative ? "Reviewed field build ready" : "Reviewed field build required")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !isAccessibilityLayout {
                    Text(fieldBuildIsAuthoritative ? "Verify this account and scooter next." : "Account linking is available. Bluetooth is not.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.60))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilitySortPriority(isAccessibilityLayout ? 100 : 0)
        .accessibilityLabel(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")
        .accessibilityValue(
            fieldBuildIsAuthoritative
                ? "Build provenance is ready. Account and scooter authority are still required before Bluetooth starts."
                : "This public build can link the Tuya account only. Bluetooth and physical evidence collection are locked."
        )
    }

'''
source = replace_region(
    source,
    '    private var buildAuthorityStatus: some View {',
    '    private var accountSetupPanel: some View {',
    build_status,
)

account_panel = '''    private var accountSetupPanel: some View {
        VStack(alignment: .leading, spacing: isAccessibilityLayout ? 14 : 16) {
            HStack(alignment: .center, spacing: 12) {
                if !isAccessibilityLayout {
                    Image(systemName: tuya.isLinked ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tuya.isLinked ? Color.green : Color.cyan)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.055), in: Circle())
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tuya.isLinked ? "Tuya Smart linked" : "Link Tuya Smart")
                        .font(isAccessibilityLayout ? .headline : .title3.bold())
                        .accessibilityAddTraits(.isHeader)
                        .foregroundStyle(tuya.isLinked ? Color.green : Color.primary)

                    Text(
                        tuya.isLinked
                            ? "Account context is ready for scooter selection."
                            : "Enter the user code from the Tuya Smart account that owns this scooter."
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if tuya.isLinked {
                statusText
            } else {
                TextField("Tuya Smart user code", text: $tuya.userCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 15)
                    .frame(minHeight: 52)
                    .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
                    .accessibilityLabel("Tuya Smart user code")
                    .accessibilityHint("Used only to create the Tuya account approval QR. It does not start Bluetooth.")

                Button {
                    tuya.requestApproval()
                } label: {
                    HStack(spacing: 10) {
                        Label("Show approval QR", systemImage: "qrcode.viewfinder")
                            .font(.headline)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.cyan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nembra.capture.root.account-link-action")
                .accessibilityLabel("Show approval QR")
                .accessibilityHint("Creates the Tuya account approval QR. It does not start Bluetooth or physical Capture.")

                if tuya.phase != .needsUserCode {
                    statusText
                }
            }

            if let data = tuya.qrPNGData,
               let image = UIImage(data: data),
               !tuya.isLinked {
                VStack(alignment: .leading, spacing: 12) {
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
                        .frame(maxWidth: isAccessibilityLayout ? .infinity : nil, alignment: .leading)
                }
            }

            if tuya.phase == .failed {
                Button("Reset account link") { tuya.resetLink() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .padding(.top, isAccessibilityLayout ? 2 : 4)
    }

'''
source = replace_region(
    source,
    '    private var accountSetupPanel: some View {',
    '    private var statusText: some View {',
    account_panel,
)

engineering = '''    private var engineeringDisclosure: some View {
        DisclosureGroup(isExpanded: $showEngineeringDetails) {
            VStack(alignment: .leading, spacing: 8) {
                Text(fieldBuildIsAuthoritative ? "Build provenance: ready" : "Build provenance: locked")
                Text("Account approval and device metadata only establish setup context. Capture independently verifies the current official SDK session and exact scooter membership before discovery.")
                Text("No scooter commands are sent by this setup flow.")
            }
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.64))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        } label: {
            Label("Technical details", systemImage: "info.circle")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.48))
                .accessibilityLabel("Engineering details")
        }
        .tint(Color.white.opacity(0.44))
        .padding(.top, 2)
    }

'''
source = replace_region(
    source,
    '    private var engineeringDisclosure: some View {',
    '    @ViewBuilder\n    private func rootSection<Content: View>',
    engineering,
)

for phrase in (
    "Prepare the scooter link",
    "Prepare account metadata",
    "This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings.",
):
    if phrase in source:
        raise SystemExit(f"retired first-fold copy survived: {phrase}")

for marker in (
    'Text("Connect your scooter")',
    'Text(tuya.isLinked ? "Tuya Smart linked" : "Link Tuya Smart")',
    'Label("Show approval QR", systemImage: "qrcode.viewfinder")',
    '.accessibilitySortPriority(isAccessibilityLayout ? 100 : 0)',
    'Capture stays locked until the reviewed field build is installed.',
    '.accessibilityLabel(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")',
):
    if marker not in source:
        raise SystemExit(f"missing redesigned first-fold marker: {marker}")

APP.write_text(source, encoding="utf-8")

STRINGS.write_text('''/* Standalone Capture first-fold product copy. */

"Connect your scooter" = "Connect your scooter";
"Link Tuya Smart" = "Link Tuya Smart";
"Show approval QR" = "Show approval QR";
"Link the Tuya Smart account that already owns this scooter. Capture stays locked until the reviewed field build is installed." = "Link the Tuya Smart account that already owns this scooter. Capture stays locked until the reviewed field build is installed.";
''', encoding="utf-8")

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture first-fold copy source contract")
struct CaptureFirstFoldCopySourceTests {
    @Test("standalone Capture keeps the locked first fold machine-first and concise")
    func compactStandardCopyIsBundled() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let strings = try readRepositoryFile("NembraApp/Resources/Localizable.strings")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        #expect(app.contains("Text(\"Connect your scooter\")"))
        #expect(app.contains("Text(tuya.isLinked ? \"Tuya Smart linked\" : \"Link Tuya Smart\")"))
        #expect(app.contains("Label(\"Show approval QR\", systemImage: \"qrcode.viewfinder\")"))
        #expect(app.contains("Capture stays locked until the reviewed field build is installed."))
        #expect(app.contains(".accessibilitySortPriority(isAccessibilityLayout ? 100 : 0)"))
        #expect(app.contains(".accessibilityLabel(fieldBuildIsAuthoritative ? \"Build provenance ready\" : \"Physical capture locked\")"))
        #expect(app.contains("Label(\"Technical details\", systemImage: \"info.circle\")"))
        #expect(app.contains(".font(.caption2.weight(.medium))"))

        #expect(!app.contains("Prepare the scooter link"))
        #expect(!app.contains("Prepare account metadata"))
        #expect(!app.contains("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."))

        #expect(strings.contains("\"Connect your scooter\" = \"Connect your scooter\";"))
        #expect(strings.contains("\"Link Tuya Smart\" = \"Link Tuya Smart\";"))
        #expect(strings.contains("\"Show approval QR\" = \"Show approval QR\";"))
        #expect(!strings.contains("Prepare account metadata"))

        #expect(project.contains("A10000000000000000000008 /* Localizable.strings in Resources */"))
        #expect(project.contains("B10000000000000000000008 /* Localizable.strings */"))
        #expect(project.contains("path = NembraApp/Resources/Localizable.strings"))
        #expect(project.contains("A10000000000000000000008 /* Localizable.strings in Resources */,"))
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
}
''', encoding="utf-8")
