#!/usr/bin/env python3
from pathlib import Path

P = "ES80-AUTHENTICATED-STATIONARY-v1"


def read_lines(path: str) -> list[str]:
    return Path(path).read_text().splitlines(keepends=True)


def write_lines(path: str, lines: list[str]) -> None:
    Path(path).write_text("".join(lines))


def insert_after(path: str, anchor: str, line: str) -> None:
    lines = read_lines(path)
    if line in lines:
        return
    matches = [i for i, value in enumerate(lines) if value == anchor]
    if len(matches) != 1:
        raise SystemExit(f"{path}: expected one exact line anchor, found {len(matches)}: {anchor!r}")
    lines.insert(matches[0] + 1, line)
    write_lines(path, lines)


def insert_before(path: str, anchor: str, line: str) -> None:
    lines = read_lines(path)
    if line in lines:
        return
    matches = [i for i, value in enumerate(lines) if value == anchor]
    if len(matches) != 1:
        raise SystemExit(f"{path}: expected one exact line anchor, found {len(matches)}: {anchor!r}")
    lines.insert(matches[0], line)
    write_lines(path, lines)


def replace_line(path: str, old: str, new: str) -> None:
    lines = read_lines(path)
    if new in lines:
        return
    matches = [i for i, value in enumerate(lines) if value == old]
    if len(matches) != 1:
        raise SystemExit(f"{path}: expected one exact replace line, found {len(matches)}: {old!r}")
    lines[matches[0]] = new
    write_lines(path, lines)


identity = "NembraApp/App/NembraCaptureBuildIdentity.swift"
entrypoint = "NembraApp/App/NembraCaptureEntrypoint.swift"
runbook = "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"
installer = "scripts/field/install_one_time_capture.command"
dependency_test = (
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/"
    "TuyaFieldDependencyProvenanceSourceTests.swift"
)
procedure_test = (
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/"
    "TuyaFieldProcedureRendezvousSourceTests.swift"
)
field_workflow = ".github/workflows/capture-field-build-provenance.yml"

insert_after(
    identity,
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n',
    f'    static let fieldProcedureIdentifier = "{P}"\n',
)
insert_after(
    entrypoint,
    "        let tuyaDependencyLockSHA256: String\n",
    "        let procedureIdentifier: String\n",
)
insert_after(
    entrypoint,
    "    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }\n",
    "    var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }\n",
)
insert_after(
    entrypoint,
    '            LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n',
    '            LabeledContent("Procedure", value: test.fieldProcedureIdentifier)\n',
)
replace_line(
    entrypoint,
    "            schemaVersion: 9,\n",
    "            schemaVersion: 10,\n",
)
insert_after(
    entrypoint,
    "            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n",
    "            procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier,\n",
)

insert_after(
    runbook,
    "# Nembra Capture P0 — secure-link gate\n",
    f"\nPROCEDURE_ID: `{P}`\n",
)
insert_after(
    installer,
    'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\n',
    f'PROCEDURE_ID="{P}"\n',
)
insert_after(
    installer,
    '    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, and standalone bundle identifier." \\\n',
    '    "Field procedure: $PROCEDURE_ID. The same identifier is compiled into the immutable accepted export." \\\n',
)

Path(procedure_test).write_text(
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

replace_line(
    dependency_test,
    '        #expect(app.contains("schemaVersion: 9"))\n',
    '        #expect(app.contains("schemaVersion: 10"))\n',
)

insert_after(
    field_workflow,
    "      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerIntendedDeviceAuthoritySourceTests.swift\n",
    "      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldProcedureRendezvousSourceTests.swift\n",
)
insert_after(
    field_workflow,
    '          grep -Fq \'static let sourceCommitSHAInfoKey = "NembraCaptureSourceCommitSHA"\' "$identity"\n',
    f'          grep -Fq \'static let fieldProcedureIdentifier = "{P}"\' "$identity"\n',
)
insert_after(
    field_workflow,
    '          grep -Fq \'tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256\' "$entrypoint"\n',
    '          grep -Fq \'procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier\' "$entrypoint"\n',
)
insert_after(
    field_workflow,
    '          grep -Fq \'BUILD_LABEL="capture-v14-${SOURCE_SHA:0:12}"\' "$installer"\n',
    f'          grep -Fq \'PROCEDURE_ID="{P}"\' "$installer"\n',
)

# Fail closed before commit if any authority surface diverges. The Entrypoint
# intentionally references the one compiled BuildIdentity constant instead of
# repeating the literal; requiring the literal there made a correct transform
# fail its own verifier.
for path in (identity, runbook, installer, procedure_test):
    if P not in Path(path).read_text():
        raise SystemExit(f"missing exact procedure rendezvous in {path}")

app = Path(entrypoint).read_text()
if "schemaVersion: 9" in app or "schemaVersion: 10" not in app:
    raise SystemExit("accepted export schema did not converge to 10")
if "procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier" not in app:
    raise SystemExit("immutable accepted export does not carry the compiled procedure identifier")
if "fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }" not in app:
    raise SystemExit("user-visible field procedure source is not bound to the compiled identifier")

dep = Path(dependency_test).read_text()
if 'schemaVersion: 9' in dep or 'schemaVersion: 10' not in dep:
    raise SystemExit("dependency-provenance regression still pins the prior export schema")
