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
[[ -n "$NEMBRA_FIELD_DEVICE_ID" && "$NEMBRA_FIELD_DEVICE_ID" != *$'\n'* && "$NEMBRA_FIELD_DEVICE_ID" != *$'\r'* ]] || die "NEMBRA_FIELD_DEVICE_ID is malformed."

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

make_commit_record() {
  local source="$1"
  local destination="$2"
  /usr/bin/python3 -I -B - "$source" "$destination" <<'PY'
import hashlib, os, stat, sys
source, destination = sys.argv[1:]
no_follow = getattr(os, 'O_NOFOLLOW', None)
if no_follow is None:
    raise SystemExit('ERROR: publication commit custody unavailable')
fd = os.open(source, os.O_RDONLY | no_follow)
try:
    before = os.fstat(fd)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_uid != os.geteuid() or before.st_size <= 0:
        raise SystemExit('ERROR: publication subject identity rejected')
    digest = hashlib.sha256()
    total = 0
    while True:
        block = os.read(fd, 65536)
        if not block:
            break
        digest.update(block)
        total += len(block)
    after = os.fstat(fd)
    identity = lambda s: (s.st_dev,s.st_ino,s.st_mode,s.st_uid,s.st_nlink,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
    if identity(before) != identity(after) or total != before.st_size:
        raise SystemExit('ERROR: publication subject changed during digest')
finally:
    os.close(fd)
record = digest.hexdigest().encode('ascii') + b'\n'
if len(record) != 65:
    raise SystemExit('ERROR: publication commit record size drifted')
out = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | no_follow, 0o600)
try:
    offset = 0
    while offset < len(record):
        count = os.write(out, record[offset:])
        if count <= 0:
            raise SystemExit('ERROR: publication commit record write failed')
        offset += count
    os.fsync(out)
finally:
    os.close(out)
PY
}

copy_to_container() {
  /usr/bin/xcrun devicectl device copy to --device "$NEMBRA_FIELD_DEVICE_ID" --domain-type "$DOMAIN_TYPE" --domain-identifier "$BUNDLE_ID" --source "$1" --destination "$2"
}
copy_from_container() {
  /usr/bin/xcrun devicectl device copy from --device "$NEMBRA_FIELD_DEVICE_ID" --domain-type "$DOMAIN_TYPE" --domain-identifier "$BUNDLE_ID" --source "$1" --destination "$2"
}

case "$ACTION" in
  --stage-manifest)
    : "${NEMBRA_RETAINED_INSTALL_MANIFEST_PATH:?Set NEMBRA_RETAINED_INSTALL_MANIFEST_PATH to the exact retained-install manifest.}"
    staged="$SCRATCH/retained-install-manifest.json"
    commit="$SCRATCH/retained-install-manifest.commit"
    snapshot_local_file "$NEMBRA_RETAINED_INSTALL_MANIFEST_PATH" "$staged" "$MANIFEST_MAX_BYTES" "retained-install manifest"
    make_commit_record "$staged" "$commit"
    copy_to_container "$staged" "$MANIFEST_INCOMING_REMOTE"
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
