#!/usr/bin/env python3
import pathlib
import subprocess

PATH = pathlib.Path("NembraApp/App/NembraCaptureEntrypoint.swift")
VISUAL_SHA = "9df1def03af40f1e452acb3f6d2aa5d52dac5681"
MARKER = "@MainActor\nprivate final class SecureLinkController"

base = PATH.read_text()
visual = subprocess.check_output(["git", "show", f"{VISUAL_SHA}:{PATH.as_posix()}"], text=True)
if MARKER not in base or MARKER not in visual:
    raise SystemExit("SecureLinkController boundary missing")
if base[base.index(MARKER):] != visual[visual.index(MARKER):]:
    raise SystemExit("visual ingredient changes truth/runtime bytes after CaptureP0Root")

root = visual[:visual.index(MARKER)]
tail = base[base.index(MARKER):]

def once(old: str, new: str, label: str) -> None:
    global root
    count = root.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    root = root.replace(old, new, 1)

once(
    'Text(fieldBuildIsAuthoritative ? "Field build ready" : "Physical capture locked")',
    'Text(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")',
    "visible provenance title",
)
once(
    '.accessibilityLabel(fieldBuildIsAuthoritative ? "Field build ready" : "Physical capture locked")',
    '.accessibilityLabel(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")',
    "provenance accessibility label",
)
once(
    'Text(fieldBuildIsAuthoritative ? "Field build authority: ready" : "Field build authority: locked")',
    'Text(fieldBuildIsAuthoritative ? "Build provenance: ready" : "Build provenance: locked")',
    "engineering provenance label",
)
once(
    'NavigationLink(fieldBuildIsAuthoritative ? "Continue to Capture" : "View locked preflight")',
    'NavigationLink(fieldBuildIsAuthoritative ? "Continue to preflight" : "View locked preflight")',
    "preflight action wording",
)
once(
    """            .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())
            .fixedSize(horizontal: false, vertical: true)

            Text(""",
    """            .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)

            Text(""",
    "hero heading trait",
)
once(
    """            .foregroundStyle(Color.white.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var buildAuthorityStatus""",
    """            .foregroundStyle(Color.white.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buildAuthorityStatus""",
    "hero semantic separation",
)

build_helper = """    private var buildAuthorityDetail: String {
        if dynamicTypeSize.isAccessibilitySize {
            return fieldBuildIsAuthoritative
                ? \"Provenance is present. Account and scooter checks are still required.\"
                : \"Public build: account metadata only. Bluetooth and physical Capture stay locked.\"
        }

        return fieldBuildIsAuthoritative
            ? \"Exact source, reviewed Tuya dependency, and stationary-procedure provenance are present. Account and scooter authority must still be verified before Bluetooth starts.\"
            : \"This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence. Install the reviewed field build before a physical Capture.\"
    }

"""
once(
    "    private var buildAuthorityStatus: some View {\n",
    build_helper + "    private var buildAuthorityStatus: some View {\n",
    "build authority detail helper",
)
once(
    """                Text(
                    isAccessibilityLayout
                        ? (fieldBuildIsAuthoritative
                            ? \"Account and scooter authority are still required before Bluetooth starts.\"
                            : \"Public build: account metadata only. Bluetooth and physical evidence stay locked.\")
                        : (fieldBuildIsAuthoritative
                            ? \"Exact source, reviewed Tuya dependency, and stationary-procedure provenance are present. Account and scooter authority must still be verified before Bluetooth starts.\"
                            : \"This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence. Install the reviewed field build before a physical Capture.\")
                )
                .font(isAccessibilityLayout ? .callout : .subheadline)""",
    """                Text(buildAuthorityDetail)
                    .font(isAccessibilityLayout ? .footnote : .subheadline)""",
    "build authority copy",
)

panel_start = """                if tuya.isLinked {
                    statusText
                } else {
"""
panel_end = "\n\n                if let data = tuya.qrPNGData,"
start = root.find(panel_start)
if start < 0:
    raise SystemExit("account panel start missing")
end = root.find(panel_end, start)
if end < 0:
    raise SystemExit("account panel end missing")
root = root[:start] + """                if dynamicTypeSize.isAccessibilitySize {
                    accountMetadataPrimaryAction
                    accountMetadataSupportingCopy
                } else {
                    accountMetadataSupportingCopy
                    accountMetadataPrimaryAction
                }""" + root[end:]

helpers = """    @ViewBuilder
    private var accountMetadataPrimaryAction: some View {
        if !tuya.isLinked {
            VStack(alignment: .leading, spacing: 7) {
                Text(\"Tuya Smart user code\")
                    .font(.subheadline.weight(.semibold))
                TextField(\"Paste user code\", text: $tuya.userCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(Color.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .accessibilityLabel(\"Tuya Smart user code\")
                    .accessibilityHint(\"Used only to create the Tuya account approval QR for metadata setup.\")
            }

            Button {
                tuya.requestApproval()
            } label: {
                Label(\"Create approval QR\", systemImage: \"qrcode\")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .foregroundStyle(.black)
            .accessibilityIdentifier(\"nembra.capture.root.account-link-action\")
            .accessibilityHint(\"Creates the account-metadata approval QR. It does not start Bluetooth or physical Capture.\")
        }
    }

    @ViewBuilder
    private var accountMetadataSupportingCopy: some View {
        Text(\"This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings.\")
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
        statusText
    }

"""
once(
    "    private var statusText: some View {\n",
    helpers + "    private var statusText: some View {\n",
    "account metadata helpers",
)

result = root + tail
required = [
    'Text(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")',
    '.accessibilityLabel(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")',
    'Text(fieldBuildIsAuthoritative ? "Build provenance: ready" : "Build provenance: locked")',
    'NavigationLink(fieldBuildIsAuthoritative ? "Continue to preflight" : "View locked preflight")',
    '.accessibilityAddTraits(.isHeader)',
    'private var buildAuthorityDetail: String',
    'Public build: account metadata only. Bluetooth and physical Capture stay locked.',
    'This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence.',
    'private var accountMetadataPrimaryAction: some View',
    'private var accountMetadataSupportingCopy: some View',
    'nembra.capture.root.account-link-action',
    'if dynamicTypeSize.isAccessibilitySize {\n                    accountMetadataPrimaryAction\n                    accountMetadataSupportingCopy',
    'This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings.',
]
for needle in required:
    if needle not in result:
        raise SystemExit(f"required current truth/visual contract missing: {needle}")

root_result = result[:result.index(MARKER)]
for needle in ["Field build ready", "Field build authority: ready", "Continue to Capture"]:
    if needle in root_result:
        raise SystemExit(f"stale authority wording survived: {needle}")
if '.accessibilityElement(children: .combine)' in root_result[root_result.index('private var rootHero'):root_result.index('private var buildAuthorityDetail')]:
    raise SystemExit("root hero still combines heading and support copy")

PATH.write_text(result)
