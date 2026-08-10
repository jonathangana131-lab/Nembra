#!/usr/bin/env python3
from pathlib import Path

PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"
INFO_KEY = "NembraCaptureProcedureIdentifier"
BUILD_SETTING = "NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER"


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one anchor, found {count}: {old[:160]!r}")
    p.write_text(text.replace(old, new, 1))


identity = "NembraApp/App/NembraCaptureBuildIdentity.swift"
replace_once(
    identity,
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n    static let fieldProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"\n',
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n'
    f'    static let fieldProcedureIdentifierInfoKey = "{INFO_KEY}"\n'
    f'    static let fieldProcedureIdentifier = "{PROCEDURE}"\n',
)
replace_once(
    identity,
    '    let tuyaDependencyLockSHA256: String\n\n    static var current: Self {',
    '    let tuyaDependencyLockSHA256: String\n    let compiledProcedureIdentifier: String\n\n    static var current: Self {',
)
replace_once(
    identity,
    '            sourceCommitSHA: ((infoDictionary[sourceCommitSHAInfoKey] as? String) ?? "").lowercased(),\n            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased()\n',
    '            sourceCommitSHA: ((infoDictionary[sourceCommitSHAInfoKey] as? String) ?? "").lowercased(),\n'
    '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased(),\n'
    '            compiledProcedureIdentifier: (infoDictionary[fieldProcedureIdentifierInfoKey] as? String) ?? ""\n',
)
replace_once(
    identity,
    '        let expectedIdentifier = "capture-v14-\\(sourceCommitSHA.prefix(12))"\n        return buildIdentifier == expectedIdentifier\n',
    '        let expectedIdentifier = "capture-v14-\\(sourceCommitSHA.prefix(12))"\n'
    '        return buildIdentifier == expectedIdentifier\n'
    '            && compiledProcedureIdentifier == Self.fieldProcedureIdentifier\n',
)

entrypoint = "NembraApp/App/NembraCaptureEntrypoint.swift"
replace_once(
    entrypoint,
    '    var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }\n',
    '    var fieldProcedureIdentifier: String { buildIdentity.compiledProcedureIdentifier }\n',
)
replace_once(
    entrypoint,
    '            procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier,\n',
    '            procedureIdentifier: buildIdentity.compiledProcedureIdentifier,\n',
)

project = "NembraCapture.xcodeproj/project.pbxproj"
project_path = Path(project)
project_text = project_path.read_text()
project_anchor = '\t\t\t\tINFOPLIST_KEY_NembraCaptureBuildIdentifier = "$(NEMBRA_CAPTURE_BUILD_IDENTIFIER)";\n'
project_line = f'\t\t\t\tINFOPLIST_KEY_{INFO_KEY} = "$({BUILD_SETTING})";\n'
if project_text.count(project_line) == 0:
    if project_text.count(project_anchor) != 2:
        raise SystemExit(f"{project}: expected Debug+Release build identifier anchors")
    project_text = project_text.replace(project_anchor, project_anchor + project_line)
elif project_text.count(project_line) != 2:
    raise SystemExit(f"{project}: procedure plist key count drifted")
project_path.write_text(project_text)

installer = "scripts/field/install_one_time_capture.command"
replace_once(
    installer,
    '    "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \\\n    build\n',
    '    "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \\\n'
    '    "NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID" \\\n'
    '    build\n',
)
replace_once(
    installer,
    'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\nBUILT_BUNDLE_ID=',
    'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n'
    'BUILT_PROCEDURE_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n'
    'BUILT_BUNDLE_ID=',
)
replace_once(
    installer,
    '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]]',
    '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n'
    '[[ "$BUILT_PROCEDURE_IDENTIFIER" == "$PROCEDURE_ID" ]] || die "Built Capture app procedure identifier does not match the canonical stationary procedure. Discard this candidate."\n'
    '[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]]',
)
replace_once(
    installer,
    'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, and field product"\nunset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_BUNDLE_ID APP_INFO_PLIST\n',
    'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, canonical field procedure, and field product"\n'
    'unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_PROCEDURE_IDENTIFIER BUILT_BUNDLE_ID APP_INFO_PLIST\n',
)

procedure_test = "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldProcedureRendezvousSourceTests.swift"
replace_once(
    procedure_test,
    '        #expect(identity.contains("fieldProcedureIdentifier"))\n        #expect(identity.contains(Self.procedure))\n        #expect(app.contains("let procedureIdentifier: String"))\n        #expect(app.contains("procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier"))\n',
    '        #expect(identity.contains("fieldProcedureIdentifierInfoKey = \\\"NembraCaptureProcedureIdentifier\\\""))\n'
    '        #expect(identity.contains("compiledProcedureIdentifier"))\n'
    '        #expect(identity.contains("compiledProcedureIdentifier == Self.fieldProcedureIdentifier"))\n'
    '        #expect(identity.contains(Self.procedure))\n'
    '        #expect(app.contains("let procedureIdentifier: String"))\n'
    '        #expect(app.contains("procedureIdentifier: buildIdentity.compiledProcedureIdentifier"))\n',
)
replace_once(
    procedure_test,
    '        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")\n        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")\n\n        #expect(runbook.contains("PROCEDURE_ID: `\\(Self.procedure)`"))\n        #expect(installer.contains("PROCEDURE_ID=\\\"\\(Self.procedure)\\\""))\n        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))\n',
    '        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")\n'
    '        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")\n'
    '        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")\n\n'
    '        #expect(runbook.contains("PROCEDURE_ID: `\\(Self.procedure)`"))\n'
    '        #expect(installer.contains("PROCEDURE_ID=\\\"\\(Self.procedure)\\\""))\n'
    '        #expect(installer.contains("NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID"))\n'
    '        #expect(installer.contains("plutil -extract NembraCaptureProcedureIdentifier"))\n'
    '        #expect(installer.contains("BUILT_PROCEDURE_IDENTIFIER\\\" == \\\"$PROCEDURE_ID"))\n'
    '        #expect(project.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier = \\\"$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)\\\";"))\n'
    '        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))\n',
)

workflow = ".github/workflows/capture-field-build-provenance.yml"
wf = Path(workflow).read_text()
identity_check = '          grep -Fq \'static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\' "$identity"\n'
extra_checks = (
    '          grep -Fq \'static let fieldProcedureIdentifierInfoKey = "NembraCaptureProcedureIdentifier"\' "$identity"\n'
    f'          grep -Fq \'static let fieldProcedureIdentifier = "{PROCEDURE}"\' "$identity"\n'
    '          grep -Fq \'compiledProcedureIdentifier == Self.fieldProcedureIdentifier\' "$identity"\n'
    '          grep -Fq \'INFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";\' "$project"\n'
    '          grep -Fq \'NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID\' "$installer"\n'
    '          grep -Fq \'plutil -extract NembraCaptureProcedureIdentifier raw -o - "$APP_INFO_PLIST"\' "$installer"\n'
    '          grep -Fq \'[[ "$BUILT_PROCEDURE_IDENTIFIER" == "$PROCEDURE_ID" ]]\' "$installer"\n'
    '          grep -Fq \'procedureIdentifier: buildIdentity.compiledProcedureIdentifier\' "$entrypoint"\n'
)
if 'compiledProcedureIdentifier == Self.fieldProcedureIdentifier' not in wf:
    if wf.count(identity_check) != 1:
        raise SystemExit("field provenance workflow identity anchor changed")
    wf = wf.replace(identity_check, identity_check + extra_checks, 1)

build_setting_anchor = '            NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256="$dependency_sha" \\\n            build\n'
if 'NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="ES80-AUTHENTICATED-STATIONARY-v1"' not in wf:
    if wf.count(build_setting_anchor) != 1:
        raise SystemExit("field provenance simulator build-setting anchor changed")
    wf = wf.replace(
        build_setting_anchor,
        '            NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256="$dependency_sha" \\\n'
        f'            NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="{PROCEDURE}" \\\n'
        '            build\n',
        1,
    )

plist_test_anchor = '          test "$(plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$plist")" = "$dependency_sha"\n'
procedure_plist_test = f'          test "$(plutil -extract NembraCaptureProcedureIdentifier raw -o - "$plist")" = "{PROCEDURE}"\n'
if procedure_plist_test not in wf:
    if wf.count(plist_test_anchor) != 1:
        raise SystemExit("field provenance simulator readback anchor changed")
    wf = wf.replace(plist_test_anchor, plist_test_anchor + procedure_plist_test, 1)
Path(workflow).write_text(wf)

# Final exact-contract proof before handing bytes to the connector.
required = {
    identity: [
        'fieldProcedureIdentifierInfoKey = "NembraCaptureProcedureIdentifier"',
        'let compiledProcedureIdentifier: String',
        'compiledProcedureIdentifier == Self.fieldProcedureIdentifier',
    ],
    entrypoint: [
        'var fieldProcedureIdentifier: String { buildIdentity.compiledProcedureIdentifier }',
        'procedureIdentifier: buildIdentity.compiledProcedureIdentifier',
    ],
    project: ['INFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";'],
    installer: [
        '"NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID"',
        'plutil -extract NembraCaptureProcedureIdentifier',
        '[[ "$BUILT_PROCEDURE_IDENTIFIER" == "$PROCEDURE_ID" ]]',
    ],
    workflow: [
        'NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="ES80-AUTHENTICATED-STATIONARY-v1"',
        'plutil -extract NembraCaptureProcedureIdentifier',
    ],
    procedure_test: ['procedureIdentifier: buildIdentity.compiledProcedureIdentifier'],
}
for path, needles in required.items():
    text = Path(path).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"{path}: missing {needle!r}")
