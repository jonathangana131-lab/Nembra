#!/bin/bash
set -euo pipefail

# This probe proves only bidirectional file transport to the already-installed Nembra Capture
# appDataContainer on one explicitly selected iPhone. It never touches authorization subjects,
# never grants Capture authority, and never contacts Bluetooth/Tuya/ES80.

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

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nembra-capture-transport.XXXXXX")}" 
/bin/mkdir -p "$ARTIFACTS_DIR"
/bin/chmod 700 "$ARTIFACTS_DIR"
export ARTIFACTS_DIR

# First bind this Xcode installation to the already-reviewed copy-to/copy-from appDataContainer help
# contract. The contract performs help-only inspection and does not contact a device.
/bin/bash "$CONTRACT" > "$ARTIFACTS_DIR/devicectl-copy-contract.txt"

# The separate file-listing surface is required only to prove that the intended installed app has
# already created its owner-only FieldAuthorization destination. Listing is read-only.
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

# Never publish the raw UDID into the durable result. A one-way local pseudonym is sufficient to
# correlate repeated operator evidence without making the raw device identifier part of the report.
DEVICE_PSEUDONYM="$(printf '%s' "$DEVICE_UDID" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"

# Prove the exact installed app has already created the intended field handoff directory. This does
# not read or copy any authority-bearing file from that directory.
/usr/bin/xcrun devicectl device info files \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --subdirectory "$FIELD_AUTHORIZATION_SUBDIRECTORY" \
  > "$ARTIFACTS_DIR/field-authorization-directory-listing.txt"

# The round-trip sentinel lives only in the app sandbox tmp directory. It is deliberately outside
# FieldAuthorization and cannot be interpreted as a retained manifest, envelope, rendezvous, GO
# decision, capability, telemetry sample, or protocol evidence.
NONCE="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
REMOTE_SENTINEL="tmp/nembra-capture-transport-probe-$NONCE.bin"
LOCAL_SENTINEL="$ARTIFACTS_DIR/transport-probe-in.bin"
ROUNDTRIP_SENTINEL="$ARTIFACTS_DIR/transport-probe-out.bin"
/usr/bin/dd if=/dev/urandom of="$LOCAL_SENTINEL" bs=64 count=1 2>/dev/null
INBOUND_SHA256="$(/usr/bin/shasum -a 256 "$LOCAL_SENTINEL" | /usr/bin/awk '{print $1}')"

/usr/bin/xcrun devicectl device copy to \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source "$LOCAL_SENTINEL" \
  --destination "$REMOTE_SENTINEL" \
  > "$ARTIFACTS_DIR/copy-to.txt"

/usr/bin/xcrun devicectl device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source "$REMOTE_SENTINEL" \
  --destination "$ROUNDTRIP_SENTINEL" \
  > "$ARTIFACTS_DIR/copy-from.txt"

OUTBOUND_SHA256="$(/usr/bin/shasum -a 256 "$ROUNDTRIP_SENTINEL" | /usr/bin/awk '{print $1}')"
[[ "$INBOUND_SHA256" == "$OUTBOUND_SHA256" ]] || {
  echo 'ERROR: physical app-container round-trip SHA-256 mismatch.' >&2
  exit 6
}
/usr/bin/cmp -s "$LOCAL_SENTINEL" "$ROUNDTRIP_SENTINEL" || {
  echo 'ERROR: physical app-container round-trip bytes differ.' >&2
  exit 7
}

{
  printf 'bundle_id=%s\n' "$BUNDLE_ID"
  printf 'device_pseudonym_sha256=%s\n' "$DEVICE_PSEUDONYM"
  printf 'field_authorization_directory_present=true\n'
  printf 'remote_sentinel_scope=appDataContainer/tmp\n'
  printf 'inbound_sha256=%s\n' "$INBOUND_SHA256"
  printf 'outbound_sha256=%s\n' "$OUTBOUND_SHA256"
  printf 'exact_round_trip=true\n'
  printf 'authorization_subject_touched=false\n'
  printf 'captureAuthorized=false\n'
  printf 'physicalAuthorityCreated=false\n'
  printf 'protocolSemanticsCreated=false\n'
  printf 'bluetoothContacted=false\n'
  printf 'tuyaContacted=false\n'
  printf 'es80Contacted=false\n'
} > "$ARTIFACTS_DIR/result.txt"

printf '%s\n' "PROVEN: exact bytes copied to and from $BUNDLE_ID appDataContainer on the explicitly selected physical iPhone; the installed app's FieldAuthorization directory was present."
printf '%s\n' 'NOT PROVEN: authorization acceptance, signing/install custody, trust-root correctness, Bluetooth/Tuya behavior, ES80 identity, telemetry semantics, commands, or physical Capture GO.'
printf 'Evidence directory: %s\n' "$ARTIFACTS_DIR"
