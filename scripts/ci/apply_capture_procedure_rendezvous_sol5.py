#!/usr/bin/env python3
from pathlib import Path
import textwrap

PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    source = p.read_text()
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one anchor, found {count}: {old!r}")
    p.write_text(source.replace(old, new, 1))


def replace_count(path: str, old: str, new: str, expected: int) -> None:
    p = Path(path)
    source = p.read_text()
    count = source.count(old)
    if count != expected:
        raise SystemExit(f"{path}: expected {expected} anchors, found {count}: {old!r}")
    p.write_text(source.replace(old, new))


identity = "NembraApp/App/NembraCaptureBuildIdentity.swift"
replace_once(
    identity,
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n',
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n'
    '    static let fieldProcedureIdentifierInfoKey = "NembraCaptureFieldProcedureIdentifier"\n'
    f'    static let fieldProcedureIdentifier = "{PROCEDURE}"\n',
)
replace_once(
    identity,
    '    let tuyaDependencyLockSHA256: String\n',
    '    let tuyaDependencyLockSHA256: String\n'
    '    let embeddedFieldProcedureIdentifier: String\n',
)
replace_once(
    identity,
    '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased()\n',
    '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased(),\n'
    '            embeddedFieldProcedureIdentifier: ((infoDictionary[fieldProcedureIdentifierInfoKey] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)\n',
)
replace_once(
    identity,
    '              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in\n'
    '                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n'
    '              }) else { return false }\n',
    '              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in\n'
    '                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n'
    '              }),\n'
    '              embeddedFieldProcedureIdentifier == Self.fieldProcedureIdentifier else { return false }\n',
)
replace_once(
    identity,
    '            return "This build has no valid exact Git + reviewed Tuya dependency provenance. Install Capture through the repository field installer before physical evidence collection."\n',
    '            return "This build has no valid exact Git + reviewed Tuya dependency + field-procedure provenance. Install Capture through the repository field installer before physical evidence collection."\n',
)

entrypoint = "NembraApp/App/NembraCaptureEntrypoint.swift"
replace_once(
    entrypoint,
    '        let tuyaDependencyLockSHA256: String\n        let tuyaDeviceID: String\n',
    '        let tuyaDependencyLockSHA256: String\n        let procedureIdentifier: String\n        let tuyaDeviceID: String\n',
)
replace_once(entrypoint, '            schemaVersion: 9,\n', '            schemaVersion: 10,\n')
replace_once(
    entrypoint,
    '            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n            tuyaDeviceID: deviceID,\n',
    '            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n'
    '            procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier,\n'
    '            tuyaDeviceID: deviceID,\n',
)
replace_once(
    entrypoint,
    '    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }\n',
    '    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }\n'
    '    var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }\n',
)
replace_once(
    entrypoint,
    '            LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n',
    '            LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n'
    '            LabeledContent("Procedure", value: test.fieldProcedureIdentifier)\n',
)
replace_once(
    entrypoint,
    '            message = "Sanitized diagnostics ready with exact compiled source + reviewed Tuya dependency-lock provenance. No account UID, AppKey/AppSecret, password, account token, local_key, session key, raw FD50 claim, DP query, or DP command is exported."\n',
    '            message = "Sanitized diagnostics ready with exact compiled source + reviewed Tuya dependency-lock + field-procedure provenance. No account UID, AppKey/AppSecret, password, account token, local_key, session key, raw FD50 claim, DP query, or DP command is exported."\n',
)

project = "NembraCapture.xcodeproj/project.pbxproj"
replace_count(
    project,
    '\t\t\t\tINFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\n',
    '\t\t\t\tINFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\n'
    '\t\t\t\tINFOPLIST_KEY_NembraCaptureFieldProcedureIdentifier = "$(NEMBRA_CAPTURE_FIELD_PROCEDURE_IDENTIFIER)";\n',
    2,
)

runbook = "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"
replace_once(
    runbook,
    '# Nembra Capture P0 — secure-link gate\n\n',
    f'# Nembra Capture P0 — secure-link gate\n\nPROCEDURE_ID: `{PROCEDURE}`\n\n',
)

installer = "scripts/field/install_one_time_capture.command"
replace_once(
    installer,
    'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\nBUILD_LABEL="capture-v14-${SOURCE_SHA:0:12}"\n',
    f'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\nPROCEDURE_ID="{PROCEDURE}"\nBUILD_LABEL="capture-v14-${{SOURCE_SHA:0:12}}"\n',
)
replace_once(
    installer,
    '    "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \\\n    build\n',
    '    "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \\\n'
    '    "NEMBRA_CAPTURE_FIELD_PROCEDURE_IDENTIFIER=$PROCEDURE_ID" \\\n'
    '    build\n',
)
replace_once(
    installer,
    'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\nBUILT_BUNDLE_ID=',
    'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n'
    'BUILT_FIELD_PROCEDURE_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureFieldProcedureIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n'
    'BUILT_BUNDLE_ID=',
)
replace_once(
    installer,
    '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]]',
    '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n'
    '[[ "$BUILT_FIELD_PROCEDURE_IDENTIFIER" == "$PROCEDURE_ID" ]] || die "Built Capture app field-procedure identifier does not match the accepted stationary procedure. Discard this candidate."\n'
    '[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]]',
)
replace_once(
    installer,
    'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, and field product"\nunset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_BUNDLE_ID APP_INFO_PLIST\n',
    'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, field procedure, and field product"\n'
    'unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_FIELD_PROCEDURE_IDENTIFIER BUILT_BUNDLE_ID APP_INFO_PLIST\n',
)
replace_once(
    installer,
    '    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, and standalone bundle identifier." \\\n',
    '    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, reviewed dependency lock, accepted field procedure, and standalone bundle identifier." \\\n'
    '    "Field procedure: $PROCEDURE_ID. The same exact identifier is compiled into the app and immutable accepted export." \\\n',
)

provenance = ".github/workflows/capture-field-build-provenance.yml"
replace_once(
    provenance,
    '      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerIntendedDeviceAuthoritySourceTests.swift\n',
    '      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerIntendedDeviceAuthoritySourceTests.swift\n'
    '      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldProcedureRendezvousSourceTests.swift\n'
    '      - docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md\n',
)
replace_once(
    provenance,
    '          grep -Fq \'NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256\' "$installer"\n',
    '          grep -Fq \'NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256\' "$installer"\n'
    f'          grep -Fq \'PROCEDURE_ID="{PROCEDURE}"\' "$installer"\n'
    '          grep -Fq \'NEMBRA_CAPTURE_FIELD_PROCEDURE_IDENTIFIER=$PROCEDURE_ID\' "$installer"\n',
)
replace_once(
    provenance,
    '          grep -Fq \'plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST"\' "$installer"\n',
    '          grep -Fq \'plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST"\' "$installer"\n'
    '          grep -Fq \'plutil -extract NembraCaptureFieldProcedureIdentifier raw -o - "$APP_INFO_PLIST"\' "$installer"\n',
)
replace_once(
    provenance,
    '          grep -Fq \'[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]]\' "$installer"\n',
    '          grep -Fq \'[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]]\' "$installer"\n'
    '          grep -Fq \'[[ "$BUILT_FIELD_PROCEDURE_IDENTIFIER" == "$PROCEDURE_ID" ]]\' "$installer"\n',
)
replace_once(
    provenance,
    '          grep -Fq \'INFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\' "$project"\n',
    '          grep -Fq \'INFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\' "$project"\n'
    '          grep -Fq \'INFOPLIST_KEY_NembraCaptureFieldProcedureIdentifier = "$(NEMBRA_CAPTURE_FIELD_PROCEDURE_IDENTIFIER)";\' "$project"\n',
)
replace_once(
    provenance,
    '          grep -Fq \'static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\' "$identity"\n',
    '          grep -Fq \'static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\' "$identity"\n'
    '          grep -Fq \'static let fieldProcedureIdentifierInfoKey = "NembraCaptureFieldProcedureIdentifier"\' "$identity"\n'
    f'          grep -Fq \'static let fieldProcedureIdentifier = "{PROCEDURE}"\' "$identity"\n',
)
replace_once(
    provenance,
    '          grep -Fq \'tuyaDependencyLockSHA256.count == 64\' "$identity"\n',
    '          grep -Fq \'tuyaDependencyLockSHA256.count == 64\' "$identity"\n'
    '          grep -Fq \'embeddedFieldProcedureIdentifier == Self.fieldProcedureIdentifier\' "$identity"\n',
)
replace_once(
    provenance,
    '          grep -Fq \'let tuyaDependencyLockSHA256: String\' "$entrypoint"\n',
    '          grep -Fq \'let tuyaDependencyLockSHA256: String\' "$entrypoint"\n'
    '          grep -Fq \'let procedureIdentifier: String\' "$entrypoint"\n'
    '          grep -Fq \'procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier\' "$entrypoint"\n'
    '          grep -Fq \'LabeledContent("Procedure"\' "$entrypoint"\n'
    '          grep -Fq \'schemaVersion: 10\' "$entrypoint"\n',
)
replace_once(
    provenance,
    "          dependency_sha='abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789'\n          label='capture-v14-0123456789ab'\n",
    "          dependency_sha='abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789'\n"
    f"          procedure_id='{PROCEDURE}'\n"
    "          label='capture-v14-0123456789ab'\n",
)
replace_once(
    provenance,
    '            NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256="$dependency_sha" \\\n            build\n',
    '            NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256="$dependency_sha" \\\n'
    '            NEMBRA_CAPTURE_FIELD_PROCEDURE_IDENTIFIER="$procedure_id" \\\n'
    '            build\n',
)
replace_once(
    provenance,
    '          test "$(plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$plist")" = "$dependency_sha"\n',
    '          test "$(plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$plist")" = "$dependency_sha"\n'
    '          test "$(plutil -extract NembraCaptureFieldProcedureIdentifier raw -o - "$plist")" = "$procedure_id"\n',
)

test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldProcedureRendezvousSourceTests.swift")
if test_path.exists():
    raise SystemExit(f"{test_path}: already exists; refusing to overwrite")
test_path.write_text(textwrap.dedent(f'''\
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure rendezvous")
struct TuyaFieldProcedureRendezvousSourceTests {{
    private static let procedure = "{PROCEDURE}"

    @Test("compiled app identity and immutable accepted export record one exact procedure")
    func appAndAcceptedArtifactShareCanonicalProcedure() throws {{
        let identity = try read("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(identity.contains("fieldProcedureIdentifier"))
        #expect(identity.contains(Self.procedure))
        #expect(app.contains("let procedureIdentifier: String"))
        #expect(app.contains("procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier"))
        #expect(app.contains("LabeledContent(\\\"Procedure\\\""))
        #expect(app.contains("schemaVersion: 10"))
    }}

    @Test("canonical runbook and field installer pin the same exact procedure")
    func fieldSurfacesShareCanonicalProcedure() throws {{
        let project = try read("NembraCapture.xcodeproj/project.pbxproj")
        let installer = try read("scripts/field/install_one_time_capture.command")
        let runbook = try read("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        #expect(project.contains("INFOPLIST_KEY_NembraCaptureFieldProcedureIdentifier"))
        #expect(runbook.contains("PROCEDURE_ID: `\\(Self.procedure)`"))
        #expect(installer.contains("PROCEDURE_ID=\\\"\\(Self.procedure)\\\""))
        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))
    }}

    @Test("procedure identity participates in authoritative field-build admission")
    func authoritativeBuildRequiresProcedureRendezvous() throws {{
        let identity = try read("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let installer = try read("scripts/field/install_one_time_capture.command")
        #expect(identity.contains("embeddedFieldProcedureIdentifier == Self.fieldProcedureIdentifier"))
        #expect(installer.contains("[[ \\\"$BUILT_FIELD_PROCEDURE_IDENTIFIER\\\" == \\\"$PROCEDURE_ID\\\" ]]"))
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
'''))

print("capture procedure rendezvous materialized")
