from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSignedAppleAppIdentityCustodySourceTests.swift"

TEST_SOURCE = '''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya signed Apple application identity custody source contract")
struct TuyaSignedAppleAppIdentityCustodySourceTests {
    @Test("field installer proves the exact signed App ID and team before installation")
    func exactSignedApplicationIdentityIsProvenBeforeInstall() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        let required = [
            "EXPECTED_APPLICATION_IDENTIFIER=\\\"${TEAM_ID}.${BUNDLE_ID}\\\"",
            "BUILT_APPLICATION_IDENTIFIER",
            "BUILT_TEAM_IDENTIFIER",
            "PROFILE_APPLICATION_IDENTIFIER",
            "PROFILE_TEAM_IDENTIFIER",
            "application-identifier",
            "com.apple.developer.team-identifier",
            "TeamIdentifier",
            "[[ \\\"$BUILT_APPLICATION_IDENTIFIER\\\" == \\\"$EXPECTED_APPLICATION_IDENTIFIER\\\" ]]",
            "[[ \\\"$BUILT_TEAM_IDENTIFIER\\\" == \\\"$TEAM_ID\\\" ]]",
            "[[ \\\"$PROFILE_APPLICATION_IDENTIFIER\\\" == \\\"$EXPECTED_APPLICATION_IDENTIFIER\\\" ]]",
            "[[ \\\"$PROFILE_TEAM_IDENTIFIER\\\" == \\\"$TEAM_ID\\\" ]]"
        ]
        for needle in required {
            #expect(installer.contains(needle), "missing signed Apple application-identity custody contract: \\(needle)")
        }

        let installMarker = try #require(installer.range(of: "say \\\"Installing SDK-integrated Capture on the intended iPhone\\\""))
        for check in [
            "[[ \\\"$BUILT_APPLICATION_IDENTIFIER\\\" == \\\"$EXPECTED_APPLICATION_IDENTIFIER\\\" ]]",
            "[[ \\\"$BUILT_TEAM_IDENTIFIER\\\" == \\\"$TEAM_ID\\\" ]]",
            "[[ \\\"$PROFILE_APPLICATION_IDENTIFIER\\\" == \\\"$EXPECTED_APPLICATION_IDENTIFIER\\\" ]]",
            "[[ \\\"$PROFILE_TEAM_IDENTIFIER\\\" == \\\"$TEAM_ID\\\" ]]"
        ] {
            let range = try #require(installer.range(of: check))
            #expect(range.lowerBound < installMarker.lowerBound, "signed Apple identity must be proven before installation: \\(check)")
        }
    }

    @Test("identity proof remains signing custody only")
    func identityProofCannotMintScooterAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let start = try #require(installer.range(of: "EXPECTED_APPLICATION_IDENTIFIER=\\\"${TEAM_ID}.${BUNDLE_ID}\\\""))
        let end = try #require(installer.range(of: "say \\\"Installing SDK-integrated Capture on the intended iPhone\\\"", range: start.upperBound..<installer.endIndex))
        let custody = installer[start.lowerBound..<end.lowerBound]

        for forbidden in [
            "connectBLE",
            "publishDps",
            "writeValue",
            "scanForPeripherals",
            "NEMBRA_SIMULATION_"
        ] {
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
        'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\nPROCEDURE_ID=',
        'BUNDLE_ID="com.jonathangana131.nembra.capturelearn"\nEXPECTED_APPLICATION_IDENTIFIER="${TEAM_ID}.${BUNDLE_ID}"\nPROCEDURE_ID=',
        "expected signed application identifier",
    )

    old_signed = '''BUILT_APPLE_SIGNIN_ENTITLEMENT="$(printf '%s' "$SIGNED_ENTITLEMENTS_OUTPUT" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '\nimport plistlib, sys\npayload = sys.stdin.buffer.read()\nstart = payload.find(b"<?xml")\nend = payload.rfind(b"</plist>")\nif start < 0 or end < start:\n    raise SystemExit(2)\ntry:\n    value = plistlib.loads(payload[start:end + len(b"</plist>")]).get("com.apple.developer.applesignin")\nexcept Exception:\n    raise SystemExit(2)\nif value == ["Default"]:\n    sys.stdout.write("Default")\n' || true)"\n[[ "$BUILT_APPLE_SIGNIN_ENTITLEMENT" == "Default" ]] || \\\n    die "Final signed Capture app does not carry the required Sign in with Apple entitlement. Enable the capability for this App ID/team and rebuild; do not install this candidate."\n'''
    new_signed = '''BUILT_SIGNING_IDENTITY="$(printf '%s' "$SIGNED_ENTITLEMENTS_OUTPUT" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '\nimport plistlib, sys\npayload = sys.stdin.buffer.read()\nstart = payload.find(b"<?xml")\nend = payload.rfind(b"</plist>")\nif start < 0 or end < start:\n    raise SystemExit(2)\ntry:\n    entitlements = plistlib.loads(payload[start:end + len(b"</plist>")])\n    apple = entitlements.get("com.apple.developer.applesignin")\n    application = entitlements.get("application-identifier")\n    team = entitlements.get("com.apple.developer.team-identifier")\nexcept Exception:\n    raise SystemExit(2)\nif apple == ["Default"] and isinstance(application, str) and isinstance(team, str):\n    sys.stdout.write(application + "\\t" + team)\n' || true)"\n[[ "$BUILT_SIGNING_IDENTITY" == *$'\\t'* ]] || \\\n    die "Final signed Capture app is missing required Sign in with Apple or exact application/team identity entitlements. Discard this candidate."\nBUILT_APPLICATION_IDENTIFIER="${BUILT_SIGNING_IDENTITY%%$'\\t'*}"\nBUILT_TEAM_IDENTIFIER="${BUILT_SIGNING_IDENTITY#*$'\\t'}"\n[[ "$BUILT_APPLICATION_IDENTIFIER" == "$EXPECTED_APPLICATION_IDENTIFIER" ]] || \\\n    die "Final signed Capture app application-identifier does not match the selected team and Capture bundle identifier. Discard this candidate."\n[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\\n    die "Final signed Capture app team identifier does not match the selected Apple Development team. Discard this candidate."\n'''
    text = replace_once(text, old_signed, new_signed, "signed app identity custody")

    old_profile = '''PROFILE_APPLE_SIGNIN_ENTITLEMENT="$(printf '%s' "$PROFILE_PLIST_XML" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '\nimport plistlib, sys\ntry:\n    root = plistlib.loads(sys.stdin.buffer.read())\n    value = root.get("Entitlements", {}).get("com.apple.developer.applesignin")\nexcept Exception:\n    raise SystemExit(2)\nif value == ["Default"]:\n    sys.stdout.write("Default")\n' || true)"\n[[ "$PROFILE_APPLE_SIGNIN_ENTITLEMENT" == "Default" ]] || \\\n    die "Embedded provisioning profile does not authorize Sign in with Apple for the final Capture app. Enable the capability for this App ID/team and rebuild; do not install this candidate."\nsay "Final signed app and embedded provisioning profile both authorize Sign in with Apple"\nunset SIGNED_ENTITLEMENTS_OUTPUT BUILT_APPLE_SIGNIN_ENTITLEMENT PROFILE_PLIST_XML PROFILE_APPLE_SIGNIN_ENTITLEMENT BUILT_PROFILE\n'''
    new_profile = '''PROFILE_SIGNING_IDENTITY="$(printf '%s' "$PROFILE_PLIST_XML" | /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '\nimport plistlib, sys\ntry:\n    root = plistlib.loads(sys.stdin.buffer.read())\n    entitlements = root.get("Entitlements", {})\n    apple = entitlements.get("com.apple.developer.applesignin")\n    application = entitlements.get("application-identifier")\n    entitlement_team = entitlements.get("com.apple.developer.team-identifier")\n    team_identifiers = root.get("TeamIdentifier")\nexcept Exception:\n    raise SystemExit(2)\nif (apple == ["Default"] and isinstance(application, str) and isinstance(entitlement_team, str)\n        and isinstance(team_identifiers, list) and len(team_identifiers) == 1\n        and team_identifiers[0] == entitlement_team):\n    sys.stdout.write(application + "\\t" + entitlement_team)\n' || true)"\n[[ "$PROFILE_SIGNING_IDENTITY" == *$'\\t'* ]] || \\\n    die "Embedded provisioning profile is missing required Sign in with Apple or exact application/team identity custody. Discard this candidate."\nPROFILE_APPLICATION_IDENTIFIER="${PROFILE_SIGNING_IDENTITY%%$'\\t'*}"\nPROFILE_TEAM_IDENTIFIER="${PROFILE_SIGNING_IDENTITY#*$'\\t'}"\n[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$EXPECTED_APPLICATION_IDENTIFIER" ]] || \\\n    die "Embedded provisioning profile application identifier does not match the selected team and Capture bundle identifier. Discard this candidate."\n[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]] || \\\n    die "Embedded provisioning profile team identity does not match the selected Apple Development team. Discard this candidate."\nsay "Final signed app and embedded provisioning profile authorize Sign in with Apple for the exact selected App ID and team"\nunset SIGNED_ENTITLEMENTS_OUTPUT BUILT_SIGNING_IDENTITY BUILT_APPLICATION_IDENTIFIER BUILT_TEAM_IDENTIFIER PROFILE_PLIST_XML PROFILE_SIGNING_IDENTITY PROFILE_APPLICATION_IDENTIFIER PROFILE_TEAM_IDENTIFIER BUILT_PROFILE\n'''
    text = replace_once(text, old_profile, new_profile, "profile identity custody")

    INSTALLER.write_text(text, encoding="utf-8")
    if TEST.exists():
        raise SystemExit("signed Apple identity regression unexpectedly exists on product parent")
    TEST.write_text(TEST_SOURCE, encoding="utf-8")


def verify() -> None:
    text = INSTALLER.read_text(encoding="utf-8")
    required = (
        'EXPECTED_APPLICATION_IDENTIFIER="${TEAM_ID}.${BUNDLE_ID}"',
        'application-identifier',
        'com.apple.developer.team-identifier',
        'TeamIdentifier',
        'BUILT_APPLICATION_IDENTIFIER',
        'BUILT_TEAM_IDENTIFIER',
        'PROFILE_APPLICATION_IDENTIFIER',
        'PROFILE_TEAM_IDENTIFIER',
        '[[ "$BUILT_APPLICATION_IDENTIFIER" == "$EXPECTED_APPLICATION_IDENTIFIER" ]]',
        '[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
        '[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$EXPECTED_APPLICATION_IDENTIFIER" ]]',
        '[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    )
    for token in required:
        if token not in text:
            raise SystemExit(f"required signing custody token missing: {token}")
    install = text.index('say "Installing SDK-integrated Capture on the intended iPhone"')
    for token in required[-4:]:
        if text.index(token) >= install:
            raise SystemExit(f"signing identity check occurs after install boundary: {token}")
    custody = text[text.index('EXPECTED_APPLICATION_IDENTIFIER="${TEAM_ID}.${BUNDLE_ID}"'):install]
    for forbidden in ("connectBLE", "publishDps", "writeValue", "scanForPeripherals", "NEMBRA_SIMULATION_"):
        if forbidden in custody:
            raise SystemExit(f"signing custody grew physical/protocol authority: {forbidden}")
    test = TEST.read_text(encoding="utf-8")
    if "exactSignedApplicationIdentityIsProvenBeforeInstall" not in test or "identityProofCannotMintScooterAuthority" not in test:
        raise SystemExit("signed Apple identity source regression incomplete")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
