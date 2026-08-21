#!/bin/bash -p
set -euo pipefail

if [[ $- != *p* ]]; then
  builtin printf '%s\n' 'ERROR: run this command directly; imported Bash startup state must remain disabled.' >&2
  exit 2
fi
set +x
PATH="/usr/bin:/bin:/usr/sbin:/sbin"; export PATH
unset BASH_ENV ENV CDPATH GLOBIGNORE XCODE_XCCONFIG_FILE OTHER_SWIFT_FLAGS SWIFT_ACTIVE_COMPILATION_CONDITIONS || true
umask 077

# Git-derived provenance must come only from this checkout. Reject inherited repository/object/config
# steering before the first Git read, then pin the remaining global/system/replace-object behavior.
for inherited_git_name in \
  GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
  GIT_INDEX_FILE GIT_REPLACE_REF_BASE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CONFIG_SYSTEM \
  GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_NO_REPLACE_OBJECTS; do
  if [[ -n "${!inherited_git_name+x}" ]]; then
    builtin printf 'ERROR: inherited %s is not allowed for field transport provenance.\n' "$inherited_git_name" >&2
    exit 1
  fi
done
while IFS='=' read -r inherited_git_name _; do
  case "$inherited_git_name" in
    GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*)
      builtin printf 'ERROR: inherited %s is not allowed for field transport provenance.\n' "$inherited_git_name" >&2
      exit 1
      ;;
  esac
done < <(/usr/bin/env)
GIT_NO_REPLACE_OBJECTS=1; export GIT_NO_REPLACE_OBJECTS
GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_NOSYSTEM
GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_GLOBAL

ROOT="$(cd "$(/usr/bin/dirname "$0")/../.." && /bin/pwd -P)"
TRANSPORT_RELATIVE_PATH="scripts/field/transfer_field_authorization.command"
CONTRACT_RELATIVE_PATH="scripts/ci/xcode27_devicectl_manifest_transport_contract.sh"
BUNDLE_ID="com.jonathangana131.nembra.capturelearn"
DOMAIN_TYPE="appDataContainer"
FIELD_DIRECTORY="Library/Application Support/NembraCapture/FieldAuthorization"
MANIFEST_INCOMING_REMOTE="$FIELD_DIRECTORY/retained-install-manifest.incoming"
MANIFEST_COMMIT_REMOTE="$FIELD_DIRECTORY/retained-install-manifest.commit"
RENDEZVOUS_REMOTE="$FIELD_DIRECTORY/signer-rendezvous.json"
ENVELOPE_INCOMING_REMOTE="$FIELD_DIRECTORY/authorization-envelope.incoming"
ENVELOPE_COMMIT_REMOTE="$FIELD_DIRECTORY/authorization-envelope.commit"
MANIFEST_MAX_BYTES=16384
RENDEZVOUS_MAX_BYTES=4096
ENVELOPE_MAX_BYTES=32768
COMMIT_RECORD_BYTES=65

say() { builtin printf '\n==> %s\n' "$*"; }
die() { builtin printf '\nERROR: %s\n' "$*" >&2; exit 1; }

self_test() {
  [[ "$BUNDLE_ID" == "com.jonathangana131.nembra.capturelearn" ]] || die "Capture bundle identity drifted."
  [[ "$DOMAIN_TYPE" == "appDataContainer" ]] || die "Capture container domain drifted."
  [[ "$MANIFEST_INCOMING_REMOTE" == */NembraCapture/FieldAuthorization/retained-install-manifest.incoming ]] || die "Manifest incoming path drifted."
  [[ "$MANIFEST_COMMIT_REMOTE" == */NembraCapture/FieldAuthorization/retained-install-manifest.commit ]] || die "Manifest commit path drifted."
  [[ "$RENDEZVOUS_REMOTE" == */NembraCapture/FieldAuthorization/signer-rendezvous.json ]] || die "Rendezvous path drifted."
  [[ "$ENVELOPE_INCOMING_REMOTE" == */NembraCapture/FieldAuthorization/authorization-envelope.incoming ]] || die "Envelope incoming path drifted."
  [[ "$ENVELOPE_COMMIT_REMOTE" == */NembraCapture/FieldAuthorization/authorization-envelope.commit ]] || die "Envelope commit path drifted."
  [[ "$MANIFEST_MAX_BYTES" == 16384 ]] || die "Manifest byte bound drifted."
  [[ "$RENDEZVOUS_MAX_BYTES" == 4096 ]] || die "Rendezvous byte bound drifted."
  [[ "$ENVELOPE_MAX_BYTES" == 32768 ]] || die "Envelope byte bound drifted."
  [[ "$COMMIT_RECORD_BYTES" == 65 ]] || die "Commit record byte bound drifted."
  [[ "$TRANSPORT_RELATIVE_PATH" == "scripts/field/transfer_field_authorization.command" ]] || die "Transport source path drifted."
  [[ "$CONTRACT_RELATIVE_PATH" == "scripts/ci/xcode27_devicectl_manifest_transport_contract.sh" ]] || die "Transport contract path drifted."
  for path in "$MANIFEST_INCOMING_REMOTE" "$MANIFEST_COMMIT_REMOTE" "$RENDEZVOUS_REMOTE" "$ENVELOPE_INCOMING_REMOTE" "$ENVELOPE_COMMIT_REMOTE"; do
    [[ "$path" != /* && "$path" != *".."* ]] || die "Container path is not bounded."
  done
  builtin printf '%s\n' 'FIELD_AUTHORIZATION_TRANSPORT_SELF_TEST_OK_NOT_PHYSICAL_GO'
}

if [[ "${1:-}" == "--self-test" ]]; then
  [[ "$#" == 1 ]] || die "--self-test accepts no additional arguments."
  self_test
  exit 0
fi

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "Run field transport on the Xcode Mac connected to the intended iPhone."
[[ -x /usr/bin/xcrun && -x /usr/bin/python3 && -x /usr/bin/mktemp && -x /usr/bin/git ]] || die "Xcode command-line tools, system Python, and Git are required."
ACTION="${1:-}"
[[ "$#" == 1 ]] || die "Choose one action; paths/device identity must come from environment variables, not extra argv values."
case "$ACTION" in
  --stage-manifest|--export-rendezvous|--stage-envelope) ;;
  *) die "Choose --stage-manifest, --export-rendezvous, --stage-envelope, or --self-test." ;;
esac

: "${NEMBRA_FIELD_DEVICE_ID:?Set NEMBRA_FIELD_DEVICE_ID to the intended connected iPhone CoreDevice identifier.}"
[[ "$NEMBRA_FIELD_DEVICE_ID" =~ ^([0-9A-Fa-f]{40}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})$ ]] || die "NEMBRA_FIELD_DEVICE_ID is not a canonical Apple UDID."
: "${NEMBRA_RETAINED_INSTALL_MANIFEST_PATH:?Set NEMBRA_RETAINED_INSTALL_MANIFEST_PATH to the exact retained-install manifest for this attempt.}"

SCRATCH="$(/usr/bin/mktemp -d "/private/tmp/nembra-field-authorization-transport.XXXXXX")"
[[ "$SCRATCH" == "/private/tmp/nembra-field-authorization-transport."* ]] || die "Temporary path is invalid."
/bin/chmod 700 "$SCRATCH"
cleanup() { /bin/rm -rf -- "$SCRATCH"; }
trap cleanup EXIT HUP INT TERM

# Bind the executable transport and the help-contract helper to the exact tracked repository HEAD
# before any device contact. The helper is then materialized from accepted Git object bytes into the
# private scratch directory so a later worktree replacement cannot change what this attempt runs.
REPOSITORY_HEAD="$(/usr/bin/git -C "$ROOT" rev-parse --verify 'HEAD^{commit}')"
TRANSPORT_TRACKED_BLOB="$(/usr/bin/git -C "$ROOT" rev-parse "${REPOSITORY_HEAD}:${TRANSPORT_RELATIVE_PATH}")"
CONTRACT_TRACKED_BLOB="$(/usr/bin/git -C "$ROOT" rev-parse "${REPOSITORY_HEAD}:${CONTRACT_RELATIVE_PATH}")"
TRANSPORT_WORKTREE_BLOB="$(/usr/bin/git -C "$ROOT" hash-object "$ROOT/$TRANSPORT_RELATIVE_PATH")"
CONTRACT_WORKTREE_BLOB="$(/usr/bin/git -C "$ROOT" hash-object "$ROOT/$CONTRACT_RELATIVE_PATH")"
[[ "$TRANSPORT_WORKTREE_BLOB" == "$TRANSPORT_TRACKED_BLOB" ]] || die "Field transport bytes differ from repository HEAD; refusing device transfer."
[[ "$CONTRACT_WORKTREE_BLOB" == "$CONTRACT_TRACKED_BLOB" ]] || die "Xcode transport-contract bytes differ from repository HEAD; refusing device transfer."
CONTRACT_EXEC="$SCRATCH/xcode27_devicectl_manifest_transport_contract.sh"
/usr/bin/git -C "$ROOT" show "${REPOSITORY_HEAD}:${CONTRACT_RELATIVE_PATH}" > "$CONTRACT_EXEC"
/bin/chmod 500 "$CONTRACT_EXEC"
CONTRACT_MATERIALIZED_BLOB="$(/usr/bin/git -C "$ROOT" hash-object "$CONTRACT_EXEC")"
[[ "$CONTRACT_MATERIALIZED_BLOB" == "$CONTRACT_TRACKED_BLOB" ]] || die "Materialized Xcode transport-contract bytes failed exact-blob verification."

# Help-only proof: no device is contacted here. Exact Xcode must document bidirectional
# appDataContainer copy and bundle-ID domain identity before any field transfer is attempted.
ARTIFACTS_DIR="$SCRATCH/devicectl-help" /bin/bash -p "$CONTRACT_EXEC" >/dev/null

# Snapshot a caller-supplied local subject through descriptor custody before devicectl can see it.
snapshot_local_file() {
  /usr/bin/python3 -I -B - "$1" "$2" "$3" "$4" <<'PY'
import os, stat, sys
from pathlib import PurePath
raw_source, raw_destination, maximum_raw, label = sys.argv[1:]
if not raw_source.startswith('/') or '\x00' in raw_source:
    raise SystemExit(f'ERROR: {label} source must be absolute')
source = PurePath(raw_source)
if any(part in {'', '.', '..'} for part in source.parts[1:]):
    raise SystemExit(f'ERROR: {label} source is not canonical')
maximum = int(maximum_raw)
no_follow = getattr(os, 'O_NOFOLLOW', None)
if no_follow is None or maximum <= 0:
    raise SystemExit(f'ERROR: {label} secure custody unavailable')
parent = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
try:
    for component in source.parts[1:-1]:
        next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | no_follow, dir_fd=parent)
        os.close(parent); parent = next_fd
    fd = os.open(source.parts[-1], os.O_RDONLY | no_follow, dir_fd=parent)
finally:
    os.close(parent)
try:
    before = os.fstat(fd)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_uid != os.geteuid():
        raise SystemExit(f'ERROR: {label} identity rejected')
    if stat.S_IMODE(before.st_mode) & 0o022 or before.st_size <= 0 or before.st_size > maximum:
        raise SystemExit(f'ERROR: {label} mode/size rejected')
    data = bytearray()
    while len(data) <= maximum:
        block = os.read(fd, min(65536, maximum + 1 - len(data)))
        if not block: break
        data.extend(block)
    after = os.fstat(fd)
    identity = lambda s: (s.st_dev,s.st_ino,s.st_mode,s.st_uid,s.st_nlink,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
    if identity(before) != identity(after) or len(data) != before.st_size:
        raise SystemExit(f'ERROR: {label} changed during read')
finally:
    os.close(fd)
out = os.open(raw_destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | no_follow, 0o600)
try:
    offset = 0
    while offset < len(data):
        count = os.write(out, data[offset:])
        if count <= 0: raise SystemExit(f'ERROR: {label} snapshot failed')
        offset += count
    os.fsync(out)
finally:
    os.close(out)
PY
}

# Cross-bind every transport action to the retained manifest's signed intended-device digest before
# any CoreDevice operation. The accepted private-runner grammar is reused exactly; the digest is
# SHA-256 over the exact UDID UTF-8 bytes with no newline. This does not authorize the app/session.
verify_manifest_device_binding() {
  /usr/bin/python3 -I -B - "$1" "$NEMBRA_FIELD_DEVICE_ID" <<'PY'
import hashlib, hmac, json, re, sys
from pathlib import Path
manifest_path, device_id = sys.argv[1:]
if re.fullmatch(r'(?:[0-9A-Fa-f]{40}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})', device_id) is None:
    raise SystemExit('ERROR: selected device is not a canonical Apple UDID')
data = Path(manifest_path).read_bytes()

def reject_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate manifest member')
        result[key] = value
    return result

try:
    manifest = json.loads(data.decode('utf-8'), object_pairs_hook=reject_duplicates)
except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
    raise SystemExit(f'ERROR: retained-install manifest is not canonical JSON: {error}')
if not isinstance(manifest, dict):
    raise SystemExit('ERROR: retained-install manifest root is not an object')
canonical = json.dumps(manifest, ensure_ascii=False, separators=(',', ':'), sort_keys=True).encode('utf-8')
if not hmac.compare_digest(canonical, data):
    raise SystemExit('ERROR: retained-install manifest bytes are not canonical')
expected = manifest.get('intendedDevicePseudonymSHA256')
if not isinstance(expected, str) or re.fullmatch(r'[0-9a-f]{64}', expected) is None or expected == '0' * 64:
    raise SystemExit('ERROR: retained-install manifest intended-device digest is invalid')
observed = hashlib.sha256(device_id.encode('utf-8')).hexdigest()
if not hmac.compare_digest(observed, expected):
    raise SystemExit('ERROR: selected CoreDevice does not match retained-install intended-device pseudonym')
PY
}

# Publish copied rendezvous bytes only to a fresh caller-selected file. Every parent component is
# opened O_NOFOLLOW, so a symlinked parent cannot redirect this private handoff.
publish_fresh_local_file() {
  /usr/bin/python3 -I -B - "$1" "$2" "$3" "$4" <<'PY'
import os, stat, sys
from pathlib import PurePath
raw_source, raw_output, maximum_raw, label = sys.argv[1:]
output = PurePath(raw_output)
if not raw_output.startswith('/') or any(part in {'', '.', '..'} for part in output.parts[1:]):
    raise SystemExit(f'ERROR: {label} output must be canonical absolute path')
maximum = int(maximum_raw); no_follow = getattr(os, 'O_NOFOLLOW', None)
if no_follow is None or maximum <= 0: raise SystemExit(f'ERROR: {label} secure custody unavailable')
fd = os.open(raw_source, os.O_RDONLY | no_follow)
try:
    before = os.fstat(fd)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size <= 0 or before.st_size > maximum:
        raise SystemExit(f'ERROR: {label} copied subject rejected')
    data = os.read(fd, maximum + 1); after = os.fstat(fd)
    if len(data) != before.st_size or (before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns,before.st_ctime_ns) != (after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns,after.st_ctime_ns):
        raise SystemExit(f'ERROR: {label} copied subject changed')
finally:
    os.close(fd)
parent = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
try:
    for component in output.parts[1:-1]:
        next_fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | no_follow, dir_fd=parent)
        os.close(parent); parent = next_fd
    out = os.open(output.parts[-1], os.O_WRONLY | os.O_CREAT | os.O_EXCL | no_follow, 0o600, dir_fd=parent)
finally:
    os.close(parent)
try:
    offset = 0
    while offset < len(data):
        count = os.write(out, data[offset:])
        if count <= 0: raise SystemExit(f'ERROR: {label} publication failed')
        offset += count
    os.fsync(out)
finally:
    os.close(out)
PY
}

# A completion record is deliberately tiny and non-authorizing: exactly lowercase SHA-256 plus LF.
# The app treats incomplete/changing/mismatched records as "not published yet" and does not consume
# the staged subject until a stable record matches stable incoming bytes.
make_commit_record() {
  local source="$1"
  local destination="$2"
  local digest
  digest="$(/usr/bin/shasum -a 256 "$source" | /usr/bin/awk '{print $1}')"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || die "Could not derive canonical SHA-256 completion record."
  builtin printf '%s\n' "$digest" > "$destination"
  /bin/chmod 600 "$destination"
  [[ "$(/usr/bin/stat -f '%z' "$destination")" == "$COMMIT_RECORD_BYTES" ]] || die "Completion record byte count drifted."
}

copy_to_container() {
  /usr/bin/xcrun devicectl device copy to --device "$NEMBRA_FIELD_DEVICE_ID" --domain-type "$DOMAIN_TYPE" --domain-identifier "$BUNDLE_ID" --source "$1" --destination "$2"
}
copy_from_container() {
  /usr/bin/xcrun devicectl device copy from --device "$NEMBRA_FIELD_DEVICE_ID" --domain-type "$DOMAIN_TYPE" --domain-identifier "$BUNDLE_ID" --source "$1" --destination "$2"
}

# Snapshot and bind the retained manifest for every action before the first device contact. This
# prevents stage-envelope/export-rendezvous from silently selecting a device unrelated to the
# manifest that names the one-time attempt.
manifest_binding_snapshot="$SCRATCH/retained-install-manifest.binding.json"
snapshot_local_file "$NEMBRA_RETAINED_INSTALL_MANIFEST_PATH" "$manifest_binding_snapshot" "$MANIFEST_MAX_BYTES" "retained-install manifest"
verify_manifest_device_binding "$manifest_binding_snapshot"

case "$ACTION" in
  --stage-manifest)
    commit="$SCRATCH/retained-install-manifest.commit"
    make_commit_record "$manifest_binding_snapshot" "$commit"
    copy_to_container "$manifest_binding_snapshot" "$MANIFEST_INCOMING_REMOTE"
    copy_to_container "$commit" "$MANIFEST_COMMIT_REMOTE"
    say "Retained manifest staged and completion-bound in the fixed Nembra Capture inbox."
    builtin printf '%s\n' 'FIELD_AUTHORIZATION_MANIFEST_STAGED_NON_AUTHORIZING'
    ;;
  --export-rendezvous)
    : "${NEMBRA_SIGNER_RENDEZVOUS_OUTPUT:?Set NEMBRA_SIGNER_RENDEZVOUS_OUTPUT to a fresh absolute local output path.}"
    staged="$SCRATCH/signer-rendezvous.json"
    copy_from_container "$RENDEZVOUS_REMOTE" "$staged"
    publish_fresh_local_file "$staged" "$NEMBRA_SIGNER_RENDEZVOUS_OUTPUT" "$RENDEZVOUS_MAX_BYTES" "signer rendezvous"
    say "Fresh signer rendezvous exported without modifying the running app attempt."
    builtin printf '%s\n' 'FIELD_AUTHORIZATION_RENDEZVOUS_EXPORTED_NON_AUTHORIZING'
    ;;
  --stage-envelope)
    : "${NEMBRA_FIELD_AUTHORIZATION_ENVELOPE_PATH:?Set NEMBRA_FIELD_AUTHORIZATION_ENVELOPE_PATH to the independently signed envelope.}"
    staged="$SCRATCH/authorization-envelope.json"
    commit="$SCRATCH/authorization-envelope.commit"
    snapshot_local_file "$NEMBRA_FIELD_AUTHORIZATION_ENVELOPE_PATH" "$staged" "$ENVELOPE_MAX_BYTES" "signed authorization envelope"
    make_commit_record "$staged" "$commit"
    copy_to_container "$staged" "$ENVELOPE_INCOMING_REMOTE"
    copy_to_container "$commit" "$ENVELOPE_COMMIT_REMOTE"
    say "Signed envelope staged and completion-bound in the fixed Nembra Capture inbox; the app must still verify and consume it."
    builtin printf '%s\n' 'FIELD_AUTHORIZATION_ENVELOPE_STAGED_NOT_AUTHORITY_NOT_PHYSICAL_GO'
    ;;
esac
