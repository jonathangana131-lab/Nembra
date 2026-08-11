#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
REGRESSION = ROOT / "scripts/ci/tests/test_capture_field_private_runner_execution_authority_red_team.py"
BRANCH = "repair/v14-field-private-runner-execution-sol-20260811"
EXPECTED_INSTALLER_BLOB = "b13144cac129f735d9c433c885d4963c501fc28d"


def run(*argv: str) -> str:
    return subprocess.check_output(argv, cwd=ROOT, text=True).strip()


if run("git", "hash-object", INSTALLER.relative_to(ROOT).as_posix()) != EXPECTED_INSTALLER_BLOB:
    raise SystemExit("refusing stale installer materialization")

source = INSTALLER.read_text(encoding="utf-8")
start_marker = 'PRIVATE_DEVICE_RUNNER="$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py"'
end_marker = 'say "Private intended-device admission validated against Final GO digest"'
if source.count(start_marker) != 1:
    raise SystemExit("legacy private runner execution seam is missing or duplicated")
start = source.index(start_marker)
end = source.index(end_marker, start) + len(end_marker)

replacement = r'''PRIVATE_DEVICE_RUNNER_RELATIVE="scripts/ci/es80_signed_field_artifact_private_runner.py"
PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB="$(run_authority_git rev-parse "$SOURCE_SHA:$PRIVATE_DEVICE_RUNNER_RELATIVE" 2>/dev/null)" || \
    die "Private intended-device reader is missing from the exact accepted Git tree."
[[ "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB" =~ ^[0-9a-f]{40}$ ]] || die "Private intended-device reader Git blob identity is malformed."
PRIVATE_DEVICE_RUNNER="$(run_authority_git show "$SOURCE_SHA:$PRIVATE_DEVICE_RUNNER_RELATIVE" | /usr/bin/base64 | /usr/bin/tr -d '\r\n')" || \
    die "Could not capture the private intended-device reader from exact accepted Git bytes."
[[ -n "$PRIVATE_DEVICE_RUNNER" ]] || die "Captured private intended-device reader is empty."
if ! DEVICE_UDID="$(/usr/bin/python3 -I -B - "$PRIVATE_DEVICE_RUNNER" "$PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT" <<'PY'
import base64
import hashlib
import hmac
import os
import re
import sys
from pathlib import Path

runner_source = base64.b64decode(sys.argv[1], validate=True)
expected_blob = sys.argv[2]
actual_blob = hashlib.sha1(
    b"blob " + str(len(runner_source)).encode("ascii") + b"\0" + runner_source
).hexdigest()
if not hmac.compare_digest(actual_blob, expected_blob):
    raise RuntimeError("captured private intended-device reader does not match the accepted Git blob")
runner_namespace = {
    "__name__": "nembra_private_device_reader",
    "__file__": "<accepted-private-device-runner>",
}
exec(
    compile(runner_source, "<accepted-private-device-runner>", "exec", dont_inherit=True),
    runner_namespace,
)
reader = runner_namespace.get("read_private_identifier")
if not callable(reader):
    raise RuntimeError("accepted private intended-device reader does not expose read_private_identifier")
value = reader(Path(sys.argv[3]), Path(sys.argv[4]))
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
unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256 PRIVATE_DEVICE_RUNNER PRIVATE_DEVICE_RUNNER_ACCEPTED_BLOB PRIVATE_DEVICE_RUNNER_RELATIVE || true
say "Private intended-device admission validated against Final GO digest"'''

INSTALLER.write_text(source[:start] + replacement + source[end:], encoding="utf-8")

subprocess.run(["/bin/bash", "-n", str(INSTALLER)], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/python3", "-m", "py_compile", str(REGRESSION)], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/python3", str(REGRESSION)], cwd=ROOT, check=True)
subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)

materialized = INSTALLER.read_text(encoding="utf-8")
required = (
    'run_authority_git rev-parse "$SOURCE_SHA:$PRIVATE_DEVICE_RUNNER_RELATIVE"',
    'run_authority_git show "$SOURCE_SHA:$PRIVATE_DEVICE_RUNNER_RELATIVE"',
    'base64.b64decode(sys.argv[1], validate=True)',
    'compile(runner_source, "<accepted-private-device-runner>", "exec", dont_inherit=True)',
)
for marker in required:
    if marker not in materialized:
        raise SystemExit(f"missing repaired runner custody marker: {marker}")
for forbidden in (
    'spec_from_file_location("nembra_private_device_reader", runner_path)',
    'spec.loader.exec_module(module)',
):
    if forbidden in materialized[start:start + len(replacement) + 256]:
        raise SystemExit(f"mutable runner execution survived repair: {forbidden}")

subprocess.run(["git", "add", str(INSTALLER.relative_to(ROOT))], cwd=ROOT, check=True)
subprocess.run(["git", "diff", "--cached", "--check"], cwd=ROOT, check=True)
subprocess.run(["git", "config", "user.name", "nembra-sol-bot"], cwd=ROOT, check=True)
subprocess.run(["git", "config", "user.email", "nembra-sol-bot@users.noreply.github.com"], cwd=ROOT, check=True)
subprocess.run(["git", "commit", "-m", "Bind field private runner to accepted Git bytes"], cwd=ROOT, check=True)
subprocess.run(["git", "push", "origin", f"HEAD:{BRANCH}"], cwd=ROOT, check=True)
