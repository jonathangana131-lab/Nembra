#!/usr/bin/env python3
from pathlib import Path

P = "ES80-AUTHENTICATED-STATIONARY-v1"


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one anchor, found {count}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))


# One compiled procedure identifier is shared by UI, immutable export, runbook,
# and field installer. It is source provenance, not physical evidence.
replace_once(
    "NembraApp/App/NembraCaptureBuildIdentity.swift",
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n',
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n'
    f'    static let fieldProcedureIdentifier = "{P}"\n',
)

replace_once(
    "NembraApp/App/NembraCaptureEntrypoint.swift",
    "        let tuyaDependencyLockSHA256: String\n        let tuyaDeviceID: String\n",
    "        let tuyaDependencyLockSHA256: String\n        let procedureIdentifier: String\n        let tuyaDeviceID: String\n",
)
replace_once(
    "NembraApp/App/NembraCaptureEntrypoint.swift",
    "    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }\n    var sdkAccountLoggedIn: Bool",
    "    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }\n"
    "    var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }\n"
    "    var sdkAccountLoggedIn: Bool",
)
replace_once(
    "NembraApp/App/NembraCaptureEntrypoint.swift",
    '            LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n            LabeledContent("Private SDK config"',
    '            LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n'
    '            LabeledContent("Procedure", value: test.fieldProcedureIdentifier)\n'
    '            LabeledContent("Private SDK config"',
)
replace_once(
    "NembraApp/App/NembraCaptureEntrypoint.swift",
    '            schemaVersion: 9,\n            purpose: "Sanitized Tuya authenticated read-only stationary preflight",',
    '            schemaVersion: 10,\n            purpose: "Sanitized Tuya authenticated read-only stationary preflight",',
)
replace_once(
    "NembraApp/App/NembraCaptureEntrypoint.swift",
    "            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n            tuyaDeviceID: deviceID,",
    "            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n"
    "            procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier,\n"
    "            tuyaDeviceID: deviceID,",
)

runbook = Path("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
runbook_text = runbook.read_text()
marker = f"PROCEDURE_ID: `{P}`"
if marker not in runbook_text:
    title = "# Nembra Capture P0 — secure-link gate\n"
    if runbook_text.count(title) != 1:
        raise SystemExit("runbook title anchor changed")
    runbook.write_text(runbook_text.replace(title, title + "\n" + marker + "\n", 1))

installer = Path("scripts/field/install_one_time_capture.command")
installer_text = installer.read_text()
if f'PROCEDURE_ID="{P}"' not in installer_text:
    anchor = 'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\n'
    if installer_text.count(anchor) != 1:
        raise SystemExit("installer bundle anchor changed")
    installer_text = installer_text.replace(anchor, anchor + f'PROCEDURE_ID="{P}"\n', 1)
summary_anchor = '    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, and standalone bundle identifier." \\\n'
summary_line = '    "Field procedure: $PROCEDURE_ID. The same identifier is compiled into the immutable accepted export." \\\n'
if summary_line not in installer_text:
    if installer_text.count(summary_anchor) != 1:
        raise SystemExit("installer launch-summary anchor changed")
    installer_text = installer_text.replace(summary_anchor, summary_anchor + summary_line, 1)
installer.write_text(installer_text)

procedure_test = Path(
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/"
    "TuyaFieldProcedureRendezvousSourceTests.swift"
)
procedure_test.write_text(
    f'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure rendezvous")
struct TuyaFieldProcedureRendezvousSourceTests {{
    private static let procedure = "{P}"

    @Test("compiled UI immutable export runbook and installer share one exact procedure")
    func oneProcedureAcrossFieldAuthoritySurfaces() throws {{
        let identity = try read("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let runbook = try read("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let installer = try read("scripts/field/install_one_time_capture.command")

        #expect(identity.contains("static let fieldProcedureIdentifier = \\\"\\(Self.procedure)\\\""))
        #expect(app.contains("let procedureIdentifier: String"))
        #expect(app.contains("procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier"))
        #expect(app.contains("LabeledContent(\\\"Procedure\\\", value: test.fieldProcedureIdentifier)"))
        #expect(runbook.contains("PROCEDURE_ID: `\\(Self.procedure)`"))
        #expect(installer.contains("PROCEDURE_ID=\\\"\\(Self.procedure)\\\""))
        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))
    }}

    @Test("procedure-bearing accepted export advances beyond dependency-lock schema")
    func exportSchemaAdvances() throws {{
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("schemaVersion: 10"))
        #expect(!app.contains("schemaVersion: 9"))
    }}

    private func read(_ path: String) throws -> String {{
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }}
}}
'''
)

# Schema 10 extends schema 9 with the exact procedure identifier; keep the
# dependency-provenance test validating its field without pinning the old schema.
replace_once(
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldDependencyProvenanceSourceTests.swift",
    '        #expect(app.contains("schemaVersion: 9"))\n',
    '        #expect(app.contains("schemaVersion: 10"))\n',
)

workflow = Path(".github/workflows/capture-field-build-provenance.yml")
workflow_text = workflow.read_text()
procedure_test_path = (
    "      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/"
    "TuyaFieldProcedureRendezvousSourceTests.swift\n"
)
if procedure_test_path not in workflow_text:
    anchor = (
        "      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/"
        "TuyaFieldInstallerIntendedDeviceAuthoritySourceTests.swift\n"
    )
    if workflow_text.count(anchor) != 1:
        raise SystemExit("field-provenance path anchor changed")
    workflow_text = workflow_text.replace(anchor, anchor + procedure_test_path, 1)

procedure_checks = (
    f'          grep -Fq \'static let fieldProcedureIdentifier = "{P}"\' "$identity"\n'
    f'          grep -Fq \'PROCEDURE_ID="{P}"\' "$installer"\n'
    '          grep -Fq \'schemaVersion: 10\' "$entrypoint"\n'
    '          grep -Fq \'procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier\' "$entrypoint"\n'
)
if f'static let fieldProcedureIdentifier = "{P}"' not in workflow_text:
    anchor = '          grep -Fq \'static let sourceCommitSHAInfoKey = "NembraCaptureSourceCommitSHA"\' "$identity"\n'
    if workflow_text.count(anchor) != 1:
        raise SystemExit("field-provenance identity anchor changed")
    workflow_text = workflow_text.replace(anchor, anchor + procedure_checks, 1)
workflow.write_text(workflow_text)

# Fail before committing if any rendezvous surface diverges.
for path in [
    "NembraApp/App/NembraCaptureBuildIdentity.swift",
    "NembraApp/App/NembraCaptureEntrypoint.swift",
    "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md",
    "scripts/field/install_one_time_capture.command",
    str(procedure_test),
]:
    if P not in Path(path).read_text():
        raise SystemExit(f"missing exact procedure rendezvous in {path}")

entrypoint = Path("NembraApp/App/NembraCaptureEntrypoint.swift").read_text()
if "schemaVersion: 9" in entrypoint or "schemaVersion: 10" not in entrypoint:
    raise SystemExit("accepted export schema did not converge to 10")
if "procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier" not in entrypoint:
    raise SystemExit("accepted export does not carry the compiled exact procedure")
