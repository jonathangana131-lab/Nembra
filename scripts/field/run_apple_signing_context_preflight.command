#!/bin/bash
set -euo pipefail

# Validation-only field-Mac transport for the exact Apple signing-context oracle.
#
# This command does NOT bootstrap Tuya, run xcodebuild, provision/register a device,
# install/launch an app, enumerate CoreDevice, use Bluetooth, or touch the scooter.
# It only materializes exact accepted Git-object bytes for the #3152 signing oracle
# into a root-owned temporary execution subject, runs that oracle as the invoking
# field user, and seals a redacted local receipt.

ORACLE_PATH="scripts/ci/tests/test_capture_signed_app_field_uid_apple_development_signing.py"
SCRIPT_PATH="scripts/field/run_apple_signing_context_preflight.command"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

[[ "$(uname -s)" == "Darwin" ]] || fail "Apple signing-context preflight requires macOS."
[[ "${EUID:-$(id -u)}" -ne 0 ]] || fail "Run this preflight as the field user, not root. It invokes sudo only for exact-byte materialization and the oracle's isolated root supervisor."
[[ "$#" == 3 ]] || fail "Usage: $0 <absolute-repository-root> <40-hex-accepted-source-sha> <absolute-output-directory>"

REPOSITORY_ROOT="$1"
SOURCE_SHA="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
OUTPUT_DIR="$3"
[[ "$REPOSITORY_ROOT" == /* ]] || fail "Repository root must be absolute."
[[ "$OUTPUT_DIR" == /* ]] || fail "Output directory must be absolute."
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "Accepted source SHA must be exactly 40 lowercase hex characters."
[[ -d "$REPOSITORY_ROOT/.git" ]] || fail "Repository root does not contain the Nembra Git checkout."

GIT=(/usr/bin/git -C "$REPOSITORY_ROOT" -c core.hooksPath=/dev/null)
GIT_ENV=(env GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null)

HEAD_SHA="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse HEAD 2>/dev/null | tr '[:upper:]' '[:lower:]')" || fail "Could not resolve repository HEAD."
[[ "$HEAD_SHA" == "$SOURCE_SHA" ]] || fail "Repository HEAD is not the exact accepted preflight source. Checkout the accepted SHA and retry."
[[ -z "$("${GIT_ENV[@]}" "${GIT[@]}" status --porcelain=v1 --untracked-files=all)" ]] || fail "Accepted-source checkout is dirty. Preserve private/ignored inputs elsewhere and retry from a clean checkout."

SCRIPT_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse "$SOURCE_SHA:$SCRIPT_PATH" 2>/dev/null)" || fail "Field preflight is absent from the accepted Git tree."
ORACLE_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse "$SOURCE_SHA:$ORACLE_PATH" 2>/dev/null)" || fail "Apple signing oracle is absent from the accepted Git tree."
[[ "$SCRIPT_BLOB" =~ ^[0-9a-f]{40}$ && "$ORACLE_BLOB" =~ ^[0-9a-f]{40}$ ]] || fail "Accepted Git blob identity is malformed."

# Refuse a mutable-worktree wrapper. The shell has already loaded this file, but its
# bytes must still match the exact accepted Git object named by SOURCE_SHA.
EXECUTING_SCRIPT="$0"
if [[ "$EXECUTING_SCRIPT" != /* ]]; then
    EXECUTING_SCRIPT="$(pwd -P)/$EXECUTING_SCRIPT"
fi
CURRENT_SCRIPT_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" hash-object "$EXECUTING_SCRIPT" 2>/dev/null)" || fail "Could not fingerprint executing preflight bytes."
[[ "$CURRENT_SCRIPT_BLOB" == "$SCRIPT_BLOB" ]] || fail "Executing field-preflight bytes do not match the accepted Git object."

mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"
[[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || fail "Output directory must be one real private directory."
OUTPUT_ABS="$(cd "$OUTPUT_DIR" && pwd -P)"
[[ "$OUTPUT_ABS" == "$OUTPUT_DIR" ]] || fail "Output directory must already be one canonical absolute path."

ROOT_EXEC_DIR="$(/usr/bin/sudo -n /usr/bin/mktemp -d /private/tmp/nembra-apple-signing-preflight.XXXXXX)" || fail "Noninteractive sudo is required to materialize the exact root-owned oracle."
[[ "$ROOT_EXEC_DIR" == /private/tmp/nembra-apple-signing-preflight.* ]] || fail "Root execution directory escaped the expected /private/tmp namespace."
cleanup() {
    /usr/bin/sudo -n /bin/rm -rf -- "$ROOT_EXEC_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM
ORACLE_EXEC="$ROOT_EXEC_DIR/apple-signing-oracle.py"

# Feed only accepted Git-object bytes on stdin to a root verifier whose program arrives
# through -c. Do not combine a pipe with `python3 -`/heredoc: stdin is reserved solely
# for the accepted oracle blob. Root recomputes the Git object ID before publication.
ROOT_MATERIALIZER="$(/bin/cat <<'PY'
import hashlib
import os
from pathlib import Path
import stat
import sys

path = Path(sys.argv[1])
expected_blob = sys.argv[2].lower()
raw = sys.stdin.buffer.read()
actual_blob = hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()
if actual_blob != expected_blob:
    raise SystemExit("accepted oracle bytes failed root Git-blob verification")
if path.parent.is_symlink():
    raise SystemExit("root oracle parent must not be a symlink")
parent = path.parent.lstat()
if parent.st_uid != 0 or not stat.S_ISDIR(parent.st_mode):
    raise SystemExit("root oracle parent lost root directory custody")
os.chown(path.parent, 0, 0)
os.chmod(path.parent, 0o755)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o555)
try:
    with os.fdopen(fd, "wb", closefd=False) as handle:
        handle.write(raw)
        handle.flush()
        os.fsync(handle.fileno())
finally:
    os.close(fd)
os.chown(path, 0, 0)
os.chmod(path, 0o555)
info = path.lstat()
if info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o555 or not stat.S_ISREG(info.st_mode):
    raise SystemExit("root oracle publication metadata is invalid")
with path.open("rb") as handle:
    frozen = handle.read()
if frozen != raw:
    raise SystemExit("root oracle publication bytes changed")
PY
)"

"${GIT_ENV[@]}" "${GIT[@]}" cat-file blob "$ORACLE_BLOB" | \
    /usr/bin/sudo -n /usr/bin/python3 -B -I -c "$ROOT_MATERIALIZER" "$ORACLE_EXEC" "$ORACLE_BLOB"
unset ROOT_MATERIALIZER

[[ -f "$ORACLE_EXEC" && ! -L "$ORACLE_EXEC" ]] || fail "Root-owned accepted oracle was not materialized."
ORACLE_OWNER="$(/usr/bin/stat -f '%u:%g:%Lp' "$ORACLE_EXEC")" || fail "Could not inspect root-owned oracle metadata."
[[ "$ORACLE_OWNER" == "0:0:555" ]] || fail "Root-owned oracle metadata is not exact."

PROBE_OUTPUT="$OUTPUT_DIR/probe-output.txt"
PROBE_RC_FILE="$OUTPUT_DIR/probe-return-code.txt"
MANIFEST="$OUTPUT_DIR/preflight-manifest.json"
: > "$PROBE_OUTPUT"
chmod 600 "$PROBE_OUTPUT"

set +e
/usr/bin/python3 -B -I "$ORACLE_EXEC" >"$PROBE_OUTPUT" 2>&1
PROBE_RC=$?
set -e
printf '%s\n' "$PROBE_RC" > "$PROBE_RC_FILE"
chmod 600 "$PROBE_RC_FILE"

# The oracle is designed to emit only redacted identity hashes/counts. Fail closed if
# it accidentally emits a raw Apple Development label grammar anyway.
if /usr/bin/grep -E 'Apple Development:[^<[:space:]]' "$PROBE_OUTPUT" >/dev/null 2>&1; then
    : > "$PROBE_OUTPUT"
    printf '%s\n' 'ERROR: preflight output was suppressed because raw Apple identity text escaped the oracle.' > "$PROBE_OUTPUT"
    PROBE_RC=90
    printf '%s\n' "$PROBE_RC" > "$PROBE_RC_FILE"
fi

/usr/bin/python3 -B -I - "$MANIFEST" "$PROBE_OUTPUT" "$PROBE_RC" "$SOURCE_SHA" "$SCRIPT_BLOB" "$ORACLE_BLOB" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

manifest, output_path, rc_raw, source_sha, script_blob, oracle_blob = sys.argv[1:]
output = Path(output_path).read_text(encoding="utf-8", errors="replace")
rc = int(rc_raw)
record = {
    "schemaVersion": 1,
    "authority": "capture-field-apple-signing-context-preflight-only",
    "exactSourceSHA": source_sha.lower(),
    "acceptedPreflightGitBlob": script_blob.lower(),
    "acceptedOracleGitBlob": oracle_blob.lower(),
    "probeReturnCode": rc,
    "successEvidencePresent": "NEMBRA_FIELD_UID_APPLE_SIGNING_JSON=" in output,
    "redEvidencePresent": "NEMBRA_FIELD_UID_APPLE_SIGNING_ERROR=" in output,
    "identityDetailsRedacted": True,
    "tuyaBootstrapExercised": False,
    "privateTuyaInputExercised": False,
    "xcodebuildExercised": False,
    "automaticProvisioningExercised": False,
    "deviceDiscoveryExercised": False,
    "coreDeviceExercised": False,
    "deviceInstallExercised": False,
    "bluetoothExercised": False,
    "physicalAuthorityCreated": False,
    "probeOutputSHA256": hashlib.sha256(output.encode("utf-8")).hexdigest(),
}
Path(manifest).write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
chmod 600 "$MANIFEST"

(
    cd "$OUTPUT_DIR"
    /usr/bin/shasum -a 256 probe-output.txt probe-return-code.txt preflight-manifest.json > SHA256SUMS.txt
    chmod 600 SHA256SUMS.txt
)

cat "$PROBE_OUTPUT"
printf 'NEMBRA_FIELD_APPLE_SIGNING_PREFLIGHT_RECEIPT=%s\n' "$OUTPUT_DIR"
exit "$PROBE_RC"
