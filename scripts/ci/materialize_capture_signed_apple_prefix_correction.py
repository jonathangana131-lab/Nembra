from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSignedAppleAppIdentityCustodySourceTests.swift"

CORRECTED_TEST = '''import Foundation
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
            "[[ \\\"$BUILT_APPLICATION_IDENTIFIER\\\" == *\\\".$BUNDLE_ID\\\" ]]",
            "[[ \\\"$PROFILE_APPLICATION_IDENTIFIER\\\" == \\\"$BUILT_APPLICATION_IDENTIFIER\\\" ]]",
            "[[ \\\"$BUILT_TEAM_IDENTIFIER\\\" == \\\"$TEAM_ID\\\" ]]",
            "[[ \\\"$PROFILE_TEAM_IDENTIFIER\\\" == \\\"$TEAM_ID\\\" ]]",
            "[[ \\\"$PROFILE_ROOT_TEAM_IDENTIFIER\\\" == \\\"$TEAM_ID\\\" ]]"
        ]
        for needle in required {
            #expect(installer.contains(needle), "missing signed Apple application-identity custody contract: \\(needle)")
        }

        let installMarker = try #require(installer.range(of: "say \\\"Installing SDK-integrated Capture on the intended iPhone\\\""))
        for check in [
            "[[ \\\"$BUILT_APPLICATION_IDENTIFIER\\\" == *\\\".$BUNDLE_ID\\\" ]]",
            "[[ \\\"$PROFILE_APPLICATION_IDENTIFIER\\\" == \\\"$BUILT_APPLICATION_IDENTIFIER\\\" ]]",
            "[[ \\\"$BUILT_TEAM_IDENTIFIER\\\" == \\\"$TEAM_ID\\\" ]]",
            "[[ \\\"$PROFILE_TEAM_IDENTIFIER\\\" == \\\"$TEAM_ID\\\" ]]",
            "[[ \\\"$PROFILE_ROOT_TEAM_IDENTIFIER\\\" == \\\"$TEAM_ID\\\" ]]"
        ] {
            let range = try #require(installer.range(of: check))
            #expect(range.lowerBound < installMarker.lowerBound, "signed Apple identity must be proven before installation: \\(check)")
        }

        #expect(!installer.contains("EXPECTED_APPLICATION_IDENTIFIER=\\\"${TEAM_ID}.${BUNDLE_ID}\\\""))
    }

    @Test("identity proof remains signing custody only")
    func identityProofCannotMintScooterAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let start = try #require(installer.range(of: "BUILT_APPLICATION_IDENTIFIER"))
        let end = try #require(installer.range(of: "say \\\"Installing SDK-integrated Capture on the intended iPhone\\\"", range: start.upperBound..<installer.endIndex))
        let custody = installer[start.lowerBound..<end.lowerBound]

        for forbidden in ["connectBLE", "publishDps", "writeValue", "scanForPeripherals", "NEMBRA_SIMULATION_"] {
            #expect(!custody.contains(forbidden), "signed Apple identity custody must not introduce BLE/protocol/physical authority: \\(forbidden)")
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
'''


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    text = INSTALLER.read_text(encoding="utf-8")
    text = replace_once(
        text,
        'EXPECTED_APPLICATION_IDENTIFIER="${TEAM_ID}.${BUNDLE_ID}"\n',
        '',
        'remove invalid team-derived App ID prefix assumption',
    )
    text = replace_once(
        text,
        '[[ "$BUILT_APPLICATION_IDENTIFIER" == "$EXPECTED_APPLICATION_IDENTIFIER" ]] || \\\n    die "Final signed Capture app application-identifier does not match the selected team and Capture bundle identifier. Discard this candidate."\n',
        '[[ "$BUILT_APPLICATION_IDENTIFIER" == *".$BUNDLE_ID" ]] || \\\n    die "Final signed Capture app application-identifier does not end in the exact Capture bundle identifier. Discard this candidate."\n',
        'signed app bundle suffix proof',
    )
    old_profile_parser = '''if (apple == ["Default"] and isinstance(application, str) and isinstance(entitlement_team, str)\n        and isinstance(team_identifiers, list) and len(team_identifiers) == 1\n        and team_identifiers[0] == entitlement_team):\n    sys.stdout.write(application + "\\t" + entitlement_team)\n'''
    new_profile_parser = '''if (apple == ["Default"] and isinstance(application, str) and isinstance(entitlement_team, str)\n        and isinstance(team_identifiers, list) and len(team_identifiers) == 1\n        and isinstance(team_identifiers[0], str)):\n    sys.stdout.write(application + "\\t" + entitlement_team + "\\t" + team_identifiers[0])\n'''
    text = replace_once(text, old_profile_parser, new_profile_parser, 'profile identity parser')
    old_profile_split_and_checks = '''[[ "$PROFILE_SIGNING_IDENTITY" == *$'\\t'* ]] || \\\n    die "Embedded provisioning profile is missing required Sign in with Apple or exact application/team identity custody. Discard this candidate."\nPROFILE_APPLICATION_IDENTIFIER="${PROFILE_SIGNING_IDENTITY%%$'\\t'*}"\nPROFILE_TEAM_IDENTIFIER="${PROFILE_SIGNING_IDENTITY#*$'\\t'}"\n[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$EXPECTED_APPLICATION_IDENTIFIER" ]] || \\\n    die "Embedded provisioning profile application identifier does not match the selected team and Capture bundle identifier. Discard this candidate."\n[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\\n    die "Embedded provisioning profile team identity does not match the selected Apple Development team. Discard this candidate."\nsay "Final signed app and embedded provisioning profile authorize Sign in with Apple for the exact selected App ID and team"\nunset SIGNED_ENTITLEMENTS_OUTPUT BUILT_SIGNING_IDENTITY BUILT_APPLICATION_IDENTIFIER BUILT_TEAM_IDENTIFIER PROFILE_PLIST_XML PROFILE_SIGNING_IDENTITY PROFILE_APPLICATION_IDENTIFIER PROFILE_TEAM_IDENTIFIER BUILT_PROFILE\n'''
    new_profile_split_and_checks = '''[[ "$PROFILE_SIGNING_IDENTITY" == *$'\\t'*$'\\t'* ]] || \\\n    die "Embedded provisioning profile is missing required Sign in with Apple or exact application/team identity custody. Discard this candidate."\nIFS=$'\\t' read -r PROFILE_APPLICATION_IDENTIFIER PROFILE_TEAM_IDENTIFIER PROFILE_ROOT_TEAM_IDENTIFIER <<< "$PROFILE_SIGNING_IDENTITY"\n[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]] || \\\n    die "Embedded provisioning profile application identifier does not exactly match the final signed app identifier. Discard this candidate."\n[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\\n    die "Final signed Capture app team identifier does not match the selected Apple Development team. Discard this candidate."\n[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\\n    die "Embedded provisioning profile entitlement team identity does not match the selected Apple Development team. Discard this candidate."\n[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\\n    die "Embedded provisioning profile root TeamIdentifier does not match the selected Apple Development team. Discard this candidate."\nsay "Final signed app and embedded provisioning profile agree on the exact App ID and selected Apple team"\nunset SIGNED_ENTITLEMENTS_OUTPUT BUILT_SIGNING_IDENTITY BUILT_APPLICATION_IDENTIFIER BUILT_TEAM_IDENTIFIER PROFILE_PLIST_XML PROFILE_SIGNING_IDENTITY PROFILE_APPLICATION_IDENTIFIER PROFILE_TEAM_IDENTIFIER PROFILE_ROOT_TEAM_IDENTIFIER BUILT_PROFILE\n'''
    text = replace_once(text, old_profile_split_and_checks, new_profile_split_and_checks, 'profile exact identity checks')
    INSTALLER.write_text(text, encoding='utf-8')
    TEST.write_text(CORRECTED_TEST, encoding='utf-8')


def verify() -> None:
    text = INSTALLER.read_text(encoding='utf-8')
    forbidden = 'EXPECTED_APPLICATION_IDENTIFIER="${TEAM_ID}.${BUNDLE_ID}"'
    if forbidden in text:
        raise SystemExit('invalid App ID prefix == Team ID assumption survived')
    required = (
        '[[ "$BUILT_APPLICATION_IDENTIFIER" == *".$BUNDLE_ID" ]]',
        '[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]]',
        '[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
        '[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
        '[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
        'TeamIdentifier',
    )
    install = text.index('say "Installing SDK-integrated Capture on the intended iPhone"')
    for token in required:
        if token not in text:
            raise SystemExit(f'required corrected signing custody token missing: {token}')
        if token.startswith('[[') and text.index(token) >= install:
            raise SystemExit(f'corrected signing check occurs after install: {token}')
    custody = text[text.index('BUILT_APPLICATION_IDENTIFIER'):install]
    for bad in ("connectBLE", "publishDps", "writeValue", "scanForPeripherals", "NEMBRA_SIMULATION_"):
        if bad in custody:
            raise SystemExit(f'signing custody introduced physical/protocol authority: {bad}')
    test = TEST.read_text(encoding='utf-8')
    if forbidden not in test or '#expect(!installer.contains' not in test:
        raise SystemExit('corrected regression no longer rejects team-derived App ID prefix')


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('apply', 'verify'))
    args = parser.parse_args()
    apply() if args.mode == 'apply' else verify()
