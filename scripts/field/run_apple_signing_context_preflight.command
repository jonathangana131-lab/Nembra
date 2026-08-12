#!/bin/bash
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

# Validation-only field-Mac transport for the exact Apple signing-context oracle.
#
# This command does NOT bootstrap Tuya, run xcodebuild, provision/register a device,
# install/launch an app, enumerate CoreDevice, use Bluetooth, or touch the scooter.
# Accepted oracle + receipt-sealer bytes are root-materialized from exact Git objects.
# The oracle still executes as the real field identity, while the root sealer captures
# its output directly and publishes a canonical non-caller-writable receipt.

ORACLE_PATH="scripts/ci/tests/test_capture_signed_app_field_uid_apple_development_signing.py"
SEALER_PATH="scripts/ci/capture_apple_signing_preflight_receipt_seal.py"
SCRIPT_PATH="scripts/field/run_apple_signing_context_preflight.command"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

[[ "$(uname -s)" == "Darwin" ]] || fail "Apple signing-context preflight requires macOS."
[[ "${EUID:-$(id -u)}" -ne 0 ]] || fail "Run this preflight as the field user, not root. It invokes sudo only for exact-byte materialization and the isolated receipt supervisor."
[[ "$#" == 3 ]] || fail "Usage: $0 <absolute-repository-root> <40-hex-accepted-source-sha> <absolute-new-receipt-directory-under-a-root-owned-parent>"

REPOSITORY_ROOT="$1"
SOURCE_SHA="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
OUTPUT_DIR="$3"
[[ "$REPOSITORY_ROOT" == /* ]] || fail "Repository root must be absolute."
[[ "$OUTPUT_DIR" == /* ]] || fail "Receipt directory must be absolute."
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "Accepted source SHA must be exactly 40 lowercase hex characters."
[[ -d "$REPOSITORY_ROOT/.git" && ! -L "$REPOSITORY_ROOT/.git" ]] || fail "Repository root must contain one real Nembra .git directory."
REPOSITORY_ABS="$(cd "$REPOSITORY_ROOT" && pwd -P)"
[[ "$REPOSITORY_ABS" == "$REPOSITORY_ROOT" ]] || fail "Repository root must already be one canonical absolute path."
GIT_DIR_ABS="$(cd "$REPOSITORY_ROOT/.git" && pwd -P)"
[[ "$GIT_DIR_ABS" == "$REPOSITORY_ROOT/.git" ]] || fail "Repository .git directory must already be one canonical real path."

[[ ! -e "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || fail "Canonical receipt path must not pre-exist."
OUTPUT_PARENT="$(/usr/bin/dirname "$OUTPUT_DIR")"
OUTPUT_NAME="$(/usr/bin/basename "$OUTPUT_DIR")"
[[ -n "$OUTPUT_NAME" && "$OUTPUT_NAME" != "." && "$OUTPUT_NAME" != ".." ]] || fail "Canonical receipt needs one named child path."
[[ -d "$OUTPUT_PARENT" && ! -L "$OUTPUT_PARENT" ]] || fail "Canonical receipt parent must already exist as one real directory."
OUTPUT_PARENT_ABS="$(cd "$OUTPUT_PARENT" && pwd -P)"
[[ "$OUTPUT_PARENT_ABS" == "$OUTPUT_PARENT" ]] || fail "Canonical receipt parent must already be one canonical real path."
[[ "$OUTPUT_PARENT_ABS/$OUTPUT_NAME" == "$OUTPUT_DIR" ]] || fail "Canonical receipt path must not contain aliases or traversal."
case "$OUTPUT_DIR/" in
    "$REPOSITORY_ROOT/"*) fail "Canonical receipt must remain outside the accepted repository." ;;
esac

# Git authority is explicitly fenced from caller GIT_* state and bound to this one
# real checkout directory. The accepted source SHA and exact loaded wrapper bytes then
# name the oracle/sealer objects that root is permitted to execute.
GIT=(/usr/bin/git --git-dir="$GIT_DIR_ABS" --work-tree="$REPOSITORY_ROOT" -c core.hooksPath=/dev/null)
GIT_ENV=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0)

HEAD_SHA="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse HEAD 2>/dev/null | tr '[:upper:]' '[:lower:]')" || fail "Could not resolve repository HEAD."
[[ "$HEAD_SHA" == "$SOURCE_SHA" ]] || fail "Repository HEAD is not the exact accepted preflight source. Checkout the accepted SHA and retry."
[[ -z "$("${GIT_ENV[@]}" "${GIT[@]}" status --porcelain=v1 --untracked-files=all)" ]] || fail "Accepted-source checkout is dirty. Preserve private/ignored inputs elsewhere and retry from a clean checkout."

SCRIPT_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse "$SOURCE_SHA:$SCRIPT_PATH" 2>/dev/null)" || fail "Field preflight is absent from the accepted Git tree."
ORACLE_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse "$SOURCE_SHA:$ORACLE_PATH" 2>/dev/null)" || fail "Apple signing oracle is absent from the accepted Git tree."
SEALER_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse "$SOURCE_SHA:$SEALER_PATH" 2>/dev/null)" || fail "Apple signing receipt sealer is absent from the accepted Git tree."
[[ "$SCRIPT_BLOB" =~ ^[0-9a-f]{40}$ && "$ORACLE_BLOB" =~ ^[0-9a-f]{40}$ && "$SEALER_BLOB" =~ ^[0-9a-f]{40}$ ]] || fail "Accepted Git blob identity is malformed."

EXECUTING_SCRIPT="$0"
if [[ "$EXECUTING_SCRIPT" != /* ]]; then
    EXECUTING_SCRIPT="$(pwd -P)/$EXECUTING_SCRIPT"
fi
CURRENT_SCRIPT_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" hash-object "$EXECUTING_SCRIPT" 2>/dev/null)" || fail "Could not fingerprint executing preflight bytes."
[[ "$CURRENT_SCRIPT_BLOB" == "$SCRIPT_BLOB" ]] || fail "Executing field-preflight bytes do not match the accepted Git object."

ROOT_EXEC_DIR="$(/usr/bin/sudo -n /usr/bin/mktemp -d /private/tmp/nembra-apple-signing-preflight.XXXXXX)" || fail "Noninteractive sudo is required for exact root-owned execution subjects."
[[ "$ROOT_EXEC_DIR" == /private/tmp/nembra-apple-signing-preflight.* ]] || fail "Root execution directory escaped the expected /private/tmp namespace."
cleanup() {
    /usr/bin/sudo -n /bin/rm -rf -- "$ROOT_EXEC_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM
ORACLE_EXEC="$ROOT_EXEC_DIR/apple-signing-oracle.py"
SEALER_EXEC="$ROOT_EXEC_DIR/apple-signing-receipt-sealer.py"

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
    raise SystemExit("accepted helper bytes failed root Git-blob verification")
if path.parent.is_symlink():
    raise SystemExit("root helper parent must not be a symlink")
parent = path.parent.lstat()
if parent.st_uid != 0 or not stat.S_ISDIR(parent.st_mode):
    raise SystemExit("root helper parent lost root directory custody")
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
if info.st_uid != 0 or info.st_gid != 0 or stat.S_IMODE(info.st_mode) != 0o555 or not stat.S_ISREG(info.st_mode):
    raise SystemExit("root helper publication metadata is invalid")
with path.open("rb") as handle:
    frozen = handle.read()
if frozen != raw:
    raise SystemExit("root helper publication bytes changed")
PY
)"

materialize_blob() {
    local blob="$1"
    local destination="$2"
    "${GIT_ENV[@]}" "${GIT[@]}" cat-file blob "$blob" | \
        /usr/bin/sudo -n /usr/bin/python3 -B -I -c "$ROOT_MATERIALIZER" "$destination" "$blob"
}
materialize_blob "$ORACLE_BLOB" "$ORACLE_EXEC"
materialize_blob "$SEALER_BLOB" "$SEALER_EXEC"
unset ROOT_MATERIALIZER

for subject in "$ORACLE_EXEC" "$SEALER_EXEC"; do
    [[ -f "$subject" && ! -L "$subject" ]] || fail "Root-owned accepted helper was not materialized."
    OWNER="$(/usr/bin/stat -f '%u:%g:%Lp' "$subject")" || fail "Could not inspect root-owned helper metadata."
    [[ "$OWNER" == "0:0:555" ]] || fail "Root-owned accepted helper metadata is not exact."
done

FIELD_UID="$(/usr/bin/id -u)"
FIELD_GID="$(/usr/bin/id -g)"
FIELD_USER="$(/usr/bin/id -un)"
[[ "$FIELD_UID" -gt 0 && "$FIELD_GID" -gt 0 ]] || fail "Field identity must be non-root."
FIELD_GROUPS_JSON="$(/usr/bin/python3 -B -I -c 'import json, os; print(json.dumps(sorted({int(g) for g in os.getgroups() if int(g) != os.getgid()})))')" || fail "Could not capture exact active field supplementary groups."

set +e
/usr/bin/sudo -n /usr/bin/python3 -B -I "$SEALER_EXEC" \
    --oracle "$ORACLE_EXEC" \
    --oracle-blob "$ORACLE_BLOB" \
    --source-sha "$SOURCE_SHA" \
    --script-blob "$SCRIPT_BLOB" \
    --output-dir "$OUTPUT_DIR" \
    --field-uid "$FIELD_UID" \
    --field-gid "$FIELD_GID" \
    --field-user "$FIELD_USER" \
    --field-groups-json "$FIELD_GROUPS_JSON"
PROBE_RC=$?
set -e

# The sealer itself publishes/prints only the root-captured, redacted evidence plus
# the canonical receipt path. Its return code remains the signing oracle verdict.
exit "$PROBE_RC"
