#!/usr/bin/env python3
from pathlib import Path

PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"


def replace_exact(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    found = text.count(old)
    if found != count:
        raise SystemExit(f"{path}: expected {count} occurrences, found {found}: {old!r}")
    p.write_text(text.replace(old, new, count))


# Make procedure identity a built-app provenance field and an authoritative-build requirement.
identity = "NembraApp/App/NembraCaptureBuildIdentity.swift"
replace_exact(
    identity,
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n    static let fieldProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"\n',
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n'
    '    static let procedureIdentifierInfoKey = "NembraCaptureProcedureIdentifier"\n'
    '    static let fieldProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"\n',
)
replace_exact(
    identity,
    '    let tuyaDependencyLockSHA256: String\n',
    '    let tuyaDependencyLockSHA256: String\n    let procedureIdentifier: String\n',
)
replace_exact(
    identity,
    '            sourceCommitSHA: ((infoDictionary[sourceCommitSHAInfoKey] as? String) ?? "").lowercased(),\n'
    '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased()\n',
    '            sourceCommitSHA: ((infoDictionary[sourceCommitSHAInfoKey] as? String) ?? "").lowercased(),\n'
    '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased(),\n'
    '            procedureIdentifier: (infoDictionary[procedureIdentifierInfoKey] as? String) ?? ""\n',
)
replace_exact(
    identity,
    '              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in\n'
    '                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n'
    '              }) else { return false }\n',
    '              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in\n'
    '                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n'
    '              }),\n'
    '              procedureIdentifier == Self.fieldProcedureIdentifier else { return false }\n',
)
replace_exact(
    identity,
    '            return "This build has no valid exact Git + reviewed Tuya dependency provenance. Install Capture through the repository field installer before physical evidence collection."\n',
    '            return "This build has no valid exact Git + reviewed Tuya dependency + field-procedure provenance. Install Capture through the repository field installer before physical evidence collection."\n',
)

# Generated Info.plist receives the procedure stamp in both Debug and Release.
project = "NembraCapture.xcodeproj/project.pbxproj"
replace_exact(
    project,
    '\t\t\t\tINFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\n',
    '\t\t\t\tINFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\n'
    '\t\t\t\tINFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";\n',
    count=2,
)

# Installer stamps and independently reads back exact procedure before installation.
installer = "scripts/field/install_one_time_capture.command"
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
    'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, accepted field procedure, and field product"\n'
    'unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_PROCEDURE_ID BUILT_BUNDLE_ID APP_INFO_PLIST\n',
)
replace_exact(
    installer,
    '    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, and standalone bundle identifier." \\\n',
    '    "The exact built device app was read back before installation and matched the requested source SHA, field-build identifier, Tuya dependency lock, accepted procedure identity, and standalone bundle identifier." \\\n',
)

# Strengthen existing procedure source contract without touching guided product UI.
test = "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldProcedureRendezvousSourceTests.swift"
replace_exact(
    test,
    '        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")\n'
    '        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")\n\n'
    '        #expect(identity.contains("fieldProcedureIdentifier"))\n',
    '        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")\n'
    '        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")\n'
    '        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")\n\n'
    '        #expect(identity.contains("procedureIdentifierInfoKey"))\n'
    '        #expect(identity.contains("procedureIdentifier == Self.fieldProcedureIdentifier"))\n'
    '        #expect(project.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier"))\n'
    '        #expect(identity.contains("fieldProcedureIdentifier"))\n',
)
replace_exact(
    test,
    '        #expect(installer.contains("PROCEDURE_ID=\\"\\(Self.procedure)\\""))\n'
    '        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))\n',
    '        #expect(installer.contains("PROCEDURE_ID=\\"\\(Self.procedure)\\""))\n'
    '        #expect(installer.contains("NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID"))\n'
    '        #expect(installer.contains("plutil -extract NembraCaptureProcedureIdentifier"))\n'
    '        #expect(installer.contains("BUILT_PROCEDURE_ID\\" == \\"$PROCEDURE_ID"))\n'
    '        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))\n',
)

for path, needle in {
    identity: 'procedureIdentifier == Self.fieldProcedureIdentifier',
    project: 'INFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";',
    installer: '[[ "$BUILT_PROCEDURE_ID" == "$PROCEDURE_ID" ]]',
    test: 'NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID',
}.items():
    if needle not in Path(path).read_text():
        raise SystemExit(f"{path}: missing {needle}")
