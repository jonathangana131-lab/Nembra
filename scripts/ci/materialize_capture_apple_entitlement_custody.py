#!/usr/bin/env python3
from pathlib import Path

installer_path = Path("scripts/field/install_one_time_capture.command")
test_path = Path("scripts/ci/tests/test_capture_apple_signin_field_entitlement_custody.py")
text = installer_path.read_text(encoding="utf-8")


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one source match, found {count}: {old[:120]!r}")
    text = text.replace(old, new, 1)


replace_once(
    '[[ -x /usr/bin/plutil ]] || die "System plutil is required for exact built-app provenance verification."\n',
    '[[ -x /usr/bin/plutil ]] || die "System plutil is required for exact built-app provenance verification."\n'
    '[[ -x /usr/bin/codesign ]] || die "System codesign is required for effective signed-entitlement verification."\n'
    '[[ -x /usr/bin/security ]] || die "System security is required for embedded provisioning-profile verification."\n',
)

anchor = '''[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]] || die "Built Capture app bundle identifier does not match the intended standalone field product. Discard this candidate."
say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, canonical stationary procedure, and field product"
unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_PROCEDURE_IDENTIFIER BUILT_BUNDLE_ID APP_INFO_PLIST
'''
replacement = '''[[ "$BUILT_BUNDLE_ID" == "$BUNDLE_ID" ]] || die "Built Capture app bundle identifier does not match the intended standalone field product. Discard this candidate."
say "Built app provenance matched exact requested source, reviewed Tuya dependency lock, canonical stationary procedure, and field product"

# Apple-backed Smart Life account entry is now part of field preflight. A source entitlement file
# is not enough: prove the final signed executable and the exact embedded provisioning profile both
# authorize Sign in with Apple before this build can be installed as the field candidate.
SIGNED_ENTITLEMENTS_XML="$(/usr/bin/codesign -d --entitlements :- --xml "$APP" 2>/dev/null)" || \
    die "Could not read effective entitlements from the final signed Capture app. Discard this candidate."
BUILT_APPLE_SIGNIN_ENTITLEMENT="$(printf '%s' "$SIGNED_ENTITLEMENTS_XML" | /usr/bin/python3 -I -c '
import plistlib, sys
try:
    value = plistlib.loads(sys.stdin.buffer.read()).get("com.apple.developer.applesignin")
except Exception:
    raise SystemExit(2)
if value == ["Default"]:
    sys.stdout.write("Default")
' || true)"
[[ "$BUILT_APPLE_SIGNIN_ENTITLEMENT" == "Default" ]] || \
    die "Final signed Capture app does not carry the required Sign in with Apple entitlement. Enable the capability for this App ID/team and rebuild; do not install this candidate."

BUILT_PROFILE="$APP/embedded.mobileprovision"
[[ -f "$BUILT_PROFILE" ]] || die "Final signed Capture app is missing embedded.mobileprovision. Discard this candidate."
PROFILE_PLIST_XML="$(/usr/bin/security cms -D -i "$BUILT_PROFILE" 2>/dev/null)" || \
    die "Could not decode the exact provisioning profile embedded in the final signed Capture app. Discard this candidate."
PROFILE_APPLE_SIGNIN_ENTITLEMENT="$(printf '%s' "$PROFILE_PLIST_XML" | /usr/bin/python3 -I -c '
import plistlib, sys
try:
    root = plistlib.loads(sys.stdin.buffer.read())
    value = root.get("Entitlements", {}).get("com.apple.developer.applesignin")
except Exception:
    raise SystemExit(2)
if value == ["Default"]:
    sys.stdout.write("Default")
' || true)"
[[ "$PROFILE_APPLE_SIGNIN_ENTITLEMENT" == "Default" ]] || \
    die "Embedded provisioning profile does not authorize Sign in with Apple for the final Capture app. Enable the capability for this App ID/team and rebuild; do not install this candidate."
say "Final signed app and embedded provisioning profile both authorize Sign in with Apple"
unset SIGNED_ENTITLEMENTS_XML BUILT_APPLE_SIGNIN_ENTITLEMENT PROFILE_PLIST_XML PROFILE_APPLE_SIGNIN_ENTITLEMENT BUILT_PROFILE
unset BUILT_BUILD_IDENTIFIER BUILT_SOURCE_SHA BUILT_TUYA_DEPENDENCY_LOCK_SHA256 BUILT_PROCEDURE_IDENTIFIER BUILT_BUNDLE_ID APP_INFO_PLIST
'''
replace_once(anchor, replacement)
installer_path.write_text(text, encoding="utf-8")

test_path.write_text(r'''#!/usr/bin/env python3
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
''', encoding="utf-8")

required = [
    '/usr/bin/codesign -d --entitlements :- --xml "$APP"',
    '[[ "$BUILT_APPLE_SIGNIN_ENTITLEMENT" == "Default" ]]',
    '/usr/bin/security cms -D -i "$BUILT_PROFILE"',
    '[[ "$PROFILE_APPLE_SIGNIN_ENTITLEMENT" == "Default" ]]',
]
missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit(f"materialized installer is missing Apple entitlement custody: {missing}")
