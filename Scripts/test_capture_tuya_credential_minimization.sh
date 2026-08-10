#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$ROOT/NembraApp/Features/Research/TuyaAccountBridge.swift"
ENTRY="$ROOT/NembraApp/App/NembraCaptureEntrypoint.swift"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$BRIDGE" ]] || fail "missing TuyaAccountBridge.swift"
[[ -f "$ENTRY" ]] || fail "missing NembraCaptureEntrypoint.swift"

# Physical C7D09A22 established that the next gate is official Tuya-authenticated BLE.
# The metadata bootstrap must therefore not retain a BLE-capable device secret that the
# supported SmartLife SDK path explicitly does not need.
if grep -Eq 'let[[:space:]]+localKey[[:space:]]*:' "$BRIDGE"; then
  fail "LinkedDevice still retains localKey; remove it instead of carrying a device secret through UI state"
fi
if grep -Eq 'localKey:[[:space:]]*string\(raw\["local_key"\]\)' "$BRIDGE"; then
  fail "metadata parser still copies local_key into app state"
fi

# The authenticated field controller must never issue scooter DP controls, lifecycle mutations,
# or raw CoreBluetooth GATT traffic. CoreBluetooth is discovery-only here; after candidate
# identification the official Tuya SDK must be the sole connection/GATT owner.
if grep -Eq '\.(publishDps|publishDpsWith|resetFactory|removeDevice|unbind|disconnectAndRemove)' "$ENTRY"; then
  fail "authenticated field controller contains a prohibited command/unbind/reset API"
fi
if grep -Eq 'central\.(connect|cancelPeripheralConnection)' "$ENTRY"; then
  fail "Capture secure-link entrypoint contains a raw CoreBluetooth connection path; Tuya SDK must own the secure session"
fi
if grep -Eq '\.(writeValue|setNotifyValue|discoverServices|discoverCharacteristics|readValue)\(' "$ENTRY"; then
  fail "Capture secure-link entrypoint contains raw CoreBluetooth GATT operations; discovery must stop before Tuya SDK ownership"
fi

# The official driver is the only accepted BLE authentication provider and acceptance must
# be based on local-BLE liveness plus genuine application callbacks from that SDK session.
grep -q 'connectBLE' "$ENTRY" || fail "official Tuya BLE connect path missing"
grep -q 'deviceStatue' "$ENTRY" || fail "local BLE liveness proof missing"
grep -q 'dpsUpdate' "$ENTRY" || fail "application update observation missing"
grep -q 'smartLifeAppSDK' "$ENTRY" || fail "accepted authentication provenance missing"
grep -q 'sdkDeviceMembershipVerified' "$ENTRY" || fail "exact SDK-account scooter membership gate missing"
grep -q 'maximumObservationPollGapNanoseconds' "$ENTRY" || fail "authenticated observation continuity fence missing"

printf 'PASS: Capture Tuya credential-minimization/read-only contract\n'
