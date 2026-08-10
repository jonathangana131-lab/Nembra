#!/usr/bin/env python3
from pathlib import Path

installer_path = Path("scripts/field/install_one_time_capture.command")
test_path = Path("scripts/ci/tests/test_capture_apple_signin_field_entitlement_custody.py")
text = installer_path.read_text(encoding="utf-8")

start = text.index("# Apple-backed Smart Life account entry is now part of field preflight.")
end_marker = "unset SIGNED_ENTITLEMENTS_XML BUILT_APPLE_SIGNIN_ENTITLEMENT PROFILE_PLIST_XML PROFILE_APPLE_SIGNIN_ENTITLEMENT BUILT_PROFILE\n"
end = text.index(end_marker, start) + len(end_marker)

replacement = r'''# Apple-backed Smart Life account entry is now part of field preflight. A source entitlement file
# is not enough: prove the final signed executable and the exact embedded provisioning profile both
# authorize Sign in with Apple before this build can be installed as the field candidate. Run the
# Apple verifiers with a closed startup environment and parse an XML plist from either display stream.
SIGNED_ENTITLEMENTS_OUTPUT="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -d --entitlements :- --xml "$APP" 2>&1)" || \
    die "Could not read effective entitlements from the final signed Capture app. Discard this candidate."
BUILT_APPLE_SIGNIN_ENTITLEMENT="$(printf '%s' "$SIGNED_ENTITLEMENTS_OUTPUT" | /usr/bin/python3 -I -c '
import plistlib, sys
payload = sys.stdin.buffer.read()
start = payload.find(b"<?xml")
end = payload.rfind(b"</plist>")
if start < 0 or end < start:
    raise SystemExit(2)
try:
    value = plistlib.loads(payload[start:end + len(b"</plist>")]).get("com.apple.developer.applesignin")
except Exception:
    raise SystemExit(2)
if value == ["Default"]:
    sys.stdout.write("Default")
' || true)"
[[ "$BUILT_APPLE_SIGNIN_ENTITLEMENT" == "Default" ]] || \
    die "Final signed Capture app does not carry the required Sign in with Apple entitlement. Enable the capability for this App ID/team and rebuild; do not install this candidate."

BUILT_PROFILE="$APP/embedded.mobileprovision"
[[ -f "$BUILT_PROFILE" ]] || die "Final signed Capture app is missing embedded.mobileprovision. Discard this candidate."
PROFILE_PLIST_XML="$(/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i "$BUILT_PROFILE" 2>/dev/null)" || \
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
unset SIGNED_ENTITLEMENTS_OUTPUT BUILT_APPLE_SIGNIN_ENTITLEMENT PROFILE_PLIST_XML PROFILE_APPLE_SIGNIN_ENTITLEMENT BUILT_PROFILE
'''

text = text[:start] + replacement + text[end:]
installer_path.write_text(text, encoding="utf-8")

test = test_path.read_text(encoding="utf-8")
test = test.replace(
    "    '/usr/bin/codesign -d --entitlements :- --xml \"$APP\"',",
    "    '/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -d --entitlements :- --xml \"$APP\" 2>&1',\n"
    "    'payload.find(b\"<?xml\")',\n"
    "    'payload.rfind(b\"</plist>\")',",
)
test = test.replace(
    "    '/usr/bin/security cms -D -i \"$BUILT_PROFILE\"',",
    "    '/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i \"$BUILT_PROFILE\"',",
)
test = test.replace(
    "if INSTALLER.index('/usr/bin/codesign -d --entitlements :- --xml \"$APP\"') > INSTALLER.index('say \"Installing SDK-integrated Capture on the intended iPhone\"'):",
    "if INSTALLER.index('/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign -d --entitlements :- --xml \"$APP\" 2>&1') > INSTALLER.index('say \"Installing SDK-integrated Capture on the intended iPhone\"'):",
)
test = test.replace(
    "if INSTALLER.index('/usr/bin/security cms -D -i \"$BUILT_PROFILE\"') > INSTALLER.index('say \"Installing SDK-integrated Capture on the intended iPhone\"'):",
    "if INSTALLER.index('/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i \"$BUILT_PROFILE\"') > INSTALLER.index('say \"Installing SDK-integrated Capture on the intended iPhone\"'):",
)
test += r'''

# Apple verification processes must not inherit caller-controlled startup/configuration state.
for poisoned in ("DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "PYTHONPATH", "CODESIGN_ALLOCATE"):
    if poisoned in INSTALLER[INSTALLER.index("SIGNED_ENTITLEMENTS_OUTPUT="):INSTALLER.index('say "Installing SDK-integrated Capture on the intended iPhone"')]:
        raise SystemExit(f"caller-controlled Apple verifier state leaked into custody block: {poisoned}")
'''
test_path.write_text(test, encoding="utf-8")
