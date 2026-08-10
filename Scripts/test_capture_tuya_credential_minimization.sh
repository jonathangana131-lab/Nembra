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

# The authenticated field controller must not invoke DP control APIs.
if grep -Eq '\.(publishDps|publishDpsWith|resetFactory|removeDevice|unbind|disconnectAndRemove)' "$ENTRY"; then
  fail "authenticated field controller contains a prohibited command/unbind/reset API"
fi

# The official driver is the only accepted BLE authentication provider.
grep -q 'connectBLE' "$ENTRY" || fail "official Tuya BLE connect path missing"
grep -q 'deviceStatue' "$ENTRY" || fail "local BLE liveness proof missing"
grep -q 'dpsUpdate' "$ENTRY" || fail "application update observation missing"
grep -q 'smartLifeAppSDK' "$ENTRY" || fail "accepted authentication provenance missing"

printf 'PASS: Capture Tuya credential-minimization/read-only contract\n'
