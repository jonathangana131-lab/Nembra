#!/usr/bin/env python3
from pathlib import Path

path = Path("scripts/field/install_one_time_capture.command")
source = path.read_text(encoding="utf-8")

replacements = (
    ('PRIVATE_DEVICE_RUNNER_BASE64="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git cat-file blob', 'PRIVATE_DEVICE_RUNNER="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git cat-file blob'),
    ('[[ -n "$PRIVATE_DEVICE_RUNNER_BASE64" ]] || die "Captured private intended-device reader is empty."', '[[ -n "$PRIVATE_DEVICE_RUNNER" ]] || die "Captured private intended-device reader is empty."'),
    ('printf \'%s\' "$PRIVATE_DEVICE_RUNNER_BASE64" | /usr/bin/base64 -D', 'printf \'%s\' "$PRIVATE_DEVICE_RUNNER" | /usr/bin/base64 -D'),
    ('/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER_BASE64" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT"', '/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT"'),
    ('unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 PRIVATE_DEVICE_RUNNER_BASE64 PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB PRIVATE_DEVICE_RUNNER_RELATIVE || true', 'unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 PRIVATE_DEVICE_RUNNER PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB PRIVATE_DEVICE_RUNNER_RELATIVE || true'),
)

for old, new in replacements:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one runner transport marker, found {count}: {old}")
    source = source.replace(old, new, 1)

if 'PRIVATE_DEVICE_RUNNER_BASE64' in source:
    raise SystemExit("obsolete PRIVATE_DEVICE_RUNNER_BASE64 marker remains")
if 'PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"' in source:
    raise SystemExit("mutable private-device runner pathname assignment reappeared")

path.write_text(source, encoding="utf-8")
