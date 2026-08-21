#!/bin/bash
set -euo pipefail
umask 077

# This probe proves only bidirectional file transport to the already-installed Nembra Capture
# appDataContainer selected by bundle ID on one explicitly selected iPhone. It never proves which
# exact Capture build is installed, never transfers an authorization payload, never grants Capture
# authority, and never contacts Bluetooth/Tuya/ES80.

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || {
  echo 'ERROR: this probe must run on the Xcode Mac.' >&2
  exit 2
}

REPOSITORY_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
CONTRACT="$REPOSITORY_ROOT/scripts/ci/xcode27_devicectl_manifest_transport_contract.sh"
BUNDLE_ID='com.jonathangana131.nembra.capturelearn'
FIELD_AUTHORIZATION_SUBDIRECTORY='Library/Application Support/NembraCapture/FieldAuthorization'
DEVICE_UDID="${NEMBRA_CAPTURE_DEVICE_UDID:-${1:-}}"

[[ -n "$DEVICE_UDID" ]] || {
  echo 'ERROR: set NEMBRA_CAPTURE_DEVICE_UDID (or pass the intended iPhone UDID as argument 1).' >&2
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

# First bind this Xcode installation to the already-reviewed copy-to/copy-from appDataContainer help
# contract. The contract performs help-only inspection and does not contact a device.
/bin/bash "$CONTRACT" > "$ARTIFACTS_DIR/devicectl-copy-contract.txt"

# The separate file-listing surface is required only to prove that the selected installed bundle has
# already created its FieldAuthorization destination. Listing is read-only. This does not establish
# the exact source/build identity of that installed bundle, and it does access the authorization
# namespace; the truthful boundary below is that no authorization payload file is transferred.
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

# Prove the selected installed bundle has already created the intended field handoff directory. This
# read-only listing does not transfer any authority-bearing file and does not prove the exact accepted
# Capture build is the installed bundle.
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
  printf 'bundle_id=%s\n' "$BUNDLE_ID"
  printf 'device_pseudonym_sha256=%s\n' "$DEVICE_PSEUDONYM"
  printf 'field_authorization_directory_listed_read_only=true\n'
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
  printf 'bluetoothContacted=false\n'
  printf 'tuyaContacted=false\n'
  printf 'es80Contacted=false\n'
} > "$RESULT_TMP"
/bin/chmod 600 "$RESULT_TMP"
/bin/mv -f -- "$RESULT_TMP" "$RESULT_PATH"

printf '%s\n' "PROVEN: exact bytes copied to and from the $BUNDLE_ID appDataContainer on the explicitly selected physical iPhone; that bundle's FieldAuthorization directory was present by read-only listing."
printf '%s\n' 'NOT PROVEN: exact installed Capture build identity, authorization payload transfer or acceptance, signing/install custody, trust-root correctness, Bluetooth/Tuya behavior, ES80 identity, telemetry semantics, commands, or physical Capture GO.'
printf 'Evidence directory: %s\n' "$ARTIFACTS_DIR"
