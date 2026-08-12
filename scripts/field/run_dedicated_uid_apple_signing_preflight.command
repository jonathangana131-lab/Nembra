#!/bin/bash -p
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
unset BASH_ENV ENV CDPATH GIT_DIR GIT_WORK_TREE || true
hash -r
umask 077

# Validation-only exact-byte transport for the dedicated build-UID Apple signing
# feasibility probe. This command never runs xcodebuild, provisioning, private Tuya,
# device discovery/install, Bluetooth, or scooter behavior. It only executes the
# accepted Python oracle bytes under a root supervisor so that oracle can create and
# retire one fresh hidden UID/GID and ask that identity to sign a harmless local copy.

SCRIPT_PATH="scripts/field/run_dedicated_uid_apple_signing_preflight.command"
ORACLE_PATH="scripts/field/capture_dedicated_uid_apple_signing_preflight.py"
PRODUCTION_PARENT="c4996ea91cc3482ca8a8d661fd1436a2eee745df"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || fail "Dedicated-UID Apple signing preflight requires macOS."
FIELD_UID="$(/usr/bin/id -u)"
FIELD_GID="$(/usr/bin/id -g)"
[[ "$FIELD_UID" -gt 0 ]] || fail "Run this preflight as the ordinary field user, not root."
[[ "$#" == 3 ]] || fail "Usage: $0 <absolute-repository-root> <40-hex-accepted-validation-sha> <absolute-output-directory-outside-repository>"

REPOSITORY_ROOT="$1"
SOURCE_SHA="$(printf '%s' "$2" | /usr/bin/tr '[:upper:]' '[:lower:]')"
OUTPUT_DIR="$3"
[[ "$REPOSITORY_ROOT" == /* ]] || fail "Repository root must be absolute."
[[ "$OUTPUT_DIR" == /* ]] || fail "Output directory must be absolute."
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "Accepted validation SHA must be exactly 40 lowercase hex characters."
[[ -d "$REPOSITORY_ROOT/.git" && ! -L "$REPOSITORY_ROOT/.git" ]] || fail "Repository root does not contain one real Nembra Git metadata directory."
REPOSITORY_ABS="$(cd "$REPOSITORY_ROOT" && /bin/pwd -P)"
[[ "$REPOSITORY_ABS" == "$REPOSITORY_ROOT" ]] || fail "Repository root must already be one canonical absolute path."
case "$OUTPUT_DIR/" in
    "$REPOSITORY_ROOT/"*) fail "Receipt directory must remain outside the accepted repository." ;;
esac

GIT=(/usr/bin/git -C "$REPOSITORY_ROOT" -c core.hooksPath=/dev/null)
GIT_ENV=(/usr/bin/env -i PATH=/usr/bin:/bin HOME="$HOME" GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null)

HEAD_SHA="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse HEAD 2>/dev/null | /usr/bin/tr '[:upper:]' '[:lower:]')" || fail "Could not resolve repository HEAD."
[[ "$HEAD_SHA" == "$SOURCE_SHA" ]] || fail "Repository HEAD is not the exact accepted validation source."
[[ -z "$("${GIT_ENV[@]}" "${GIT[@]}" status --porcelain=v1 --untracked-files=all)" ]] || fail "Accepted validation checkout is dirty."
MERGE_BASE="$("${GIT_ENV[@]}" "${GIT[@]}" merge-base "$PRODUCTION_PARENT" "$SOURCE_SHA" 2>/dev/null | /usr/bin/tr '[:upper:]' '[:lower:]')" || fail "Could not bind validation source to the pinned production parent."
[[ "$MERGE_BASE" == "$PRODUCTION_PARENT" ]] || fail "Validation source is not descended from the pinned production parent."

SCRIPT_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse "$SOURCE_SHA:$SCRIPT_PATH" 2>/dev/null)" || fail "Accepted transport is absent from the exact Git tree."
ORACLE_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse "$SOURCE_SHA:$ORACLE_PATH" 2>/dev/null)" || fail "Accepted dedicated-UID oracle is absent from the exact Git tree."
[[ "$SCRIPT_BLOB" =~ ^[0-9a-f]{40}$ && "$ORACLE_BLOB" =~ ^[0-9a-f]{40}$ ]] || fail "Accepted Git blob identity is malformed."

EXECUTING_SCRIPT="$0"
if [[ "$EXECUTING_SCRIPT" != /* ]]; then
    EXECUTING_SCRIPT="$(/bin/pwd -P)/$EXECUTING_SCRIPT"
fi
CURRENT_SCRIPT_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" hash-object "$EXECUTING_SCRIPT" 2>/dev/null)" || fail "Could not fingerprint executing transport bytes."
[[ "$CURRENT_SCRIPT_BLOB" == "$SCRIPT_BLOB" ]] || fail "Executing transport bytes do not match the exact accepted Git object."

/usr/bin/sudo -n /usr/bin/true >/dev/null 2>&1 || fail "Noninteractive sudo is required only for the ephemeral dedicated-principal lifecycle."

/bin/mkdir -p "$OUTPUT_DIR"
/bin/chmod 700 "$OUTPUT_DIR"
[[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || fail "Receipt directory must be one real private directory."
OUTPUT_ABS="$(cd "$OUTPUT_DIR" && /bin/pwd -P)"
[[ "$OUTPUT_ABS" == "$OUTPUT_DIR" ]] || fail "Receipt directory must already be one canonical absolute path."
case "$OUTPUT_ABS/" in
    "$REPOSITORY_ROOT/"*) fail "Canonical receipt directory resolved inside the accepted repository." ;;
esac

PROBE_OUTPUT="$OUTPUT_DIR/probe-output.txt"
PROBE_RC_FILE="$OUTPUT_DIR/probe-return-code.txt"
MANIFEST="$OUTPUT_DIR/preflight-manifest.json"
: > "$PROBE_OUTPUT"
/bin/chmod 600 "$PROBE_OUTPUT"

# Root receives only the exact accepted oracle object bytes on stdin. It recomputes
# the Git blob identity before executing those in-memory bytes, then binds the same
# captured source into the fresh dedicated child. No mutable worktree Python path is
# reopened at either privileged or signing side-effect boundary.
ROOT_RUNNER="$(/bin/cat <<'PY'
import base64
import hashlib
import os
import sys

expected_blob, expected_head, field_uid, field_gid = sys.argv[1:]
raw = sys.stdin.buffer.read()
actual_blob = hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()
if actual_blob != expected_blob.lower():
    raise SystemExit("accepted dedicated signing oracle failed root Git-blob verification")
namespace = {
    "__name__": "nembra_dedicated_uid_signing_root",
    "__file__": "<accepted-dedicated-uid-signing-oracle>",
}
exec(
    compile(raw, "<accepted-dedicated-uid-signing-oracle>", "exec", dont_inherit=True),
    namespace,
)
namespace["SELF_SOURCE_B64"] = base64.b64encode(raw).decode("ascii")
raise SystemExit(namespace["root_probe"](expected_head.lower(), int(field_uid), int(field_gid)))
PY
)"

set +e
"${GIT_ENV[@]}" "${GIT[@]}" cat-file blob "$ORACLE_BLOB" | \
    /usr/bin/sudo -n /usr/bin/python3 -B -I -c "$ROOT_RUNNER" "$ORACLE_BLOB" "$SOURCE_SHA" "$FIELD_UID" "$FIELD_GID" \
    >"$PROBE_OUTPUT" 2>&1
PIPE_STATUS=("${PIPESTATUS[@]}")
set -e
GIT_RC="${PIPE_STATUS[0]}"
PROBE_RC="${PIPE_STATUS[1]}"
unset ROOT_RUNNER PIPE_STATUS
[[ "$GIT_RC" == 0 ]] || {
    : > "$PROBE_OUTPUT"
    printf '%s\n' 'ERROR: accepted oracle Git-object transport failed before privileged execution.' > "$PROBE_OUTPUT"
    PROBE_RC=91
}
printf '%s\n' "$PROBE_RC" > "$PROBE_RC_FILE"
/bin/chmod 600 "$PROBE_RC_FILE"

# Defense-in-depth public receipt redaction. The oracle emits classifications only;
# suppress the whole output if a raw identity label grammar somehow escapes.
if /usr/bin/grep -E 'Apple Development:[[:space:]]*[^<[:space:]]' "$PROBE_OUTPUT" >/dev/null 2>&1; then
    : > "$PROBE_OUTPUT"
    printf '%s\n' 'ERROR: preflight output suppressed because raw Apple identity text escaped.' > "$PROBE_OUTPUT"
    PROBE_RC=90
    printf '%s\n' "$PROBE_RC" > "$PROBE_RC_FILE"
fi

/usr/bin/python3 -B -I - "$MANIFEST" "$PROBE_OUTPUT" "$PROBE_RC" "$SOURCE_SHA" "$SCRIPT_BLOB" "$ORACLE_BLOB" "$PRODUCTION_PARENT" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

manifest, output_path, rc_raw, source_sha, script_blob, oracle_blob, production_parent = sys.argv[1:]
output = Path(output_path).read_text(encoding="utf-8", errors="replace")
rc = int(rc_raw)
record = {
    "schemaVersion": 1,
    "authority": "capture-dedicated-uid-apple-signing-feasibility-preflight-only",
    "exactValidationHead": source_sha.lower(),
    "exactProductionParent": production_parent.lower(),
    "acceptedTransportGitBlob": script_blob.lower(),
    "acceptedOracleGitBlob": oracle_blob.lower(),
    "probeReturnCode": rc,
    "successEvidencePresent": "NEMBRA_DEDICATED_UID_APPLE_SIGNING_JSON=" in output,
    "redEvidencePresent": "NEMBRA_DEDICATED_UID_APPLE_SIGNING_ERROR=" in output,
    "identityDetailsRedacted": True,
    "freshDedicatedPrincipalLifecycleExercised": True,
    "xcodebuildExercised": False,
    "automaticProvisioningExercised": False,
    "privateTuyaInputExercised": False,
    "deviceDiscoveryExercised": False,
    "deviceInstallExercised": False,
    "bluetoothExercised": False,
    "productionBytesChanged": False,
    "productionAcceptanceClaimed": False,
    "physicalAuthorityCreated": False,
    "probeOutputSHA256": hashlib.sha256(output.encode("utf-8")).hexdigest(),
}
Path(manifest).write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
/bin/chmod 600 "$MANIFEST"

(
    cd "$OUTPUT_DIR"
    /usr/bin/shasum -a 256 probe-output.txt probe-return-code.txt preflight-manifest.json > SHA256SUMS.txt
    /bin/chmod 600 SHA256SUMS.txt
)

/bin/cat "$PROBE_OUTPUT"
printf 'NEMBRA_DEDICATED_UID_APPLE_SIGNING_PREFLIGHT_RECEIPT=%s\n' "$OUTPUT_DIR"
exit "$PROBE_RC"
