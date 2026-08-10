from pathlib import Path

PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"

def once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 anchor, found {count}")
    return text.replace(old, new, 1)

# Build identity: procedure must be a property of the built artifact, not only source prose.
p = Path("NembraApp/App/NembraCaptureBuildIdentity.swift")
s = p.read_text()
s = once(s,
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n    static let fieldProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"\n',
    '    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"\n    static let procedureIdentifierInfoKey = "NembraCaptureProcedureIdentifier"\n    static let fieldProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"\n',
    'identity info key')
s = once(s, '    let tuyaDependencyLockSHA256: String\n', '    let tuyaDependencyLockSHA256: String\n    let procedureIdentifier: String\n', 'identity stored procedure')
s = once(s,
    '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased()\n',
    '            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased(),\n            procedureIdentifier: (infoDictionary[procedureIdentifierInfoKey] as? String) ?? ""\n',
    'identity decode')
s = once(s,
    '              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in\n                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n              }) else { return false }\n',
    '              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in\n                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)\n              }),\n              procedureIdentifier == Self.fieldProcedureIdentifier else { return false }\n',
    'identity authority')
s = s.replace('exact Git + reviewed Tuya dependency provenance', 'exact Git + reviewed Tuya dependency + field-procedure provenance')
p.write_text(s)

# Generated Info.plist carries the exact procedure ID in both app configurations.
p = Path("NembraCapture.xcodeproj/project.pbxproj")
s = p.read_text()
anchor = '\t\t\t\tINFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256 = "$(NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256)";\n'
if s.count(anchor) != 2:
    raise SystemExit(f'project plist anchor count={s.count(anchor)}')
s = s.replace(anchor, anchor + f'\t\t\t\tINFOPLIST_KEY_NembraCaptureProcedureIdentifier = "{PROCEDURE}";\n')
p.write_text(s)

# Export/UI consume the built artifact identity, not a parallel source constant.
p = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = p.read_text()
s = once(s,
    '    var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }\n',
    '    var fieldProcedureIdentifier: String { buildIdentity.procedureIdentifier }\n',
    'controller built procedure getter')
s = once(s,
    '            procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier,\n',
    '            procedureIdentifier: buildIdentity.procedureIdentifier,\n',
    'export built procedure value')
p.write_text(s)

# Installer mechanically verifies the exact built .app procedure before installation.
p = Path("scripts/field/install_one_time_capture.command")
s = p.read_text()
s = once(s,
    'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\nBUILT_BUNDLE_ID=',
    'BUILT_TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\nBUILT_PROCEDURE_ID="$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier raw -o - "$APP_INFO_PLIST" 2>/dev/null || true)"\nBUILT_BUNDLE_ID=',
    'installer readback')
s = once(s,
    '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]]',
    '[[ "$BUILT_TUYA_DEPENDENCY_LOCK_SHA256" == "$TUYA_DEPENDENCY_LOCK_SHA256" ]] || die "Built Capture app Tuya dependency-lock fingerprint does not match the exact resolved private workspace. Discard this candidate."\n[[ "$BUILT_PROCEDURE_ID" == "$PROCEDURE_ID" ]] || die "Built Capture app procedure identity does not match the canonical stationary field procedure. Discard this candidate."\n[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]]',
    'installer compare')
s = once(s,
    'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, and field product"\nunset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_BUNDLE_ID APP_INFO_PLIST\n',
    'say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, canonical stationary procedure, and field product"\nunset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_PROCEDURE_ID BUILT_BUNDLE_ID APP_INFO_PLIST\n',
    'installer cleanup')
p.write_text(s)

# Add focused artifact-custody regression without replacing the existing cross-surface test.
p = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldProcedureArtifactCustodySourceTests.swift")
p.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure artifact custody")
struct TuyaFieldProcedureArtifactCustodySourceTests {
    private static let procedure = "ES80-AUTHENTICATED-STATIONARY-v1"

    @Test("authoritative build reads the procedure from its own Info plist and requires the canonical value")
    func compiledArtifactOwnsProcedureIdentity() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(identity.contains("static let procedureIdentifierInfoKey = \"NembraCaptureProcedureIdentifier\""))
        #expect(identity.contains("let procedureIdentifier: String"))
        #expect(identity.contains("procedureIdentifier == Self.fieldProcedureIdentifier"))
        #expect(project.components(separatedBy: "INFOPLIST_KEY_NembraCaptureProcedureIdentifier = \"\(Self.procedure)\";").count == 3)
        #expect(app.contains("var fieldProcedureIdentifier: String { buildIdentity.procedureIdentifier }"))
        #expect(app.contains("procedureIdentifier: buildIdentity.procedureIdentifier"))
    }

    @Test("installer reads back and rejects a different built app procedure before install")
    func installerVerifiesBuiltProcedure() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let readback = installer.range(of: "BUILT_PROCEDURE_ID=\"$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier")
        let compare = installer.range(of: "[[ \"$BUILT_PROCEDURE_ID\" == \"$PROCEDURE_ID\" ]]")
        let install = installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone\"")
        #expect(readback != nil)
        #expect(compare != nil)
        #expect(install != nil)
        if let readback, let compare, let install {
            #expect(readback.lowerBound < compare.lowerBound)
            #expect(compare.lowerBound < install.lowerBound)
        }
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
''')
