from pathlib import Path

installer_path = Path("scripts/field/install_one_time_capture.command")
installer = installer_path.read_text()
old = "| /usr/bin/python3 -I -c '"
new = "| /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '"
count = installer.count(old)
if count < 2:
    raise SystemExit(f"expected at least two entitlement/profile parser pipelines, found {count}")
# Restrict replacement to the Apple entitlement custody block only.
start = installer.index("SIGNED_ENTITLEMENTS_OUTPUT=")
end = installer.index('say "Installing SDK-integrated Capture on the intended iPhone"', start)
block = installer[start:end]
if block.count(old) != 2:
    raise SystemExit(f"expected exactly two Apple custody parser pipelines, found {block.count(old)}")
block = block.replace(old, new)
installer = installer[:start] + block + installer[end:]
installer_path.write_text(installer)

test_path = Path("scripts/ci/tests/test_capture_apple_signin_field_entitlement_custody.py")
test = test_path.read_text()
test = test.replace(
    "'/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i \"$BUILT_PROFILE\"',\n",
    "'/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security cms -D -i \"$BUILT_PROFILE\"',\n    \"| /usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '\",\n",
)
old_footer = '''# Apple verification processes must not inherit caller-controlled startup/configuration state.\nfor poisoned in ("DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "PYTHONPATH", "CODESIGN_ALLOCATE"):\n    if poisoned in INSTALLER[INSTALLER.index("SIGNED_ENTITLEMENTS_OUTPUT="):INSTALLER.index('say "Installing SDK-integrated Capture on the intended iPhone"')]:\n        raise SystemExit(f"caller-controlled Apple verifier state leaked into custody block: {poisoned}")\n'''
new_footer = '''# Every external process in the Apple entitlement custody block runs from a closed startup environment.\ncustody = INSTALLER[INSTALLER.index("SIGNED_ENTITLEMENTS_OUTPUT="):INSTALLER.index('say "Installing SDK-integrated Capture on the intended iPhone"')]\nif custody.count("/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/python3 -I -c '") != 2:\n    raise SystemExit("both Apple plist parsers must run under a closed startup environment")\nif custody.count("/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/codesign") != 1:\n    raise SystemExit("codesign entitlement inspection must run under a closed startup environment")\nif custody.count("/usr/bin/env -i PATH=/usr/bin:/bin /usr/bin/security") != 1:\n    raise SystemExit("profile inspection must run under a closed startup environment")\nfor poisoned in ("DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH", "PYTHONPATH", "CODESIGN_ALLOCATE"):\n    if poisoned in custody:\n        raise SystemExit(f"caller-controlled Apple verifier state leaked into custody block: {poisoned}")\n'''
if old_footer not in test:
    raise SystemExit("expected Apple verifier environment footer missing")
test = test.replace(old_footer, new_footer)
test_path.write_text(test)
