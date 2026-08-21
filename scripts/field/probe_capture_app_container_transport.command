#!/bin/bash
set -euo pipefail
umask 077

# This probe proves only bidirectional file transport to the already-installed Nembra Capture
# appDataContainer selected by bundle ID on one explicitly selected iPhone. It never proves which
# exact Capture build is installed, never transfers an authorization payload, never grants Capture
# authority, and its own code path initiates no Bluetooth/Tuya/ES80 operation.

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || {
  echo 'ERROR: this probe must run on the Xcode Mac.' >&2
  exit 2
}

REPOSITORY_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
PROBE_RELATIVE_PATH='scripts/field/probe_capture_app_container_transport.command'
CONTRACT_RELATIVE_PATH='scripts/ci/xcode27_devicectl_manifest_transport_contract.sh'
PROBE_PATH="$REPOSITORY_ROOT/$PROBE_RELATIVE_PATH"
CONTRACT="$REPOSITORY_ROOT/$CONTRACT_RELATIVE_PATH"
BUNDLE_ID='com.jonathangana131.nembra.capturelearn'
FIELD_AUTHORIZATION_SUBDIRECTORY='Library/Application Support/NembraCapture/FieldAuthorization'

[[ "$#" -eq 0 ]] || {
  echo 'ERROR: positional arguments are forbidden; set NEMBRA_CAPTURE_DEVICE_UDID in the environment for the intended iPhone.' >&2
  exit 3
}
DEVICE_UDID="${NEMBRA_CAPTURE_DEVICE_UDID:-}"
unset NEMBRA_CAPTURE_DEVICE_UDID || true
[[ -n "$DEVICE_UDID" ]] || {
  echo 'ERROR: set NEMBRA_CAPTURE_DEVICE_UDID in the environment for the intended iPhone.' >&2
  exit 3
}
[[ -x /usr/bin/xcrun ]] || {
  echo 'ERROR: xcrun is unavailable.' >&2
  exit 4
}
[[ -f "$CONTRACT" ]] || {
  echo "ERROR: missing exact devicectl transport contract: $CONTRACT" >&2
  exit 5
}
[[ -x /usr/bin/git ]] || {
  echo 'ERROR: git is unavailable for exact probe provenance binding.' >&2
  exit 8
}

# Bind the future physical result to exact checked-in probe and transport-contract bytes before any
# device contact. A locally edited probe/contract fails closed even if the repository HEAD itself is
# an accepted SHA. This result still does not prove which app build is installed on the iPhone.
REPOSITORY_HEAD="$(/usr/bin/git -C "$REPOSITORY_ROOT" rev-parse --verify 'HEAD^{commit}')"
PROBE_TRACKED_BLOB="$(/usr/bin/git -C "$REPOSITORY_ROOT" rev-parse "${REPOSITORY_HEAD}:${PROBE_RELATIVE_PATH}")"
CONTRACT_TRACKED_BLOB="$(/usr/bin/git -C "$REPOSITORY_ROOT" rev-parse "${REPOSITORY_HEAD}:${CONTRACT_RELATIVE_PATH}")"
PROBE_WORKTREE_BLOB="$(/usr/bin/git -C "$REPOSITORY_ROOT" hash-object "$PROBE_PATH")"
CONTRACT_WORKTREE_BLOB="$(/usr/bin/git -C "$REPOSITORY_ROOT" hash-object "$CONTRACT")"
[[ "$PROBE_WORKTREE_BLOB" == "$PROBE_TRACKED_BLOB" ]] || {
  echo 'ERROR: probe bytes differ from repository HEAD; refusing physical evidence.' >&2
  exit 9
}
[[ "$CONTRACT_WORKTREE_BLOB" == "$CONTRACT_TRACKED_BLOB" ]] || {
  echo 'ERROR: transport-contract bytes differ from repository HEAD; refusing physical evidence.' >&2
  exit 10
}
PROBE_SHA256="$(/usr/bin/shasum -a 256 "$PROBE_PATH" | /usr/bin/awk '{print $1}')"
CONTRACT_SHA256="$(/usr/bin/shasum -a 256 "$CONTRACT" | /usr/bin/awk '{print $1}')"
XCODE_IDENTITY="$(/usr/bin/xcodebuild -version | /usr/bin/tr '\n' ';' | /usr/bin/sed 's/;$//')"

# ARTIFACTS_DIR is treated as an evidence root, never as a reusable result directory. Every probe
# attempt gets a new UUID-named child. Therefore a failed later attempt cannot leave an older
# result.txt at the path printed for the current attempt and accidentally promote stale success.
ARTIFACTS_ROOT="${ARTIFACTS_DIR:-$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nembra-capture-transport.XXXXXX")}"
/bin/mkdir -p "$ARTIFACTS_ROOT"
/bin/chmod 700 "$ARTIFACTS_ROOT"
RUN_ID="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
RUN_DIR="$ARTIFACTS_ROOT/run-$RUN_ID"
/bin/mkdir "$RUN_DIR"
/bin/chmod 700 "$RUN_DIR"
ARTIFACTS_DIR="$RUN_DIR"
export ARTIFACTS_DIR

# Any output produced while contacting the physical iPhone is kept outside the durable evidence
# directory and erased on exit. devicectl may render raw device identity in human-readable output;
# only the one-way device pseudonym below is allowed into result.txt.
PRIVATE_RUNTIME_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nembra-capture-transport-private.XXXXXX")"
/bin/chmod 700 "$PRIVATE_RUNTIME_DIR"
cleanup_private_runtime() {
  /bin/rm -rf -- "$PRIVATE_RUNTIME_DIR"
}
trap cleanup_private_runtime EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Execute the exact contract blob already bound above, not a pathname that could be replaced between
# verification and execution. The contract performs help-only inspection and does not contact a device.
CONTRACT_EXEC="$PRIVATE_RUNTIME_DIR/devicectl-manifest-transport-contract.sh"
/usr/bin/git -C "$REPOSITORY_ROOT" cat-file blob "$CONTRACT_TRACKED_BLOB" > "$CONTRACT_EXEC"
/bin/chmod 500 "$CONTRACT_EXEC"
[[ "$(/usr/bin/git -C "$REPOSITORY_ROOT" hash-object "$CONTRACT_EXEC")" == "$CONTRACT_TRACKED_BLOB" ]] || {
  echo 'ERROR: exact transport-contract materialization changed; refusing physical evidence.' >&2
  exit 11
}
/bin/bash "$CONTRACT_EXEC" > "$ARTIFACTS_DIR/devicectl-copy-contract.txt"

# The separate file-listing surface is required only to exercise a read-only request against the
# intended FieldAuthorization subdirectory before the scratch round trip. A zero exit proves that
# this exact requested listing operation succeeded; the probe deliberately does not infer stronger
# filesystem-existence or exact-build identity semantics from human-readable devicectl output.
/usr/bin/xcrun devicectl help device info files > "$ARTIFACTS_DIR/devicectl-device-info-files-help.txt" 2>&1
/usr/bin/python3 -I -B - "$ARTIFACTS_DIR/devicectl-device-info-files-help.txt" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
required = ("--device", "--domain-type", "--domain-identifier", "--subdirectory")
missing = [token for token in required if token not in text]
if missing:
    raise SystemExit("ERROR: devicectl device info files help is missing: " + ", ".join(missing))
if "appDataContainer" not in text:
    raise SystemExit("ERROR: devicectl device info files help does not enumerate appDataContainer")
PY

# Never publish the raw UDID into durable evidence. A one-way local pseudonym is sufficient to
# correlate repeated operator evidence without making the raw device identifier part of the report.
DEVICE_PSEUDONYM="$(printf '%s' "$DEVICE_UDID" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"

# Request a read-only listing at the intended handoff subdirectory. This does not transfer any
# authority-bearing file and does not prove the exact accepted Capture build is the installed bundle.
/usr/bin/xcrun devicectl device info files \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --subdirectory "$FIELD_AUTHORIZATION_SUBDIRECTORY" \
  > "$PRIVATE_RUNTIME_DIR/field-authorization-directory-listing.txt" 2>&1

# The round-trip sentinel lives only in the app sandbox tmp directory. It is deliberately outside
# FieldAuthorization and cannot be interpreted as a retained manifest, envelope, rendezvous, GO
# decision, capability, telemetry sample, or protocol evidence.
NONCE="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
REMOTE_SENTINEL="tmp/nembra-capture-transport-probe-$NONCE.bin"
LOCAL_SENTINEL="$ARTIFACTS_DIR/transport-probe-in.bin"
ROUNDTRIP_SENTINEL="$ARTIFACTS_DIR/transport-probe-out.bin"
/bin/dd if=/dev/urandom of="$LOCAL_SENTINEL" bs=64 count=1 2>/dev/null
INBOUND_SHA256="$(/usr/bin/shasum -a 256 "$LOCAL_SENTINEL" | /usr/bin/awk '{print $1}')"

/usr/bin/xcrun devicectl device copy to \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source "$LOCAL_SENTINEL" \
  --destination "$REMOTE_SENTINEL" \
  > "$PRIVATE_RUNTIME_DIR/copy-to.txt" 2>&1

/usr/bin/xcrun devicectl device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source "$REMOTE_SENTINEL" \
  --destination "$ROUNDTRIP_SENTINEL" \
  > "$PRIVATE_RUNTIME_DIR/copy-from.txt" 2>&1

OUTBOUND_SHA256="$(/usr/bin/shasum -a 256 "$ROUNDTRIP_SENTINEL" | /usr/bin/awk '{print $1}')"
[[ "$INBOUND_SHA256" == "$OUTBOUND_SHA256" ]] || {
  echo 'ERROR: physical app-container round-trip SHA-256 mismatch.' >&2
  exit 6
}
/usr/bin/cmp -s "$LOCAL_SENTINEL" "$ROUNDTRIP_SENTINEL" || {
  echo 'ERROR: physical app-container round-trip bytes differ.' >&2
  exit 7
}

# Random sentinel bytes are not evidence and are removed before sealing. Only their exact matching
# hashes survive. result.txt appears atomically only after every required check has succeeded.
/bin/rm -f -- "$LOCAL_SENTINEL" "$ROUNDTRIP_SENTINEL"
RESULT_TMP="$ARTIFACTS_DIR/.result-$NONCE.tmp"
RESULT_PATH="$ARTIFACTS_DIR/result.txt"
{
  printf 'evidence_run_id=%s\n' "$RUN_ID"
  printf 'repository_head=%s\n' "$REPOSITORY_HEAD"
  printf 'probe_git_blob=%s\n' "$PROBE_TRACKED_BLOB"
  printf 'probe_sha256=%s\n' "$PROBE_SHA256"
  printf 'transport_contract_git_blob=%s\n' "$CONTRACT_TRACKED_BLOB"
  printf 'transport_contract_sha256=%s\n' "$CONTRACT_SHA256"
  printf 'xcode_identity=%s\n' "$XCODE_IDENTITY"
  printf 'bundle_id=%s\n' "$BUNDLE_ID"
  printf 'device_pseudonym_sha256=%s\n' "$DEVICE_PSEUDONYM"
  printf 'field_authorization_subdirectory_listing_succeeded=true\n'
  printf 'authorization_payload_file_transferred=false\n'
  printf 'installed_build_identity_verified=false\n'
  printf 'remote_sentinel_scope=appDataContainer/tmp\n'
  printf 'inbound_sha256=%s\n' "$INBOUND_SHA256"
  printf 'outbound_sha256=%s\n' "$OUTBOUND_SHA256"
  printf 'exact_round_trip=true\n'
  printf 'raw_device_output_persisted=false\n'
  printf 'captureAuthorized=false\n'
  printf 'physicalAuthorityCreated=false\n'
  printf 'protocolSemanticsCreated=false\n'
  printf 'probe_initiated_bluetooth=false\n'
  printf 'probe_initiated_tuya=false\n'
  printf 'probe_initiated_es80_contact=false\n'
} > "$RESULT_TMP"
/bin/chmod 600 "$RESULT_TMP"
/bin/mv -f -- "$RESULT_TMP" "$RESULT_PATH"

printf '%s\n' "PROVEN: exact bytes copied to and from the $BUNDLE_ID appDataContainer on the explicitly selected physical iPhone; the read-only listing request for $FIELD_AUTHORIZATION_SUBDIRECTORY also succeeded."
printf '%s\n' "PROVEN PROVENANCE: repository HEAD $REPOSITORY_HEAD with exact checked-in probe blob $PROBE_TRACKED_BLOB and transport-contract blob $CONTRACT_TRACKED_BLOB."
printf '%s\n' 'NOT PROVEN: handoff-directory filesystem existence beyond devicectl listing success, exact installed Capture build identity, authorization payload transfer or acceptance, signing/install custody, trust-root correctness, whether another process or already-running app contacted Bluetooth/Tuya/ES80, ES80 identity, telemetry semantics, commands, or physical Capture GO.'
printf 'Evidence directory: %s\n' "$ARTIFACTS_DIR"