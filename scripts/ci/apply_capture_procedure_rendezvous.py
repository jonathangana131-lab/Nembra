#!/usr/bin/env python3
from pathlib import Path

PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"


def replace_exact(path: str, old: str, new: str, expected_count: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != expected_count:
        raise SystemExit(f"{path}: expected {expected_count} anchors, found {count}: {old!r}")
    p.write_text(text.replace(old, new, expected_count))


def insert_once(path: str, anchor: str, insertion: str) -> None:
    p = Path(path)
    text = p.read_text()
    if insertion in text:
        return
    if text.count(anchor) != 1:
        raise SystemExit(f"{path}: anchor count {text.count(anchor)} for {anchor!r}")
    p.write_text(text.replace(anchor, anchor + insertion, 1))


# Build identity: procedure is a stamped build property, not an operator-memory string.
replace_exact(
    "NembraApp/App/NembraCaptureBuildIdentity.swift",
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n',
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n'
    '    static let procedureIdentifierInfoKey = "NembraCaptureProcedureIdentifier"\n'
    f'    static let canonicalProcedureIdentifier = "{PROCEDURE}"\n',
)
replace_exact(
    "NembraApp/App/NembraCaptureBuildIdentity.swift",
    '    let tuyaDependencyLockSHA256: String\n',
    '    let tuyaDependencyLockSHA256: String\n    let procedureIdentifier: String\n',
)
replace_exact(
    "NembraApp/App/NembraCaptureBuildIdentity.swift",
    '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased()\n',
    '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased(),\n'
    '            procedureIdentifier: (infoDictionary[procedureIdentifierInfoKey] as? String) ?? ""\n',
)
replace_exact(
    "NembraApp/App/NembraCaptureBuildIdentity.swift",
    '              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in\n'
    '                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n'
    '              }) else { return false }\n',
    '              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in\n'
    '                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n'
    '              }),\n'
    '              procedureIdentifier == Self.canonicalProcedureIdentifier else { return false }\n',
)
replace_exact(
    "NembraApp/App/NembraCaptureBuildIdentity.swift",
    '            return "This build has no valid exact Git + reviewed Tuya dependency provenance. Install Capture through the repository field installer before physical evidence collection."\n',
    '            return "This build has no valid exact Git + reviewed Tuya dependency + field-procedure provenance. Install Capture through the repository field installer before physical evidence collection."\n',
)

# Standalone target Info.plist generation: stamp the canonical procedure in both configurations.
replace_exact(
    "NembraCapture.xcodeproj/project.pbxproj",
    '\t\t\t\tINFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\n',
    '\t\t\t\tINFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\n'
    '\t\t\t\tINFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";\n',
    expected_count=2,
)

# Accepted Export + UI: freeze and display exactly what the built app was stamped with.
replace_exact(
    "NembraApp/App/NembraCaptureEntrypoint.swift",
    '        let tuyaDependencyLockSHA256: String\n        let tuyaDeviceID: String\n',
    '        let tuyaDependencyLockSHA256: String\n        let procedureIdentifier: String\n        let tuyaDeviceID: String\n',
)
replace_exact(
    "NembraApp/App/NembraCaptureEntrypoint.swift",
    '    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }\n    var sdkAccountLoggedIn: Bool',
    '    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }\n'
    '    var fieldProcedureIdentifier: String { buildIdentity.procedureIdentifier }\n'
    '    var sdkAccountLoggedIn: Bool',
)
replace_exact(
    "NembraApp/App/NembraCaptureEntrypoint.swift",
    '            schemaVersion: 9,\n',
    '            schemaVersion: 10,\n',
)
replace_exact(
    "NembraApp/App/NembraCaptureEntrypoint.swift",
    '            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n            tuyaDeviceID: deviceID,\n',
    '            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n'
    '            procedureIdentifier: buildIdentity.procedureIdentifier,\n'
    '            tuyaDeviceID: deviceID,\n',
)
replace_exact(
    "NembraApp/App/NembraCaptureEntrypoint.swift",
    '            LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n            LabeledContent("Private SDK config", value: test.privateConfig ? "Present" : "Missing")\n',
    '            LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n'
    '            LabeledContent("Procedure", value: test.fieldProcedureIdentifier)\n'
    '            LabeledContent("Private SDK config", value: test.privateConfig ? "Present" : "Missing")\n',
)

# Canonical runbook marker.
runbook = Path("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
runbook_text = runbook.read_text()
marker = f"PROCEDURE_ID: `{PROCEDURE}`\n"
if marker not in runbook_text:
    title = "# Nembra Capture P0 — secure-link gate\n"
    if runbook_text.count(title) != 1:
        raise SystemExit("runbook title anchor changed")
    runbook.write_text(runbook_text.replace(title, title + "\n" + marker, 1))

# Field installer: stamp procedure, read it back from the built app, and refuse install on mismatch.
installer = "scripts/field/install_one_time_capture.command"
replace_exact(
    installer,
    'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\nBUILD_LABEL="capture-v14-${SOURCE_SHA:0:12}"\n',
    f'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\nPROCEDURE_ID="{PROCEDURE}"\nBUILD_LABEL="capture-v14-${{SOURCE_SHA:0:12}}"\n',
)
replace_exact(
    installer,
    '    "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \\\n    build\n',
    '    "NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256" \\\n'
    '    "NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID" \\\n'
    '    build\n',
)
replace_exact(
    installer,
    'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n'
    'BUILT_BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n',
    'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n'
    'BUILT_PROCEDURE_ID="$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n'
    'BUILT_BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n',
)
replace_exact(
    installer,
    '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n'
    '[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]] || die "Built Capture app bundle identifier does not match the intended standalone field product. Discard this candidate."\n'
    'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, and field product"\n'
    'unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_BUNDLE_ID APP_INFO_PLIST\n',
    '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n'
    '[[ "$BUILT_PROCEDURE_ID" == "$PROCEDURE_ID" ]] || die "Built Capture app procedure identity does not match the accepted stationary field procedure. Discard this candidate."\n'
    '[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]] || die "Built Capture app bundle identifier does not match the intended standalone field product. Discard this candidate."\n'
    'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, field procedure, and field product"\n'
    'unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_PROCEDURE_ID BUILT_BUNDLE_ID APP_INFO_PLIST\n',
)
replace_exact(
    installer,
    '    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, and standalone bundle identifier." \\\n',
    '    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, Tuya dependency lock, accepted procedure identity, and standalone bundle identifier." \\\n'
    '    "Field procedure: $PROCEDURE_ID. The same stamped identifier is visible in Capture and frozen into accepted export evidence." \\\n',
)

# Source-level adversarial contract across all authority surfaces.
test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldProcedureRendezvousSourceTests.swift")
test_path.write_text(f'''import Foundation\nimport Testing\n@testable import NembraBluetoothCapture\n\n@Suite("Capture field procedure rendezvous")\nstruct TuyaFieldProcedureRendezvousSourceTests {{\n    private static let procedure = "{PROCEDURE}"\n\n    @Test("built app, UI, immutable export, runbook, and installer share one exact procedure")\n    func oneProcedureAcrossFieldAuthoritySurfaces() throws {{\n        let identity = try read("NembraApp/App/NembraCaptureBuildIdentity.swift")\n        let project = try read("NembraCapture.xcodeproj/project.pbxproj")\n        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")\n        let runbook = try read("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")\n        let installer = try read("scripts/field/install_one_time_capture.command")\n\n        #expect(identity.contains("static let canonicalProcedureIdentifier = \\\"\\(Self.procedure)\\\""))\n        #expect(identity.contains("procedureIdentifier == Self.canonicalProcedureIdentifier"))\n        #expect(project.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier"))\n        #expect(app.contains("let procedureIdentifier: String"))\n        #expect(app.contains("procedureIdentifier: buildIdentity.procedureIdentifier"))\n        #expect(app.contains("LabeledContent(\\\"Procedure\\\", value: test.fieldProcedureIdentifier)"))\n        #expect(runbook.contains("PROCEDURE_ID: `\\(Self.procedure)`"))\n        #expect(installer.contains("PROCEDURE_ID=\\\"\\(Self.procedure)\\\""))\n        #expect(installer.contains("NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID"))\n        #expect(installer.contains("plutil -extract NembraCaptureProcedureIdentifier"))\n        #expect(installer.contains("BUILT_PROCEDURE_ID\\\" == \\\"$PROCEDURE_ID"))\n    }}\n\n    @Test("procedure-bearing accepted export advances beyond dependency-lock schema")\n    func exportSchemaAdvances() throws {{\n        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")\n        #expect(app.contains("schemaVersion: 10"))\n        #expect(!app.contains("schemaVersion: 9"))\n    }}\n\n    private func read(_ path: String) throws -> String {{\n        let root = URL(fileURLWithPath: #filePath)\n            .deletingLastPathComponent()\n            .deletingLastPathComponent()\n            .deletingLastPathComponent()\n            .deletingLastPathComponent()\n            .deletingLastPathComponent()\n        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)\n    }}\n}}\n''')

# Field provenance gate must exercise and read back the procedure stamp too.
workflow = ".github/workflows/capture-field-build-provenance.yml"
insert_once(
    workflow,
    '      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerIntendedDeviceAuthoritySourceTests.swift\n',
    '      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldProcedureRendezvousSourceTests.swift\n',
)
insert_once(
    workflow,
    '          grep -Fq \'NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256\' "$installer"\n',
    f'          grep -Fq \'PROCEDURE_ID="{PROCEDURE}"\' "$installer"\n'
    '          grep -Fq \'NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID\' "$installer"\n',
)
insert_once(
    workflow,
    '          grep -Fq \'plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST"\' "$installer"\n',
    '          grep -Fq \'plutil -extract NembraCaptureProcedureIdentifier raw -o - "$APP_INFO_PLIST"\' "$installer"\n',
)
insert_once(
    workflow,
    '          grep -Fq \'[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]]\' "$installer"\n',
    '          grep -Fq \'[[ "$BUILT_PROCEDURE_ID" == "$PROCEDURE_ID" ]]\' "$installer"\n',
)
insert_once(
    workflow,
    '          grep -Fq \'INFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\' "$project"\n',
    '          grep -Fq \'INFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";\' "$project"\n',
)
insert_once(
    workflow,
    '          grep -Fq \'static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\' "$identity"\n',
    '          grep -Fq \'static let procedureIdentifierInfoKey = "NembraCaptureProcedureIdentifier"\' "$identity"\n'
    f'          grep -Fq \'static let canonicalProcedureIdentifier = "{PROCEDURE}"\' "$identity"\n'
    '          grep -Fq \'procedureIdentifier == Self.canonicalProcedureIdentifier\' "$identity"\n',
)
insert_once(
    workflow,
    '          dependency_sha=\'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789\'\n',
    f'          procedure_id=\'{PROCEDURE}\'\n',
)
insert_once(
    workflow,
    '            NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256="$dependency_sha" \\\n',
    '            NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="$procedure_id" \\\n',
)
insert_once(
    workflow,
    '          test "$(plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$plist")" = "$dependency_sha"\n',
    '          test "$(plutil -extract NembraCaptureProcedureIdentifier raw -o - "$plist")" = "$procedure_id"\n',
)

# Mechanical post-patch sanity before the workflow is allowed to commit.
required = {
    "NembraApp/App/NembraCaptureBuildIdentity.swift": [PROCEDURE, "procedureIdentifier == Self.canonicalProcedureIdentifier"],
    "NembraCapture.xcodeproj/project.pbxproj": ["NembraCaptureProcedureIdentifier"],
    "NembraApp/App/NembraCaptureEntrypoint.swift": ["schemaVersion: 10", "procedureIdentifier: buildIdentity.procedureIdentifier"],
    "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md": [f"PROCEDURE_ID: `{PROCEDURE}`"],
    "scripts/field/install_one_time_capture.command": [f'PROCEDURE_ID="{PROCEDURE}"', "BUILT_PROCEDURE_ID"],
    ".github/workflows/capture-field-build-provenance.yml": ["NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER", "NembraCaptureProcedureIdentifier"],
}
for path, needles in required.items():
    text = Path(path).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"{path}: missing required rendezvous marker {needle!r}")
