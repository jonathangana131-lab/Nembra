#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = (ROOT / "scripts/field/install_one_time_capture.command").read_text(encoding="utf-8")
PROJECT = (ROOT / "NembraCapture.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
ENTITLEMENTS = (ROOT / "NembraCapture.entitlements").read_text(encoding="utf-8")

required_installer = [
    '[[ -x /usr/bin/codesign ]] || die "System codesign is required for effective signed-entitlement verification."',
    '[[ -x /usr/bin/security ]] || die "System security is required for embedded provisioning-profile verification."',
    'APP_ID_SUFFIX=".${BUNDLE_ID}"',
    '/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -d --entitlements :- --xml "$APP" 2>&1',
    'payload.find(b"<?xml")',
    'payload.rfind(b"</plist>")',
    'apple = entitlements.get("com.apple.developer.applesignin")',
    'application = entitlements.get("application-identifier")',
    'team = entitlements.get("com.apple.developer.team-identifier")',
    '[[ "$BUILT_SIGNING_IDENTITY" == *$\'\\t\'* ]]',
    'BUILT_APPLICATION_IDENTIFIER="${BUILT_SIGNING_IDENTITY%%$\'\\t\'*}"',
    'BUILT_TEAM_IDENTIFIER="${BUILT_SIGNING_IDENTITY#*$\'\\t\'}"',
    '[[ "$BUILT_APPLICATION_IDENTIFIER" == *"$APP_ID_SUFFIX" ]]',
    '[[ "$BUILT_APPLICATION_IDENTIFIER" != *"*"* ]]',
    'BUILT_APP_ID_PREFIX="${BUILT_APPLICATION_IDENTIFIER%$APP_ID_SUFFIX}"',
    '[[ -n "$BUILT_APP_ID_PREFIX" && "$BUILT_APP_ID_PREFIX" != "$BUILT_APPLICATION_IDENTIFIER" ]]',
    '[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    'BUILT_PROFILE="$APP/embedded.mobileprovision"',
    '/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i "$BUILT_PROFILE"',
    'entitlement_team = entitlements.get("com.apple.developer.team-identifier")',
    'team_identifiers = root.get("TeamIdentifier")',
    '[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]]',
    '[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    '[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    'Final signed app and embedded provisioning profile authorize Sign in with Apple for one exact App ID and the selected team',
]
for needle in required_installer:
    if needle not in INSTALLER:
        raise SystemExit(f"missing signed Apple entitlement/application identity custody contract: {needle}")

# Apple documents that an App ID prefix is sometimes, but not always, equal to the Team ID.
# Preserve the exact prefix actually carried by the final signature/profile rendezvous instead of
# synthesizing one from the selected development team.
if 'EXPECTED_APPLICATION_IDENTIFIER="${TEAM_ID}.${BUNDLE_ID}"' in INSTALLER:
    raise SystemExit("field custody must not assume the Apple App ID prefix equals the Team ID")

install_marker = 'say "Installing SDK-integrated Capture on the intended iPhone"'
install = INSTALLER.index(install_marker)
for marker in (
    '/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -d --entitlements :- --xml "$APP" 2>&1',
    '/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i "$BUILT_PROFILE"',
    '[[ "$BUILT_APPLICATION_IDENTIFIER" == *"$APP_ID_SUFFIX" ]]',
    '[[ "$BUILT_APPLICATION_IDENTIFIER" != *"*"* ]]',
    '[[ -n "$BUILT_APP_ID_PREFIX" && "$BUILT_APP_ID_PREFIX" != "$BUILT_APPLICATION_IDENTIFIER" ]]',
    '[[ "$BUILT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    '[[ "$PROFILE_APPLICATION_IDENTIFIER" == "$BUILT_APPLICATION_IDENTIFIER" ]]',
    '[[ "$PROFILE_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
    '[[ "$PROFILE_ROOT_TEAM_IDENTIFIER" == "$TEAM_ID" ]]',
):
    if INSTALLER.index(marker) > install:
        raise SystemExit(f"signed Apple identity verification must finish before installation: {marker}")

if "CODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;" not in PROJECT:
    raise SystemExit("standalone Capture target must wire the Apple entitlement source into code signing")
if "<key>com.apple.developer.applesignin</key>" not in ENTITLEMENTS or "<string>Default</string>" not in ENTITLEMENTS:
    raise SystemExit("standalone Capture entitlement source must request default Sign in with Apple authority")

# Every external process in the actual Apple entitlement custody block runs from a closed startup
# environment. Inspect production bytes directly so future protocol/Simulator authority cannot hide
# behind a hand-authored expected-token list.
custody = INSTALLER[INSTALLER.index("SIGNED_ENTITLEMENTS_OUTPUT="):install]
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
    "disconnectBLE",
    "publishDps",
    "queryDps",
    "writeValue",
):
    if forbidden in custody:
        raise SystemExit(f"Apple signing custody must not introduce protocol/physical authority: {forbidden}")

print("capture Apple Sign-In signed application-identity custody source contract: PASS")
