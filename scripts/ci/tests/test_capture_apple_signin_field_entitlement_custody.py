#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = (ROOT / "scripts/field/install_one_time_capture.command").read_text(encoding="utf-8")
PROJECT = (ROOT / "NembraCapture.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
ENTITLEMENTS = (ROOT / "NembraCapture.entitlements").read_text(encoding="utf-8")

required_installer = [
    '[[ -x /usr/bin/codesign ]] || die "System codesign is required for effective signed-entitlement verification."',
    '[[ -x /usr/bin/security ]] || die "System security is required for embedded provisioning-profile verification."',
    '/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -d --entitlements :- --xml "$APP" 2>&1',
    'payload.find(b"<?xml")',
    'payload.rfind(b"</plist>")',
    'com.apple.developer.applesignin',
    'application-identifier',
    'com.apple.developer.team-identifier',
    'BUILT_APPLICATION_IDENTIFIER',
    'BUILT_TEAM_IDENTIFIER',
    'BUILT_PROFILE="$APP/embedded.mobileprovision"',
    '/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i "$BUILT_PROFILE"',
    "| /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '",
    'root.get("Entitlements", {}).get("com.apple.developer.applesignin")',
    'TeamIdentifier',
    'PROFILE_APPLICATION_IDENTIFIER',
    'PROFILE_TEAM_IDENTIFIER',
    'PROFILE_ROOT_TEAM_IDENTIFIER',
    '[[ "$BUILT_APPLICATION_IDENTIFIER" == *".$BUNDLE_ID" ]]',
    '[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]]',
    '[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    '[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    '[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
]
for needle in required_installer:
    if needle not in INSTALLER:
        raise SystemExit(f"missing signed Apple entitlement/identity custody contract: {needle}")

install_marker = INSTALLER.index('say "Installing SDK-integrated Capture on the intended iPhone"')
for check in required_installer[-5:]:
    if INSTALLER.index(check) > install_marker:
        raise SystemExit(f"signed Apple identity verification must finish before installation begins: {check}")

if 'EXPECTED_APPLICATION_IDENTIFIER="${TEAM_ID}.${BUNDLE_ID}"' in INSTALLER:
    raise SystemExit("App ID prefix must not be assumed to equal Team ID")

if "CODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;" not in PROJECT:
    raise SystemExit("standalone Capture target must wire the Apple entitlement source into code signing")
if "<key>com.apple.developer.applesignin</key>" not in ENTITLEMENTS or "<string>Default</string>" not in ENTITLEMENTS:
    raise SystemExit("standalone Capture entitlement source must request default Sign in with Apple authority")

custody = INSTALLER[INSTALLER.index("SIGNED_ENTITLEMENTS_OUTPUT="):install_marker]
if custody.count("/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '") != 2:
    raise SystemExit("both Apple plist parsers must run under a closed startup environment")
if custody.count("/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign") != 1:
    raise SystemExit("codesign entitlement inspection must run under a closed startup environment")
if custody.count("/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security") != 1:
    raise SystemExit("profile inspection must run under a closed startup environment")
for poisoned in ("DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "PYTHONPATH", "CODESIGN_ALLOCATE"):
    if poisoned in custody:
        raise SystemExit(f"caller-controlled Apple verifier state leaked into custody block: {poisoned}")
for forbidden in ("SIMCTL_CHILD_", "NEMBRA_SIMULATION_", "connectBLE", "publishDps", "writeValue", "scanForPeripherals"):
    if forbidden in custody:
        raise SystemExit(f"Apple signing custody must not introduce protocol/physical authority: {forbidden}")

print("capture Apple Sign-In signed entitlement + App ID custody source contract: PASS")
