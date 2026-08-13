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

# Git remains a byte transport only. The externally supplied accepted commit name
# is never trusted as an object lookup result by itself: authority-bearing commit
# and tree bytes are bounded-captured and independently re-hashed before their
# child OIDs are admitted. This closes caller-owned pack-index/name aliasing.
GIT=(/usr/bin/git --git-dir="$GIT_DIR_ABS" --work-tree="$REPOSITORY_ROOT" -c core.hooksPath=/dev/null)
GIT_ENV=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0)

HEAD_SHA="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse HEAD 2>/dev/null | tr '[:upper:]' '[:lower:]')" || fail "Could not resolve repository HEAD."
[[ "$HEAD_SHA" == "$SOURCE_SHA" ]] || fail "Repository HEAD is not the exact accepted preflight source. Checkout the accepted SHA and retry."
[[ -z "$("${GIT_ENV[@]}" "${GIT[@]}" status --porcelain=v1 --untracked-files=all)" ]] || fail "Accepted-source checkout is dirty. Preserve private/ignored inputs elsewhere and retry from a clean checkout."

OBJECT_RESOLVER="$(/bin/cat <<'PY'
import hashlib
import os
import re
import subprocess
import sys

MAX_COMMIT_BYTES = 4 * 1024 * 1024
MAX_TREE_BYTES = 16 * 1024 * 1024
MAX_TREE_DEPTH = 64
OID = re.compile(r"^[0-9a-f]{40}$")

git_dir, source_sha, *paths = sys.argv[1:]
source_sha = source_sha.lower()
if not OID.fullmatch(source_sha):
    raise SystemExit("accepted source SHA is not canonical SHA-1")
if len(paths) != 3 or any(not path or path.startswith("/") or ".." in path.split("/") for path in paths):
    raise SystemExit("accepted helper path contract is invalid")

environment = {
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "LC_ALL": "C",
    "GIT_NO_REPLACE_OBJECTS": "1",
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_OPTIONAL_LOCKS": "0",
}

def object_oid(object_type, payload):
    header = object_type.encode("ascii") + b" " + str(len(payload)).encode("ascii") + b"\0"
    return hashlib.sha1(header + payload).hexdigest()

def capture(object_type, oid, limit):
    if object_type not in {"commit", "tree"} or not OID.fullmatch(oid) or limit <= 0:
        raise SystemExit("accepted Git object capture contract is invalid")
    process = subprocess.Popen(
        ["/usr/bin/git", f"--git-dir={git_dir}", "cat-file", object_type, oid],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env=environment,
    )
    if process.stdout is None:
        process.kill()
        process.wait()
        raise SystemExit("accepted Git object capture pipe unavailable")
    payload = process.stdout.read(limit + 1)
    if len(payload) > limit:
        process.kill()
        process.wait()
        raise SystemExit("accepted Git object exceeds bounded capture limit")
    returncode = process.wait()
    process.stdout.close()
    if returncode != 0:
        raise SystemExit("accepted Git object capture failed")
    actual = object_oid(object_type, payload)
    if actual != oid:
        raise SystemExit("accepted Git object lookup returned bytes outside accepted identity")
    return payload

def commit_tree(commit_payload):
    headers = commit_payload.split(b"\n\n", 1)[0]
    tree_oids = [line[5:] for line in headers.splitlines() if line.startswith(b"tree ")]
    if len(tree_oids) != 1:
        raise SystemExit("accepted commit must carry exactly one tree header")
    try:
        tree_oid = tree_oids[0].decode("ascii").lower()
    except UnicodeDecodeError as error:
        raise SystemExit("accepted commit tree identity is not ASCII") from error
    if not OID.fullmatch(tree_oid):
        raise SystemExit("accepted commit tree identity is malformed")
    return tree_oid

def tree_entries(payload):
    entries = []
    offset = 0
    while offset < len(payload):
        space = payload.find(b" ", offset)
        nul = payload.find(b"\0", space + 1) if space > offset else -1
        if space <= offset or nul <= space + 1 or nul + 21 > len(payload):
            raise SystemExit("accepted tree object is malformed")
        mode = payload[offset:space]
        name = payload[space + 1:nul]
        if not name or name in {b".", b".."} or b"/" in name:
            raise SystemExit("accepted tree contains unsafe path component")
        oid = payload[nul + 1:nul + 21].hex()
        entries.append((mode, name, oid))
        offset = nul + 21
    return entries

def resolve_path(root_tree_oid, path):
    components = [component.encode("utf-8") for component in path.split("/")]
    tree_oid = root_tree_oid
    for depth, component in enumerate(components):
        if depth >= MAX_TREE_DEPTH:
            raise SystemExit("accepted helper path exceeds tree-depth limit")
        payload = capture("tree", tree_oid, MAX_TREE_BYTES)
        matches = [entry for entry in tree_entries(payload) if entry[1] == component]
        if len(matches) != 1:
            raise SystemExit("accepted helper path is absent or ambiguous")
        mode, _, oid = matches[0]
        is_last = depth == len(components) - 1
        if is_last:
            if mode not in {b"100644", b"100755"} or not OID.fullmatch(oid):
                raise SystemExit("accepted helper leaf is not one regular Git blob")
            return oid
        if mode != b"40000" or not OID.fullmatch(oid):
            raise SystemExit("accepted helper path traverses a non-tree object")
        tree_oid = oid
    raise SystemExit("accepted helper path resolution failed")

commit_payload = capture("commit", source_sha, MAX_COMMIT_BYTES)
root_tree_oid = commit_tree(commit_payload)
resolved = [resolve_path(root_tree_oid, path) for path in paths]
print("\t".join(resolved))
PY
)"

RESOLVED_BLOBS="$(/usr/bin/python3 -B -I -c "$OBJECT_RESOLVER" "$GIT_DIR_ABS" "$SOURCE_SHA" "$SCRIPT_PATH" "$ORACLE_PATH" "$SEALER_PATH")" || fail "Accepted commit/tree object chain failed independent verification."
unset OBJECT_RESOLVER
IFS=$'\t' read -r SCRIPT_BLOB ORACLE_BLOB SEALER_BLOB <<< "$RESOLVED_BLOBS"
unset RESOLVED_BLOBS
[[ "$SCRIPT_BLOB" =~ ^[0-9a-f]{40}$ && "$ORACLE_BLOB" =~ ^[0-9a-f]{40}$ && "$SEALER_BLOB" =~ ^[0-9a-f]{40}$ ]] || fail "Verified accepted Git blob identity is malformed."

EXECUTING_SCRIPT="$0"
if [[ "$EXECUTING_SCRIPT" != /* ]]; then
    EXECUTING_SCRIPT="$(pwd -P)/$EXECUTING_SCRIPT"
fi
CURRENT_SCRIPT_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" hash-object "$EXECUTING_SCRIPT" 2>/dev/null)" || fail "Could not fingerprint executing preflight bytes."
[[ "$CURRENT_SCRIPT_BLOB" == "$SCRIPT_BLOB" ]] || fail "Executing field-preflight bytes do not match the independently verified accepted Git object."

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
