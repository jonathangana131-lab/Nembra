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
BUNDLE_ID="com.jonathangana131.nembra.capturelearn"
DOMAIN_TYPE="appDataContainer"
FIELD_DIRECTORY="Library/Application Support/NembraCapture/FieldAuthorization"
MANIFEST_REMOTE="$FIELD_DIRECTORY/retained-install-manifest.json"
RENDEZVOUS_REMOTE="$FIELD_DIRECTORY/signer-rendezvous.json"
ENVELOPE_REMOTE="$FIELD_DIRECTORY/authorization-envelope.json"
MANIFEST_MAX_BYTES=16384
RENDEZVOUS_MAX_BYTES=4096
ENVELOPE_MAX_BYTES=32768

say() { builtin printf '\n==> %s\n' "$*"; }
die() { builtin printf '\nERROR: %s\n' "$*" >&2; exit 1; }

self_test() {
  [[ "$BUNDLE_ID" == "com.jonathangana131.nembra.capturelearn" ]] || die "Capture bundle identity drifted."
  [[ "$DOMAIN_TYPE" == "appDataContainer" ]] || die "Capture container domain drifted."
  [[ "$MANIFEST_REMOTE" == */NembraCapture/FieldAuthorization/retained-install-manifest.json ]] || die "Manifest path drifted."
  [[ "$RENDEZVOUS_REMOTE" == */NembraCapture/FieldAuthorization/signer-rendezvous.json ]] || die "Rendezvous path drifted."
  [[ "$ENVELOPE_REMOTE" == */NembraCapture/FieldAuthorization/authorization-envelope.json ]] || die "Envelope path drifted."
  [[ "$MANIFEST_MAX_BYTES" == 16384 ]] || die "Manifest byte bound drifted."
  [[ "$RENDEZVOUS_MAX_BYTES" == 4096 ]] || die "Rendezvous byte bound drifted."
  [[ "$ENVELOPE_MAX_BYTES" == 32768 ]] || die "Envelope byte bound drifted."
  for path in "$MANIFEST_REMOTE" "$RENDEZVOUS_REMOTE" "$ENVELOPE_REMOTE"; do
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
[[ -x /usr/bin/xcrun && -x /usr/bin/python3 && -x /usr/bin/mktemp ]] || die "Xcode command-line tools and system Python are required."
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

# Help-only proof: no device is contacted here. Exact Xcode must document bidirectional
# appDataContainer copy and bundle-ID domain identity before any field transfer is attempted.
ARTIFACTS_DIR="$SCRATCH/devicectl-help" /bin/bash -p "$ROOT/scripts/ci/xcode27_devicectl_manifest_transport_contract.sh" >/dev/null

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
    snapshot_local_file "$NEMBRA_RETAINED_INSTALL_MANIFEST_PATH" "$staged" "$MANIFEST_MAX_BYTES" "retained-install manifest"
    copy_to_container "$staged" "$MANIFEST_REMOTE"
    say "Retained manifest copied into the fixed Nembra Capture inbox."
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
    snapshot_local_file "$NEMBRA_FIELD_AUTHORIZATION_ENVELOPE_PATH" "$staged" "$ENVELOPE_MAX_BYTES" "signed authorization envelope"
    copy_to_container "$staged" "$ENVELOPE_REMOTE"
    say "Signed envelope copied into the fixed Nembra Capture inbox; the app must still verify and consume it."
    builtin printf '%s\n' 'FIELD_AUTHORIZATION_ENVELOPE_STAGED_NOT_AUTHORITY_NOT_PHYSICAL_GO'
    ;;
esac
