#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = (ROOT / "scripts/field/install_one_time_capture.command").read_text(encoding="utf-8")
PROJECT = (ROOT / "NembraCapture.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
ENTITLEMENTS = (ROOT / "NembraCapture.entitlements").read_text(encoding="utf-8")

required_installer = [
    '[[ -x /usr/bin/codesign ]] || die "System codesign is required for effective signed-entitlement verification."',
    '[[ -x /usr/bin/security ]] || die "System security is required for embedded provisioning-profile verification."',
    '/usr/bin/codesign -d --entitlements :- --xml "$APP"',
    'com.apple.developer.applesignin',
    '[[ "$BUILT_APPLE_SIGNIN_ENTITLEMENT" == "Default" ]]',
    'BUILT_PROFILE="$APP/embedded.mobileprovision"',
    '/usr/bin/security cms -D -i "$BUILT_PROFILE"',
    'root.get("Entitlements", {}).get("com.apple.developer.applesignin")',
    '[[ "$PROFILE_APPLE_SIGNIN_ENTITLEMENT" == "Default" ]]',
    'Final signed app and embedded provisioning profile both authorize Sign in with Apple',
]
for needle in required_installer:
    if needle not in INSTALLER:
        raise SystemExit(f"missing signed Apple entitlement custody contract: {needle}")

if INSTALLER.index('/usr/bin/codesign -d --entitlements :- --xml "$APP"') > INSTALLER.index('say "Installing SDK-integrated Capture on the intended iPhone"'):
    raise SystemExit("effective entitlement verification must finish before installation begins")
if INSTALLER.index('/usr/bin/security cms -D -i "$BUILT_PROFILE"') > INSTALLER.index('say "Installing SDK-integrated Capture on the intended iPhone"'):
    raise SystemExit("provisioning entitlement verification must finish before installation begins")

if "CODE_SIGN_ENTITLEMENTS = NembraCapture.entitlements;" not in PROJECT:
    raise SystemExit("standalone Capture target must wire the Apple entitlement source into code signing")
if "<key>com.apple.developer.applesignin</key>" not in ENTITLEMENTS or "<string>Default</string>" not in ENTITLEMENTS:
    raise SystemExit("standalone Capture entitlement source must request default Sign in with Apple authority")

for forbidden in (
    "SIMCTL_CHILD_",
    "NEMBRA_SIMULATION_",
    "connectBLE",
    "publishDps",
    "writeValue",
):
    if forbidden in "\n".join(required_installer):
        raise SystemExit(f"Apple entitlement custody must not introduce protocol/physical authority: {forbidden}")

print("capture Apple Sign-In signed-entitlement custody source contract: PASS")
