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
    'BUILT_SIGNING_IDENTITY',
    'BUILT_APPLICATION_IDENTIFIER',
    'BUILT_TEAM_IDENTIFIER',
    'APP_ID_SUFFIX=".${BUNDLE_ID}"',
    '[[ "$BUILT_APPLICATION_IDENTIFIER" == *"$APP_ID_SUFFIX" ]]',
    '[[ "$BUILT_APPLICATION_IDENTIFIER" != *"*"* ]]',
    'BUILT_APP_ID_PREFIX="${BUILT_APPLICATION_IDENTIFIER%$APP_ID_SUFFIX}"',
    '[[ -n "$BUILT_APP_ID_PREFIX" && "$BUILT_APP_ID_PREFIX" != "$BUILT_APPLICATION_IDENTIFIER" ]]',
    '[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    'BUILT_PROFILE="$APP/embedded.mobileprovision"',
    '/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i "$BUILT_PROFILE"',
    'PROFILE_SIGNING_IDENTITY',
    'PROFILE_APPLICATION_IDENTIFIER',
    'PROFILE_TEAM_IDENTIFIER',
    'PROFILE_ROOT_TEAM_IDENTIFIER',
    'TeamIdentifier',
    '[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]]',
    '[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    '[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    'Final signed app and embedded provisioning profile authorize Sign in with Apple for one exact App ID and the selected team',
]
for needle in required_installer:
    if needle not in INSTALLER:
        raise SystemExit(f"missing signed Apple identity custody contract: {needle}")

for forbidden in (
    'EXPECTED_APPLICATION_IDENTIFIER="${TEAM_ID}.${BUNDLE_ID}"',
    '[[ "$BUILT_APPLE_SIGNIN_ENTITLEMENT" == "Default" ]]',
    '[[ "$PROFILE_APPLE_SIGNIN_ENTITLEMENT" == "Default" ]]',
):
    if forbidden in INSTALLER:
        raise SystemExit(f"stale/unsafe Apple identity custody contract remains: {forbidden}")

install_marker = INSTALLER.index('say "Installing SDK-integrated Capture on the intended iPhone"')
for check in (
    '[[ "$BUILT_APPLICATION_IDENTIFIER" == *"$APP_ID_SUFFIX" ]]',
    '[[ "$BUILT_APPLICATION_IDENTIFIER" != *"*"* ]]',
    '[[ -n "$BUILT_APP_ID_PREFIX" && "$BUILT_APP_ID_PREFIX" != "$BUILT_APPLICATION_IDENTIFIER" ]]',
    '[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    '[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]]',
    '[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    '[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
):
    if INSTALLER.index(check) > install_marker:
        raise SystemExit(f"signed Apple identity verification must finish before installation begins: {check}")

if INSTALLER.index('/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -d --entitlements :- --xml "$APP" 2>&1') > install_marker:
    raise SystemExit("effective entitlement verification must finish before installation begins")
if INSTALLER.index('/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i "$BUILT_PROFILE"') > install_marker:
    raise SystemExit("provisioning entitlement verification must finish before installation begins")

if 'if apple == ["Default"] and isinstance(application, str) and isinstance(team, str):' not in INSTALLER:
    raise SystemExit("signed app parser must require Sign in with Apple plus application/team identity")
if 'sys.stdout.write(application + "\\t" + team)' not in INSTALLER:
    raise SystemExit("signed app parser must return exact application/team identity")
if 'sys.stdout.write(application + "\\t" + entitlement_team + "\\t" + team_identifiers[0])' not in INSTALLER:
    raise SystemExit("profile parser must return exact application/entitlement-team/root-team identity")

if "CODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;" not in PROJECT:
    raise SystemExit("standalone Capture target must wire the Apple entitlement source into code signing")
if "<key>com.apple.developer.applesignin</key>" not in ENTITLEMENTS or "<string>Default</string>" not in ENTITLEMENTS:
    raise SystemExit("standalone Capture entitlement source must request default Sign in with Apple authority")

# Every external process in the Apple identity custody block runs from a closed startup environment.
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

for forbidden in (
    "SIMCTL_CHILD_",
    "NEMBRA_SIMULATION_",
    "connectBLE",
    "publishDps",
    "queryDps",
    "writeValue",
    "scanForPeripherals",
):
    if forbidden in custody:
        raise SystemExit(f"Apple identity custody must not introduce protocol/physical authority: {forbidden}")

print("capture Apple Sign-In signed-identity custody source contract: PASS")
