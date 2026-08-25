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
PRIVATE_DEVICE_READER_RELATIVE_PATH="scripts/ci/es80_signed_field_artifact_private_runner.py"
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
  [[ "$TRANSPORT_RELATIVE_PATH" == "scripts/field/transfer_field_authorization.command" ]] || die "Transport source path drifted."
  [[ "$CONTRACT_RELATIVE_PATH" == "scripts/ci/xcode27_devicectl_manifest_transport_contract.sh" ]] || die "Transport contract path drifted."
  [[ "$PRIVATE_DEVICE_READER_RELATIVE_PATH" == "scripts/ci/es80_signed_field_artifact_private_runner.py" ]] || die "Private intended-device reader path drifted."
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
[[ -x /usr/bin/xcrun && -x /usr/bin/python3 && -x /usr/bin/mktemp && -x /usr/bin/git ]] || die "Xcode command-line tools, system Python, and Git are required."
ACTION="${1:-}"
[[ "$#" == 1 ]] || die "Choose one action; paths/device identity must come from environment variables, not extra argv values."
case "$ACTION" in
  --stage-manifest|--export-rendezvous|--stage-envelope) ;;
  *) die "Choose --stage-manifest, --export-rendezvous, --stage-envelope, or --self-test." ;;
esac

: "${NEMBRA_FIELD_DEVICE_ID:?Set NEMBRA_FIELD_DEVICE_ID to the intended connected iPhone CoreDevice selector.}"
[[ "$NEMBRA_FIELD_DEVICE_ID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || die "NEMBRA_FIELD_DEVICE_ID is not a canonical CoreDevice selector."
: "${NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE:?Set NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE to the private mode-0600 intended-iPhone identifier file.}"
: "${NEMBRA_RETAINED_INSTALL_MANIFEST_PATH:?Set NEMBRA_RETAINED_INSTALL_MANIFEST_PATH to the exact retained-install manifest for this attempt.}"

SCRATCH="$(/usr/bin/mktemp -d "/private/tmp/nembra-field-authorization-transport.XXXXXX")"
[[ "$SCRATCH" == "/private/tmp/nembra-field-authorization-transport."* ]] || die "Temporary path is invalid."
/bin/chmod 700 "$SCRATCH"
cleanup() { /bin/rm -rf -- "$SCRATCH"; }
trap cleanup EXIT HUP INT TERM

# Bind every repository helper that can influence physical-device selection or transport to exact
# tracked bytes before any device discovery. The helpers are then materialized from accepted Git
# objects into the private attempt directory so mutable worktree replacements cannot redirect them.
REPOSITORY_HEAD="$(/usr/bin/git -C "$ROOT" rev-parse --verify 'HEAD^{commit}')"
TRANSPORT_TRACKED_BLOB="$(/usr/bin/git -C "$ROOT" rev-parse "${REPOSITORY_HEAD}:${TRANSPORT_RELATIVE_PATH}")"
CONTRACT_TRACKED_BLOB="$(/usr/bin/git -C "$ROOT" rev-parse "${REPOSITORY_HEAD}:${CONTRACT_RELATIVE_PATH}")"
PRIVATE_DEVICE_READER_TRACKED_BLOB="$(/usr/bin/git -C "$ROOT" rev-parse "${REPOSITORY_HEAD}:${PRIVATE_DEVICE_READER_RELATIVE_PATH}")"
TRANSPORT_WORKTREE_BLOB="$(/usr/bin/git -C "$ROOT" hash-object "$ROOT/$TRANSPORT_RELATIVE_PATH")"
CONTRACT_WORKTREE_BLOB="$(/usr/bin/git -C "$ROOT" hash-object "$ROOT/$CONTRACT_RELATIVE_PATH")"
PRIVATE_DEVICE_READER_WORKTREE_BLOB="$(/usr/bin/git -C "$ROOT" hash-object "$ROOT/$PRIVATE_DEVICE_READER_RELATIVE_PATH")"
[[ "$TRANSPORT_WORKTREE_BLOB" == "$TRANSPORT_TRACKED_BLOB" ]] || die "Field transport bytes differ from repository HEAD; refusing device transfer."
[[ "$CONTRACT_WORKTREE_BLOB" == "$CONTRACT_TRACKED_BLOB" ]] || die "Xcode transport-contract bytes differ from repository HEAD; refusing device transfer."
[[ "$PRIVATE_DEVICE_READER_WORKTREE_BLOB" == "$PRIVATE_DEVICE_READER_TRACKED_BLOB" ]] || die "Private intended-device reader bytes differ from repository HEAD; refusing device selection."

CONTRACT_EXEC="$SCRATCH/xcode27_devicectl_manifest_transport_contract.sh"
PRIVATE_DEVICE_READER_EXEC="$SCRATCH/es80_signed_field_artifact_private_runner.py"
/usr/bin/git -C "$ROOT" show "${REPOSITORY_HEAD}:${CONTRACT_RELATIVE_PATH}" > "$CONTRACT_EXEC"
/usr/bin/git -C "$ROOT" show "${REPOSITORY_HEAD}:${PRIVATE_DEVICE_READER_RELATIVE_PATH}" > "$PRIVATE_DEVICE_READER_EXEC"
/bin/chmod 500 "$CONTRACT_EXEC" "$PRIVATE_DEVICE_READER_EXEC"
CONTRACT_MATERIALIZED_BLOB="$(/usr/bin/git -C "$ROOT" hash-object "$CONTRACT_EXEC")"
PRIVATE_DEVICE_READER_MATERIALIZED_BLOB="$(/usr/bin/git -C "$ROOT" hash-object "$PRIVATE_DEVICE_READER_EXEC")"
[[ "$CONTRACT_MATERIALIZED_BLOB" == "$CONTRACT_TRACKED_BLOB" ]] || die "Materialized Xcode transport-contract bytes failed exact-blob verification."
[[ "$PRIVATE_DEVICE_READER_MATERIALIZED_BLOB" == "$PRIVATE_DEVICE_READER_TRACKED_BLOB" ]] || die "Materialized private intended-device reader bytes failed exact-blob verification."

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

# Cross-bind the retained manifest to a privately custodied intended-device token. The manifest's
# intendedDevicePseudonymSHA256 is SHA-256 over the exact private UDID UTF-8 bytes; the raw token is
# captured only in the protected shell and is never printed, persisted, or passed to devicectl argv.
read_manifest_bound_private_device() {
  /usr/bin/python3 -I -B - "$PRIVATE_DEVICE_READER_EXEC" "$1" "$NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE" "$ROOT" <<'PY'
import hashlib, hmac, importlib.util, json, re, sys
from pathlib import Path
reader_path, manifest_path, private_device_path, repository_root = sys.argv[1:]

spec = importlib.util.spec_from_file_location("nembra_private_device_reader", reader_path)
if spec is None or spec.loader is None:
    raise SystemExit('ERROR: private intended-device reader could not be loaded')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

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
value = module.read_private_identifier(Path(private_device_path), Path(repository_root))
observed = hashlib.sha256(value.encode('utf-8')).hexdigest()
if not hmac.compare_digest(observed, expected):
    raise SystemExit('ERROR: private intended-device identifier does not match retained-install intended-device pseudonym')
sys.stdout.write(value)
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

# Snapshot the retained manifest and bind its intended-device pseudonym to the private mode-0600
# identifier before the first physical-device query. No caller-selected CoreDevice can bypass this.
manifest_binding_snapshot="$SCRATCH/retained-install-manifest.binding.json"
snapshot_local_file "$NEMBRA_RETAINED_INSTALL_MANIFEST_PATH" "$manifest_binding_snapshot" "$MANIFEST_MAX_BYTES" "retained-install manifest"
if ! INTENDED_DEVICE_UDID="$(read_manifest_bound_private_device "$manifest_binding_snapshot")"; then
  die "Retained manifest/private intended-device binding failed before device discovery."
fi
[[ -n "$INTENDED_DEVICE_UDID" ]] || die "Private intended-device binding produced no identifier."

# Require exactly one matching attached physical iPhone in Xcode's device view. The raw identifier
# remains inside this shell only and is never persisted or emitted to devicectl argv.
DEVICE_ROWS="$(/usr/bin/xcrun xctrace list devices 2>/dev/null | /usr/bin/python3 -I -B -c '
import re, sys
section = False
for raw in sys.stdin:
    line = raw.strip()
    if line == "== Devices ==":
        section = True
        continue
    if line.startswith("== "):
        section = False
        continue
    if not section or "iPhone" not in line:
        continue
    match = re.search(r"\(([0-9A-Fa-f-]{20,})\)\s*$", line)
    if match:
        print(match.group(1))
')"
[[ -n "$DEVICE_ROWS" ]] || die "Xcode reported no physical iPhone for intended-device binding."
MATCH_COUNT=0
INTENDED_NORMALIZED="$(builtin printf '%s' "$INTENDED_DEVICE_UDID" | /usr/bin/tr '[:upper:]' '[:lower:]')"
while IFS= read -r ROW_UDID; do
  [[ -n "$ROW_UDID" ]] || continue
  ROW_NORMALIZED="$(builtin printf '%s' "$ROW_UDID" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  if [[ "$ROW_NORMALIZED" == "$INTENDED_NORMALIZED" ]]; then
    MATCH_COUNT=$((MATCH_COUNT + 1))
  fi
done <<< "$DEVICE_ROWS"
[[ "$MATCH_COUNT" == "1" ]] || die "Connected iPhones do not contain exactly one match for the retained manifest's intended device. No arbitrary-device fallback is permitted."

# CoreDevice exposes a separate non-private selector. Correlate that selector to the private UDID
# through its CoreDevice hostname, then require the caller-selected selector to be exactly that value.
COREDEVICE_ROWS="$(/usr/bin/xcrun devicectl list devices --hide-headers 2>/dev/null || true)"
[[ -n "$COREDEVICE_ROWS" ]] || die "CoreDevice reported no available intended iPhone."
if ! BOUND_COREDEVICE_ID="$(builtin printf '%s\0%s' "$INTENDED_DEVICE_UDID" "$COREDEVICE_ROWS" | /usr/bin/python3 -I -B -c '
import re, sys
payload = sys.stdin.buffer.read()
try:
    intended_raw, rows_raw = payload.split(b"\0", 1)
    intended = intended_raw.decode("utf-8").lower()
    rows = rows_raw.decode("utf-8")
except (ValueError, UnicodeDecodeError):
    raise SystemExit(2)
matches = []
for raw in rows.splitlines():
    line = raw.strip()
    match = re.search(r"(\S+\.coredevice\.local)\s+([0-9A-Fa-f-]{36})\s+(.+)$", line)
    if match is None:
        continue
    hostname, selector, tail = match.groups()
    if hostname.lower() != intended + ".coredevice.local":
        continue
    if re.search(r"\bunavailable\b", tail, re.IGNORECASE):
        continue
    matches.append(selector)
if len(matches) != 1:
    raise SystemExit(3)
sys.stdout.write(matches[0])
')"; then
  die "CoreDevice could not bind exactly one available selector to the retained manifest's intended device."
fi
[[ "$BOUND_COREDEVICE_ID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || die "Bound CoreDevice selector is malformed."
[[ "$(builtin printf '%s' "$BOUND_COREDEVICE_ID" | /usr/bin/tr '[:upper:]' '[:lower:]')" == "$(builtin printf '%s' "$NEMBRA_FIELD_DEVICE_ID" | /usr/bin/tr '[:upper:]' '[:lower:]')" ]] || die "Caller-selected CoreDevice does not match the retained manifest's intended device."

# Drop raw/private device subjects before any app-container copy. Only the already-correlated
# non-private CoreDevice selector remains available to the transfer helpers.
unset INTENDED_DEVICE_UDID INTENDED_NORMALIZED ROW_UDID ROW_NORMALIZED DEVICE_ROWS COREDEVICE_ROWS BOUND_COREDEVICE_ID MATCH_COUNT
unset NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE || true
say "Intended CoreDevice matched retained manifest device binding"

case "$ACTION" in
  --stage-manifest)
    copy_to_container "$manifest_binding_snapshot" "$MANIFEST_REMOTE"
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
