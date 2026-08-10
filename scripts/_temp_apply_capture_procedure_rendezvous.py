from pathlib import Path

PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)

# Build identity: the compiled app must carry the exact procedure identity.
path = Path("NembraApp/App/NembraCaptureBuildIdentity.swift")
text = path.read_text()
text = replace_once(
    text,
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n',
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n'
    '    static let procedureIdentifierInfoKey = "NembraCaptureProcedureIdentifier"\n'
    f'    static let fieldProcedureIdentifier = "{PROCEDURE}"\n',
    "build identity keys",
)
text = replace_once(
    text,
    '    let tuyaDependencyLockSHA256: String\n',
    '    let tuyaDependencyLockSHA256: String\n    let procedureIdentifier: String\n',
    "build identity stored procedure",
)
text = replace_once(
    text,
    '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased()\n',
    '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased(),\n'
    '            procedureIdentifier: (infoDictionary[procedureIdentifierInfoKey] as? String) ?? ""\n',
    "build identity decode",
)
text = replace_once(
    text,
    '              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in\n'
    '                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n'
    '              }) else { return false }\n\n'
    '        let expectedIdentifier = "capture-v14-\\(sourceCommitSHA.prefix(12))"\n'
    '        return buildIdentifier == expectedIdentifier\n',
    '              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in\n'
    '                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n'
    '              }),\n'
    '              procedureIdentifier == Self.fieldProcedureIdentifier else { return false }\n\n'
    '        let expectedIdentifier = "capture-v14-\\(sourceCommitSHA.prefix(12))"\n'
    '        return buildIdentifier == expectedIdentifier\n',
    "build identity authority",
)
text = text.replace(
    "This build has no valid exact Git + reviewed Tuya dependency provenance.",
    "This build has no valid exact Git + reviewed Tuya dependency + field-procedure provenance.",
)
path.write_text(text)

# Xcode-generated Info.plist carries the exact procedure ID in both configs.
path = Path("NembraCapture.xcodeproj/project.pbxproj")
text = path.read_text()
anchor = '\t\t\t\tINFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\n'
if text.count(anchor) != 2:
    raise SystemExit(f"project procedure plist anchor count={text.count(anchor)}")
text = text.replace(
    anchor,
    anchor + f'\t\t\t\tINFOPLIST_KEY_NembraCaptureProcedureIdentifier = "{PROCEDURE}";\n',
)
path.write_text(text)

# Entrypoint: Export schema 10 freezes procedure identity; UI exposes it.
path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = path.read_text()
text = replace_once(
    text,
    '        let tuyaDependencyLockSHA256: String\n        let tuyaDeviceID: String\n',
    '        let tuyaDependencyLockSHA256: String\n        let procedureIdentifier: String\n        let tuyaDeviceID: String\n',
    "export procedure field",
)
text = replace_once(
    text,
    '    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }\n',
    '    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }\n'
    '    var fieldProcedureIdentifier: String { buildIdentity.procedureIdentifier }\n',
    "controller procedure getter",
)
text = replace_once(text, '            schemaVersion: 9,\n', '            schemaVersion: 10,\n', "export schema")
text = replace_once(
    text,
    '            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n            tuyaDeviceID: deviceID,\n',
    '            tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256,\n'
    '            procedureIdentifier: buildIdentity.procedureIdentifier,\n'
    '            tuyaDeviceID: deviceID,\n',
    "export procedure value",
)
text = replace_once(
    text,
    '            LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n'
    '            LabeledContent("Private SDK config", value: test.privateConfig ? "Present" : "Missing")\n',
    '            LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n'
    '            LabeledContent("Procedure", value: test.fieldProcedureIdentifier)\n'
    '            LabeledContent("Private SDK config", value: test.privateConfig ? "Present" : "Missing")\n',
    "authority UI procedure",
)
path.write_text(text)

# Canonical procedure source is explicitly versioned.
path = Path("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
text = path.read_text()
text = replace_once(
    text,
    '# Nembra Capture P0 — secure-link gate\n\n',
    f'# Nembra Capture P0 — secure-link gate\n\nPROCEDURE_ID: `{PROCEDURE}`\n\n',
    "runbook procedure marker",
)
path.write_text(text)

# Installer owns the same procedure ID and refuses a built app with a different one.
path = Path("scripts/field/install_one_time_capture.command")
text = path.read_text()
text = replace_once(
    text,
    'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\nBUILD_LABEL="capture-v14-${SOURCE_SHA:0:12}"\n',
    f'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\nPROCEDURE_ID="{PROCEDURE}"\nBUILD_LABEL="capture-v14-${{SOURCE_SHA:0:12}}"\n',
    "installer procedure constant",
)
text = replace_once(
    text,
    'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n'
    'BUILT_BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n',
    'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n'
    'BUILT_PROCEDURE_ID="$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n'
    'BUILT_BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\n',
    "installer procedure readback",
)
text = replace_once(
    text,
    '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n'
    '[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]] || die "Built Capture app bundle identifier does not match the intended standalone field product. Discard this candidate."\n'
    'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, and field product"\n'
    'unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_BUNDLE_ID APP_INFO_PLIST\n',
    '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n'
    '[[ "$BUILT_PROCEDURE_ID" == "$PROCEDURE_ID" ]] || die "Built Capture app procedure identity does not match the canonical stationary field procedure. Discard this candidate."\n'
    '[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]] || die "Built Capture app bundle identifier does not match the intended standalone field product. Discard this candidate."\n'
    'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, canonical stationary procedure, and field product"\n'
    'unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_PROCEDURE_ID BUILT_BUNDLE_ID APP_INFO_PLIST\n',
    "installer procedure verify",
)
text = replace_once(
    text,
    '    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, and standalone bundle identifier." \\\n',
    '    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, canonical procedure identity, and standalone bundle identifier." \\\n'
    '    "Field procedure: $PROCEDURE_ID. The same identifier is compiled into the immutable accepted export." \\\n',
    "installer operator procedure output",
)
path.write_text(text)

# Field provenance workflow: bind checkout to immutable event subject and pin procedure surfaces.
path = Path(".github/workflows/capture-field-build-provenance.yml")
text = path.read_text()
text = replace_once(
    text,
    '      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateFieldInputProvenanceSourceTests.swift\n',
    '      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateFieldInputProvenanceSourceTests.swift\n'
    '      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldProcedureRendezvousSourceTests.swift\n'
    '      - docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md\n',
    "workflow trigger paths",
)
text = replace_once(
    text,
    '    steps:\n      - uses: actions/checkout@v4\n\n',
    '''    steps:\n      - name: Checkout immutable PR head\n        if: github.event_name == 'pull_request'\n        uses: actions/checkout@v6\n        with:\n          ref: ${{ github.event.pull_request.head.sha }}\n\n      - name: Checkout immutable non-PR subject\n        if: github.event_name != 'pull_request'\n        uses: actions/checkout@v6\n        with:\n          ref: ${{ github.sha }}\n\n      - name: Verify immutable source subject\n        shell: bash\n        env:\n          EXPECTED_WORKFLOW_SHA: ${{ github.event_name == 'pull_request' && github.event.pull_request.head.sha || github.sha }}\n        run: |\n          set -euo pipefail\n          actual="$(git rev-parse HEAD)"\n          [[ "$EXPECTED_WORKFLOW_SHA" =~ ^[0-9a-f]{40}$ ]]\n          test "$actual" = "$EXPECTED_WORKFLOW_SHA"\n\n''',
    "workflow exact-head checkout",
)
text = replace_once(
    text,
    "          private_provenance='Scripts/capture_tuya_private_input_provenance.py'\n",
    "          private_provenance='Scripts/capture_tuya_private_input_provenance.py'\n          runbook='docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md'\n",
    "workflow runbook var",
)
text = replace_once(
    text,
    "          grep -Fq 'let tuyaDependencyLockSHA256: String' \"$entrypoint\"\n"
    "          grep -Fq 'tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256' \"$entrypoint\"\n",
    "          grep -Fq 'let tuyaDependencyLockSHA256: String' \"$entrypoint\"\n"
    f"          grep -Fq 'static let fieldProcedureIdentifier = \"{PROCEDURE}\"' \"$identity\"\n"
    "          grep -Fq 'static let procedureIdentifierInfoKey = \"NembraCaptureProcedureIdentifier\"' \"$identity\"\n"
    "          grep -Fq 'procedureIdentifier == Self.fieldProcedureIdentifier' \"$identity\"\n"
    "          grep -Fq 'let procedureIdentifier: String' \"$entrypoint\"\n"
    "          grep -Fq 'procedureIdentifier: buildIdentity.procedureIdentifier' \"$entrypoint\"\n"
    "          grep -Fq 'LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)' \"$entrypoint\"\n"
    f"          grep -Fq 'PROCEDURE_ID: `{PROCEDURE}`' \"$runbook\"\n"
    f"          grep -Fq 'PROCEDURE_ID=\"{PROCEDURE}\"' \"$installer\"\n"
    "          grep -Fq 'plutil -extract NembraCaptureProcedureIdentifier raw -o - \"$APP_INFO_PLIST\"' \"$installer\"\n"
    "          grep -Fq '[[ \"$BUILT_PROCEDURE_ID\" == \"$PROCEDURE_ID\" ]]' \"$installer\"\n"
    "          grep -Fq 'tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256' \"$entrypoint\"\n",
    "workflow source procedure checks",
)
text = replace_once(
    text,
    '          grep -Fq \'INFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\' "$project"\n',
    '          grep -Fq \'INFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\' "$project"\n'
    f'          grep -Fq \'INFOPLIST_KEY_NembraCaptureProcedureIdentifier = "{PROCEDURE}";\' "$project"\n',
    "workflow project procedure check",
)
text = replace_once(
    text,
    '          test "$(plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$plist")" = "$dependency_sha"\n',
    '          test "$(plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$plist")" = "$dependency_sha"\n'
    f'          test "$(plutil -extract NembraCaptureProcedureIdentifier raw -o - "$plist")" = "{PROCEDURE}"\n',
    "workflow built procedure readback",
)
path.write_text(text)

# Portable source-level rendezvous regression.
test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldProcedureRendezvousSourceTests.swift")
test_path.write_text(f'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure rendezvous")
struct TuyaFieldProcedureRendezvousSourceTests {{
    private static let procedure = "{PROCEDURE}"

    @Test("one exact stationary procedure is bound across compiled app, export, installer, runbook, and field gate")
    func exactProcedureRendezvous() throws {{
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")

        #expect(identity.contains("static let fieldProcedureIdentifier = \\\"\\(Self.procedure)\\\""))
        #expect(identity.contains("procedureIdentifier == Self.fieldProcedureIdentifier"))
        #expect(project.components(separatedBy: "INFOPLIST_KEY_NembraCaptureProcedureIdentifier = \\\"\\(Self.procedure)\\\";").count == 3)
        #expect(app.contains("let procedureIdentifier: String"))
        #expect(app.contains("procedureIdentifier: buildIdentity.procedureIdentifier"))
        #expect(app.contains("LabeledContent(\\\"Procedure\\\", value: test.fieldProcedureIdentifier)"))
        #expect(installer.contains("PROCEDURE_ID=\\\"\\(Self.procedure)\\\""))
        #expect(installer.contains("BUILT_PROCEDURE_ID"))
        #expect(installer.contains("[[ \\\"$BUILT_PROCEDURE_ID\\\" == \\\"$PROCEDURE_ID\\\" ]]"))
        #expect(runbook.contains("PROCEDURE_ID: `\\(Self.procedure)`"))
        #expect(workflow.contains("TuyaFieldProcedureRendezvousSourceTests.swift"))
        #expect(workflow.contains("github.event.pull_request.head.sha"))
    }}

    @Test("adding procedure identity advances the sanitized export schema")
    func procedureIdentityIsSchemaTen() throws {{
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("schemaVersion: 10"))
        #expect(!app.contains("schemaVersion: 9,"))
    }}

    private func readRepositoryFile(_ relativePath: String) throws -> String {{
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }}
}}
''')
