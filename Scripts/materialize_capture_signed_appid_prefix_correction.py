#!/usr/bin/env python3
from pathlib import Path

installer_path = Path("scripts/field/install_one_time_capture.command")
source = installer_path.read_text()

wrong_expected = 'EXPECTED_APPLICATION_IDENTIFIER="${TEAM_ID}.${BUNDLE_ID}"\n'
if source.count(wrong_expected) != 1:
    raise SystemExit("derived App ID assumption missing or duplicated")
source = source.replace(wrong_expected, "", 1)

wrong_built_check = '''[[ "$BUILT_APPLICATION_IDENTIFIER" == "$EXPECTED_APPLICATION_IDENTIFIER" ]] || \\
    die "Final signed Capture app application-identifier does not match the selected team and Capture bundle identifier. Discard this candidate."
'''
correct_built_check = '''[[ "$BUILT_APPLICATION_IDENTIFIER" == *".$BUNDLE_ID" ]] || \\
    die "Final signed Capture app application-identifier does not end in the exact Capture bundle identifier. Discard this candidate."
[[ "$BUILT_APPLICATION_IDENTIFIER" != *"*"* ]] || \\
    die "Final signed Capture app application-identifier is wildcard or ambiguous. Discard this candidate."
'''
if source.count(wrong_built_check) != 1:
    raise SystemExit("signed-app App ID check drifted")
source = source.replace(wrong_built_check, correct_built_check, 1)

wrong_profile_output = '    sys.stdout.write(application + "\\t" + entitlement_team)\n'
correct_profile_output = '    sys.stdout.write(application + "\\t" + entitlement_team + "\\t" + team_identifiers[0])\n'
if source.count(wrong_profile_output) != 1:
    raise SystemExit("profile identity output drifted")
source = source.replace(wrong_profile_output, correct_profile_output, 1)

wrong_profile_parse = '''[[ "$PROFILE_SIGNING_IDENTITY" == *$'\\t'* ]] || \\
    die "Embedded provisioning profile is missing required Sign in with Apple or exact application/team identity custody. Discard this candidate."
PROFILE_APPLICATION_IDENTIFIER="${PROFILE_SIGNING_IDENTITY%%$'\\t'*}"
PROFILE_TEAM_IDENTIFIER="${PROFILE_SIGNING_IDENTITY#*$'\\t'}"
[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$EXPECTED_APPLICATION_IDENTIFIER" ]] || \\
    die "Embedded provisioning profile application identifier does not match the selected team and Capture bundle identifier. Discard this candidate."
[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\
    die "Embedded provisioning profile team identity does not match the selected Apple Development team. Discard this candidate."
'''
correct_profile_parse = '''[[ "$PROFILE_SIGNING_IDENTITY" == *$'\\t'*$'\\t'* ]] || \\
    die "Embedded provisioning profile is missing required Sign in with Apple or exact application/team identity custody. Discard this candidate."
PROFILE_APPLICATION_IDENTIFIER="${PROFILE_SIGNING_IDENTITY%%$'\\t'*}"
PROFILE_SIGNING_IDENTITY_REMAINDER="${PROFILE_SIGNING_IDENTITY#*$'\\t'}"
PROFILE_TEAM_IDENTIFIER="${PROFILE_SIGNING_IDENTITY_REMAINDER%%$'\\t'*}"
PROFILE_ROOT_TEAM_IDENTIFIER="${PROFILE_SIGNING_IDENTITY_REMAINDER#*$'\\t'}"
[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]] || \\
    die "Embedded provisioning profile application identifier does not exactly match the final signed Capture app. Discard this candidate."
[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\
    die "Embedded provisioning profile team entitlement does not match the selected Apple Development team. Discard this candidate."
[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\
    die "Embedded provisioning profile root TeamIdentifier does not match the selected Apple Development team. Discard this candidate."
'''
if source.count(wrong_profile_parse) != 1:
    raise SystemExit("profile App ID/team check block drifted")
source = source.replace(wrong_profile_parse, correct_profile_parse, 1)

old_unset = "unset SIGNED_ENTITLEMENTS_OUTPUT BUILT_SIGNING_IDENTITY BUILT_APPLICATION_IDENTIFIER BUILT_TEAM_IDENTIFIER PROFILE_PLIST_XML PROFILE_SIGNING_IDENTITY PROFILE_APPLICATION_IDENTIFIER PROFILE_TEAM_IDENTIFIER BUILT_PROFILE\n"
new_unset = "unset SIGNED_ENTITLEMENTS_OUTPUT BUILT_SIGNING_IDENTITY BUILT_APPLICATION_IDENTIFIER BUILT_TEAM_IDENTIFIER PROFILE_PLIST_XML PROFILE_SIGNING_IDENTITY PROFILE_SIGNING_IDENTITY_REMAINDER PROFILE_APPLICATION_IDENTIFIER PROFILE_TEAM_IDENTIFIER PROFILE_ROOT_TEAM_IDENTIFIER BUILT_PROFILE\n"
if source.count(old_unset) != 1:
    raise SystemExit("signing identity cleanup drifted")
source = source.replace(old_unset, new_unset, 1)
installer_path.write_text(source)

test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSignedAppleAppIdentityCustodySourceTests.swift")
test_path.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya signed Apple application identity custody source contract")
struct TuyaSignedAppleAppIdentityCustodySourceTests {
    @Test("field installer proves the exact signed App ID and team before installation")
    func exactSignedApplicationIdentityIsProvenBeforeInstall() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        let required = [
            "BUILT_APPLICATION_IDENTIFIER",
            "BUILT_TEAM_IDENTIFIER",
            "PROFILE_APPLICATION_IDENTIFIER",
            "PROFILE_TEAM_IDENTIFIER",
            "PROFILE_ROOT_TEAM_IDENTIFIER",
            "application-identifier",
            "com.apple.developer.team-identifier",
            "TeamIdentifier",
            "[[ \"$BUILT_APPLICATION_IDENTIFIER\" == *\".$BUNDLE_ID\" ]]",
            "[[ \"$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER\" ]]",
            "[[ \"$BUILT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_ROOT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"
        ]
        for needle in required {
            #expect(installer.contains(needle), "missing signed Apple application-identity custody contract: \(needle)")
        }

        let installMarker = try #require(installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone\""))
        for check in [
            "[[ \"$BUILT_APPLICATION_IDENTIFIER\" == *\".$BUNDLE_ID\" ]]",
            "[[ \"$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER\" ]]",
            "[[ \"$BUILT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_ROOT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"
        ] {
            let range = try #require(installer.range(of: check))
            #expect(range.lowerBound < installMarker.lowerBound, "signed Apple identity must be proven before installation: \(check)")
        }

        #expect(!installer.contains("EXPECTED_APPLICATION_IDENTIFIER=\"${TEAM_ID}.${BUNDLE_ID}\""))
    }

    @Test("identity proof remains signing custody only")
    func identityProofCannotMintScooterAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let start = try #require(installer.range(of: "BUILT_APPLICATION_IDENTIFIER"))
        let end = try #require(installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone\"", range: start.upperBound..<installer.endIndex))
        let custody = installer[start.lowerBound..<end.lowerBound]

        for forbidden in [
            "connectBLE",
            "publishDps",
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
''')
