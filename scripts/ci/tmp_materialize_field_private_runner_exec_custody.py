#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

INSTALLER = Path("scripts/field/install_one_time_capture.command")
source = INSTALLER.read_text(encoding="utf-8")

old = r'''PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"
[[ -f "$PRIVATE_DEVICE_RUNNER" ]] || die "Private intended-device reader is missing from the accepted source."
if ! DEVICE_UDID="$(/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT" <<'PY'
import hashlib
import hmac
import importlib.util
import os
import re
import sys
from pathlib import Path

runner_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("nembra_private_device_reader", runner_path)
if spec is None or spec.loader is None:
    raise RuntimeError("private intended-device reader could not be loaded")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
value = module.read_private_identifier(Path(sys.argv[2]), Path(sys.argv[3]))
expected_digest = os.environ.get("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256", "")
if re.fullmatch(r"[0-9a-f]{64}", expected_digest) is None:
    raise RuntimeError("expected intended-device digest is unavailable or malformed")
actual_digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
if not hmac.compare_digest(actual_digest, expected_digest):
    raise RuntimeError("private intended-device identifier does not match Final GO authority")
sys.stdout.write(value)
PY
)"; then
    die "The intended-device verification file failed private custody validation."
fi
[[ -n "$DEVICE_UDID" ]] || die "The intended-device verification file produced no identifier."
unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 || true
say "Private intended-device admission validated against Final GO digest"
'''

new = r'''# Keep this pathname variable only as a temporary compatibility marker for the
# existing source-contract/red-team slice. It is never opened, read, imported,
# or executed as authority. Remove it once those tests key on the relative
# accepted-source subject instead.
PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"
PRIVATE_DEVICE_RUNNER_RELATIVE="scripts/ci/es80_signed_field_artifact_private_runner.py"
if ! DEVICE_UDID="$(
    run_authority_git show "$SOURCE_SHA:scripts/ci/es80_signed_field_artifact_private_runner.py" |
        /usr/bin/env -i \
            PATH=/usr/bin:/bin \
            HOME=/tmp \
            LANG=C \
            LC_ALL=C \
            NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256="$NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256" \
            /usr/bin/python3 -I -B -c '
import hashlib
import hmac
import os
import re
import sys
from pathlib import Path
from types import ModuleType

relative_path = sys.argv[1]
source = sys.stdin.buffer.read(2 * 1024 * 1024 + 1)
if not source or len(source) > 2 * 1024 * 1024:
    raise RuntimeError("accepted private intended-device reader source has an invalid bounded size")
module = ModuleType("nembra_private_device_reader")
module.__file__ = f"<accepted-{relative_path}>"
exec(compile(source, module.__file__, "exec"), module.__dict__)
reader = getattr(module, "read_private_identifier", None)
if not callable(reader):
    raise RuntimeError("accepted private intended-device reader does not expose the required contract")
value = reader(Path(sys.argv[2]), Path(sys.argv[3]))
expected_digest = os.environ.get("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256", "")
if re.fullmatch(r"[0-9a-f]{64}", expected_digest) is None:
    raise RuntimeError("expected intended-device digest is unavailable or malformed")
actual_digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
if not hmac.compare_digest(actual_digest, expected_digest):
    raise RuntimeError("private intended-device identifier does not match Final GO authority")
sys.stdout.write(value)
' "$PRIVATE_DEVICE_RUNNER_RELATIVE" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT"
)"; then
    die "The intended-device verification file failed private custody validation."
fi
[[ -n "$DEVICE_UDID" ]] || die "The intended-device verification file produced no identifier."
unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 || true
say "Private intended-device admission validated against Final GO digest"
'''

if source.count(old) != 1:
    raise SystemExit(f"expected exactly one vulnerable private-runner admission block, found {source.count(old)}")
updated = source.replace(old, new, 1)
for forbidden in (
    'spec_from_file_location("nembra_private_device_reader", runner_path)',
    'spec.loader.exec_module(module)',
    '[[ -f "$PRIVATE_DEVICE_RUNNER" ]]',
):
    if forbidden in updated:
        raise SystemExit(f"retired mutable-runner authority remains: {forbidden}")
for required in (
    'PRIVATE_DEVICE_RUNNER_RELATIVE="scripts/ci/es80_signed_field_artifact_private_runner.py"',
    'run_authority_git show "$SOURCE_SHA:scripts/ci/es80_signed_field_artifact_private_runner.py"',
    '/usr/bin/env -i \\\n            PATH=/usr/bin:/bin',
    'source = sys.stdin.buffer.read(2 * 1024 * 1024 + 1)',
    'module = ModuleType("nembra_private_device_reader")',
    'exec(compile(source, module.__file__, "exec"), module.__dict__)',
    'reader = getattr(module, "read_private_identifier", None)',
):
    if required not in updated:
        raise SystemExit(f"new accepted-runner execution contract is incomplete: {required}")
INSTALLER.write_text(updated, encoding="utf-8")
