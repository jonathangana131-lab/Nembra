#!/usr/bin/env python3
from pathlib import Path

INSTALLER = Path("scripts/field/install_one_time_capture.command")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSignedAppleAppIdentityCustodySourceTests.swift")

text = INSTALLER.read_text(encoding="utf-8")

def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    text = text.replace(old, new, 1)

replace_once(
    'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\nEXPECTED_APPLICATION_IDENTIFIER="${TEAM_ID}.${BUNDLE_ID}"\nPROCEDURE_ID="ES80-AUTHENTICATED-STATIONARY-v1"\n',
    'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\nAPP_ID_SUFFIX=".${BUNDLE_ID}"\nPROCEDURE_ID="ES80-AUTHENTICATED-STATIONARY-v1"\n',
    "derived Team ID App ID assumption",
)

replace_once(
    '''BUILT_APPLICATION_IDENTIFIER="${BUILT_SIGNING_IDENTITY%%$'\\t'*}"
BUILT_TEAM_IDENTIFIER="${BUILT_SIGNING_IDENTITY#*$'\\t'}"
[[ "$BUILT_APPLICATION_IDENTIFIER" == "$EXPECTED_APPLICATION_IDENTIFIER" ]] || \\
    die "Final signed Capture app application-identifier does not match the selected team and Capture bundle identifier. Discard this candidate."
[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\
    die "Final signed Capture app team identifier does not match the selected Apple Development team. Discard this candidate."
''',
    '''BUILT_APPLICATION_IDENTIFIER="${BUILT_SIGNING_IDENTITY%%$'\\t'*}"
BUILT_TEAM_IDENTIFIER="${BUILT_SIGNING_IDENTITY#*$'\\t'}"
[[ "$BUILT_APPLICATION_IDENTIFIER" == *"$APP_ID_SUFFIX" ]] || \\
    die "Final signed Capture app application-identifier does not end in the exact Capture bundle identifier. Discard this candidate."
[[ "$BUILT_APPLICATION_IDENTIFIER" != *"*"* ]] || \\
    die "Final signed Capture app application-identifier is wildcard/ambiguous. Discard this candidate."
BUILT_APP_ID_PREFIX="${BUILT_APPLICATION_IDENTIFIER%$APP_ID_SUFFIX}"
[[ -n "$BUILT_APP_ID_PREFIX" && "$BUILT_APP_ID_PREFIX" != "$BUILT_APPLICATION_IDENTIFIER" ]] || \\
    die "Final signed Capture app application-identifier is missing a concrete App ID prefix. Discard this candidate."
[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\
    die "Final signed Capture app team identifier does not match the selected Apple Development team. Discard this candidate."
''',
    "signed application identity checks",
)

replace_once(
    '''if (apple == ["Default"] and isinstance(application, str) and isinstance(entitlement_team, str)
        and isinstance(team_identifiers, list) and len(team_identifiers) == 1
        and team_identifiers[0] == entitlement_team):
    sys.stdout.write(application + "\\t" + entitlement_team)
''',
    '''if (apple == ["Default"] and isinstance(application, str) and isinstance(entitlement_team, str)
        and isinstance(team_identifiers, list) and len(team_identifiers) == 1
        and isinstance(team_identifiers[0], str)):
    sys.stdout.write(application + "\\t" + entitlement_team + "\\t" + team_identifiers[0])
''',
    "profile identity parser",
)

replace_once(
    '''[[ "$PROFILE_SIGNING_IDENTITY" == *$'\\t'* ]] || \\
    die "Embedded provisioning profile is missing required Sign in with Apple or exact application/team identity custody. Discard this candidate."
PROFILE_APPLICATION_IDENTIFIER="${PROFILE_SIGNING_IDENTITY%%$'\\t'*}"
PROFILE_TEAM_IDENTIFIER="${PROFILE_SIGNING_IDENTITY#*$'\\t'}"
[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$EXPECTED_APPLICATION_IDENTIFIER" ]] || \\
    die "Embedded provisioning profile application identifier does not match the selected team and Capture bundle identifier. Discard this candidate."
[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\
    die "Embedded provisioning profile team identity does not match the selected Apple Development team. Discard this candidate."
say "Final signed app and embedded provisioning profile authorize Sign in with Apple for the exact selected App ID and team"
unset SIGNED_ENTITLEMENTS_OUTPUT BUILT_SIGNING_IDENTITY BUILT_APPLICATION_IDENTIFIER BUILT_TEAM_IDENTIFIER PROFILE_PLIST_XML PROFILE_SIGNING_IDENTITY PROFILE_APPLICATION_IDENTIFIER PROFILE_TEAM_IDENTIFIER BUILT_PROFILE
''',
    '''[[ "$PROFILE_SIGNING_IDENTITY" == *$'\\t'*$'\\t'* ]] || \\
    die "Embedded provisioning profile is missing required Sign in with Apple or exact application/team identity custody. Discard this candidate."
PROFILE_APPLICATION_IDENTIFIER="${PROFILE_SIGNING_IDENTITY%%$'\\t'*}"
PROFILE_TEAM_FIELDS="${PROFILE_SIGNING_IDENTITY#*$'\\t'}"
PROFILE_TEAM_IDENTIFIER="${PROFILE_TEAM_FIELDS%%$'\\t'*}"
PROFILE_ROOT_TEAM_IDENTIFIER="${PROFILE_TEAM_FIELDS#*$'\\t'}"
[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]] || \\
    die "Embedded provisioning profile application identifier does not exactly match the final signed Capture app. Discard this candidate."
[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\
    die "Embedded provisioning profile entitlement team identity does not match the selected Apple Development team. Discard this candidate."
[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\
    die "Embedded provisioning profile root TeamIdentifier does not match the selected Apple Development team. Discard this candidate."
say "Final signed app and embedded provisioning profile authorize Sign in with Apple for one exact App ID and the selected team"
unset SIGNED_ENTITLEMENTS_OUTPUT BUILT_SIGNING_IDENTITY BUILT_APPLICATION_IDENTIFIER BUILT_TEAM_IDENTIFIER BUILT_APP_ID_PREFIX PROFILE_PLIST_XML PROFILE_SIGNING_IDENTITY PROFILE_APPLICATION_IDENTIFIER PROFILE_TEAM_FIELDS PROFILE_TEAM_IDENTIFIER PROFILE_ROOT_TEAM_IDENTIFIER BUILT_PROFILE APP_ID_SUFFIX
''',
    "profile application/team checks",
)

INSTALLER.write_text(text, encoding="utf-8")

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya signed Apple application identity custody source contract")
struct TuyaSignedAppleAppIdentityCustodySourceTests {
    @Test("field installer preserves App ID prefix while proving exact bundle and selected team")
    func prefixSafeSignedApplicationIdentityIsProvenBeforeInstall() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(!installer.contains("EXPECTED_APPLICATION_IDENTIFIER=\"${TEAM_ID}.${BUNDLE_ID}\""))
        #expect(installer.contains("APP_ID_SUFFIX=\".${BUNDLE_ID}\""))
        #expect(installer.contains("[[ \"$BUILT_APPLICATION_IDENTIFIER\" == *\"$APP_ID_SUFFIX\" ]]"))
        #expect(installer.contains("[[ \"$BUILT_APPLICATION_IDENTIFIER\" != *\"*\"* ]]"))
        #expect(installer.contains("BUILT_APP_ID_PREFIX=\"${BUILT_APPLICATION_IDENTIFIER%$APP_ID_SUFFIX}\""))
        #expect(installer.contains("[[ -n \"$BUILT_APP_ID_PREFIX\" && \"$BUILT_APP_ID_PREFIX\" != \"$BUILT_APPLICATION_IDENTIFIER\" ]]"))
        #expect(installer.contains("[[ \"$BUILT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"))
        #expect(installer.contains("[[ \"$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER\" ]]"))
        #expect(installer.contains("[[ \"$PROFILE_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"))
        #expect(installer.contains("[[ \"$PROFILE_ROOT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"))
        #expect(installer.contains("application-identifier"))
        #expect(installer.contains("com.apple.developer.team-identifier"))
        #expect(installer.contains("TeamIdentifier"))

        let installMarker = try #require(installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone\""))
        for check in [
            "[[ \"$BUILT_APPLICATION_IDENTIFIER\" == *\"$APP_ID_SUFFIX\" ]]",
            "[[ \"$BUILT_APPLICATION_IDENTIFIER\" != *\"*\"* ]]",
            "[[ \"$BUILT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER\" ]]",
            "[[ \"$PROFILE_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_ROOT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"
        ] {
            let range = try #require(installer.range(of: check))
            #expect(range.lowerBound < installMarker.lowerBound, "signed Apple identity must be proven before installation: \(check)")
        }
    }

    @Test("profile identity is matched to signed app rather than synthesized from Team ID")
    func profileMatchesExactSignedApplicationIdentifier() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        #expect(installer.contains("sys.stdout.write(application + \"\\t\" + entitlement_team + \"\\t\" + team_identifiers[0])"))
        #expect(installer.contains("PROFILE_ROOT_TEAM_IDENTIFIER"))
        #expect(installer.contains("$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER"))
        #expect(!installer.contains("$PROFILE_APPLICATION_IDENTIFIER\" == \"$TEAM_ID.$BUNDLE_ID"))
    }

    @Test("identity proof remains signing custody only")
    func identityProofCannotMintScooterAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let start = try #require(installer.range(of: "APP_ID_SUFFIX=\".${BUNDLE_ID}\""))
        let end = try #require(installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone\"", range: start.upperBound..<installer.endIndex))
        let custody = installer[start.lowerBound..<end.lowerBound]

        for forbidden in [
            "connectBLE",
            "publishDps",
            "queryDps",
            "writeValue",
            "scanForPeripherals",
            "NEMBRA_SIMULATION_"
        ] {
            #expect(!custody.contains(forbidden), "signed Apple identity custody must not introduce BLE/protocol/physical authority: \(forbidden)")
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
''', encoding="utf-8")

final_installer = INSTALLER.read_text(encoding="utf-8")
assert 'EXPECTED_APPLICATION_IDENTIFIER="${TEAM_ID}.${BUNDLE_ID}"' not in final_installer
assert '[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]]' in final_installer
assert '[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]' in final_installer
print("prefix-safe signed Apple App ID custody materialized: PASS")
