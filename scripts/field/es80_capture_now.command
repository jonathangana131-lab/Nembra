#!/bin/bash
set -euo pipefail

# One-time private ES80 Capture handoff helper.
#
# This helper intentionally lives OUTSIDE the frozen Capture candidate. It checks out the exact
# candidate below into a detached temporary worktree, runs its real Xcode 27 Simulator acceptance
# locally, invokes that candidate's existing Research-only signed-field producer, and installs the
# exact retained IPA onto the selected connected iPhone. It never launches Capture or authorizes
# Bluetooth automatically; the operator must still open the app from the Home Screen, confirm the
# Research provenance screen, keep the scooter stationary with charger disconnected, and explicitly
# start the passive/read-only procedure.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
FROZEN_CAPTURE_SHA="f4cd76e301334ce96824d0b150ef03d2d2cb606b"
FROZEN_SHORT="${FROZEN_CAPTURE_SHA:0:12}"
FIELD_RECIPE="ES80-FINGERPRINT-v1"
BUNDLE_ID="com.jonathangana131.nembra"

say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This field helper must run on the Mac that has Xcode 27 and the signing account."
command -v git >/dev/null || die "git is missing."
command -v xcrun >/dev/null || die "Xcode command-line tools are missing."
command -v security >/dev/null || die "macOS security tool is missing."

cd "$REPO_ROOT"
git cat-file -e "${FROZEN_CAPTURE_SHA}^{commit}" 2>/dev/null || die "Frozen Capture commit $FROZEN_CAPTURE_SHA is not present locally. Run: git fetch --all --prune"

# Prefer an already-selected Xcode 27. Otherwise find an installed Xcode 27 app without changing
# the machine-wide xcode-select setting.
select_xcode27() {
  local version app candidate
  version="$(xcodebuild -version 2>/dev/null | head -1 || true)"
  if [[ "$version" == Xcode\ 27* ]]; then
    return 0
  fi

  for app in /Applications/Xcode_27*.app /Applications/Xcode-beta.app /Applications/Xcode.app; do
    [[ -d "$app/Contents/Developer" ]] || continue
    candidate="$(DEVELOPER_DIR="$app/Contents/Developer" xcodebuild -version 2>/dev/null | head -1 || true)"
    if [[ "$candidate" == Xcode\ 27* ]]; then
      export DEVELOPER_DIR="$app/Contents/Developer"
      return 0
    fi
  done
  return 1
}
select_xcode27 || die "Xcode 27 was not found. Install/open Xcode 27 first."

say "Using $(xcodebuild -version | tr '\n' ' ')"
xcrun simctl list runtimes | grep -q 'iOS 27' || die "The iOS 27 Simulator runtime is not installed in this Xcode. Install it in Xcode Settings > Components."

# Physical iPhone selection comes from xctrace's Devices section, not Simulators. The selected
# identifier is also the subject the signed-field inspector expects to find in the development
# provisioning profile.
DEVICE_DATA="$(/usr/bin/python3 - <<'PY'
import re, subprocess
out = subprocess.check_output(["xcrun", "xctrace", "list", "devices"], text=True, stderr=subprocess.STDOUT)
section = None
rows = []
for raw in out.splitlines():
    line = raw.strip()
    if line == "== Devices ==":
        section = "devices"; continue
    if line.startswith("== "):
        section = None; continue
    if section != "devices" or "iPhone" not in line:
        continue
    m = re.search(r"\(([0-9A-Fa-f-]{20,})\)\s*$", line)
    if m:
        rows.append((line[:m.start()].strip(), m.group(1)))
for i, (label, ident) in enumerate(rows, 1):
    print(f"{i}\t{ident}\t{label}")
PY
)" || die "Could not query connected iPhones. Unlock the iPhone, trust this Mac, and enable Developer Mode."

[[ -n "$DEVICE_DATA" ]] || die "No connected physical iPhone was found. Connect/unlock the intended iPhone and rerun this command."

DEVICE_COUNT="$(printf '%s\n' "$DEVICE_DATA" | wc -l | tr -d ' ')"
if [[ "$DEVICE_COUNT" == "1" ]]; then
  DEVICE_UDID="$(printf '%s\n' "$DEVICE_DATA" | cut -f2)"
  DEVICE_LABEL="$(printf '%s\n' "$DEVICE_DATA" | cut -f3-)"
else
  say "Connected iPhones"
  printf '%s\n' "$DEVICE_DATA" | awk -F '\t' '{printf "  %s) %s\n", $1, $3}'
  read -r -p "Choose the intended iPhone number: " DEVICE_CHOICE
  DEVICE_UDID="$(printf '%s\n' "$DEVICE_DATA" | awk -F '\t' -v n="$DEVICE_CHOICE" '$1==n {print $2}')"
  DEVICE_LABEL="$(printf '%s\n' "$DEVICE_DATA" | awk -F '\t' -v n="$DEVICE_CHOICE" '$1==n {print $3}')"
  [[ -n "$DEVICE_UDID" ]] || die "Invalid iPhone selection."
fi
say "Intended device: $DEVICE_LABEL"

# Apple Development identities normally include the Team ID in the final parenthesized token.
TEAM_IDS="$(security find-identity -v -p codesigning 2>/dev/null | /usr/bin/python3 -c '
import re,sys
ids=[]
for line in sys.stdin:
    if "Apple Development:" not in line:
        continue
    m=re.search(r"\(([A-Z0-9]{10})\)\s*\"?\s*$", line.strip())
    if m and m.group(1) not in ids:
        ids.append(m.group(1))
print("\n".join(ids))
')"
TEAM_COUNT="$(printf '%s\n' "$TEAM_IDS" | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ "$TEAM_COUNT" == "1" ]]; then
  TEAM_ID="$(printf '%s\n' "$TEAM_IDS" | sed '/^$/d')"
else
  if [[ "$TEAM_COUNT" -gt 1 ]]; then
    say "Apple Development Team IDs found"
    printf '%s\n' "$TEAM_IDS" | nl -w2 -s') '
  else
    say "No Apple Development signing identity could be auto-detected"
  fi
  read -r -p "Enter the 10-character Team ID shown in Xcode > Signing & Capabilities: " TEAM_ID
fi
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "Team ID must be exactly 10 uppercase letters/numbers."

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/NembraCaptureNow.XXXXXX")"
WORKTREE="$TMP_ROOT/frozen-source"
SIM_ARTIFACTS="$TMP_ROOT/simulator-acceptance"
UDID_FILE="$TMP_ROOT/intended-iphone.udid"
EXPORT_OPTIONS="$TMP_ROOT/ExportOptions.plist"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_DIR="$HOME/Desktop/NembraCaptureFieldCandidate-${FROZEN_SHORT}-${STAMP}"

cleanup() {
  cd "$REPO_ROOT" >/dev/null 2>&1 || true
  git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT INT TERM

umask 077
printf '%s\n' "$DEVICE_UDID" > "$UDID_FILE"
chmod 0600 "$UDID_FILE"

/usr/bin/python3 - "$EXPORT_OPTIONS" "$TEAM_ID" <<'PY'
import plistlib, sys
path, team = sys.argv[1:]
options = {
    "method": "development",
    "signingStyle": "automatic",
    "teamID": team,
    "destination": "export",
    "stripSwiftSymbols": True,
}
with open(path, "wb") as f:
    plistlib.dump(options, f, fmt=plistlib.FMT_XML, sort_keys=True)
PY
chmod 0600 "$EXPORT_OPTIONS"

say "Creating detached exact-source worktree $FROZEN_SHORT"
git worktree add --detach "$WORKTREE" "$FROZEN_CAPTURE_SHA" >/dev/null
cd "$WORKTREE"
[[ "$(git rev-parse HEAD)" == "$FROZEN_CAPTURE_SHA" ]] || die "Detached worktree did not land on the frozen Capture SHA."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "Frozen Capture worktree is not clean."

say "Running exact Capture Simulator acceptance LOCALLY on Xcode 27 (bypasses GitHub's xcode-27 queue)"
ARTIFACTS_DIR="$SIM_ARTIFACTS" scripts/ci/xcode27_simulator_capture.sh

say "Simulator acceptance passed. Producing dedicated signed Research Field Build"
export NEMBRA_DEVELOPMENT_TEAM="$TEAM_ID"
export NEMBRA_EXPORT_OPTIONS_PLIST="$EXPORT_OPTIONS"
export NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE="$UDID_FILE"
export NEMBRA_ALLOW_PROVISIONING_UPDATES=1
export ARTIFACTS_DIR="$OUTPUT_DIR"
scripts/ci/xcode27_today_research_field_candidate.sh

IPA="$(find "$OUTPUT_DIR" -type f -name '*.ipa' -print | head -1)"
[[ -n "$IPA" && -f "$IPA" ]] || die "Signed producer completed but no retained IPA was found in $OUTPUT_DIR."
IPA_SHA_BEFORE="$(shasum -a 256 "$IPA" | awk '{print $1}')"
[[ "$IPA_SHA_BEFORE" =~ ^[0-9a-f]{64}$ ]] || die "Could not hash retained IPA."

say "Installing the exact retained Research IPA on the intended iPhone"
if ! xcrun devicectl device install app --device "$DEVICE_UDID" "$IPA"; then
  say "Direct IPA install was not accepted by devicectl; installing the exact signed app bundle contained in that IPA"
  UNPACK="$TMP_ROOT/ipa-unpacked"
  mkdir "$UNPACK"
  /usr/bin/ditto -x -k "$IPA" "$UNPACK"
  APP="$(find "$UNPACK/Payload" -maxdepth 1 -type d -name '*.app' -print | head -1)"
  [[ -n "$APP" && -d "$APP" ]] || die "Could not locate the signed app bundle inside the retained IPA."
  xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
fi

IPA_SHA_AFTER="$(shasum -a 256 "$IPA" | awk '{print $1}')"
[[ "$IPA_SHA_AFTER" == "$IPA_SHA_BEFORE" ]] || die "Retained IPA bytes changed during installation. STOP."

RECEIPT="$OUTPUT_DIR/TODAY_DIRECT_INSTALL_RECEIPT.txt"
DEVICE_HASH="$(printf '%s' "$DEVICE_UDID" | shasum -a 256 | awk '{print $1}')"
{
  echo "authority=private-today-direct-device-handoff-not-physical-telemetry"
  echo "source_sha=$FROZEN_CAPTURE_SHA"
  echo "recipe=$FIELD_RECIPE"
  echo "bundle_id=$BUNDLE_ID"
  echo "team_id=$TEAM_ID"
  echo "intended_device_udid_sha256=$DEVICE_HASH"
  echo "retained_ipa_sha256=$IPA_SHA_BEFORE"
  echo "local_xcode=$(xcodebuild -version | tr '\n' ' ')"
  echo "simulator_acceptance=PASS"
  echo "exact_retained_install=PASS"
  echo "automatic_bluetooth_authorization=NOT_GRANTED"
  echo "application_characteristic_writes=NOT_AUTHORIZED"
} > "$RECEIPT"
chmod 0600 "$RECEIPT"

say "READY FOR THE MANUAL FIELD PREFLIGHT"
printf '%s\n' \
  "Installed exact frozen Capture source: $FROZEN_CAPTURE_SHA" \
  "Retained IPA SHA-256: $IPA_SHA_BEFORE" \
  "Evidence folder: $OUTPUT_DIR" \
  "" \
  "Now open Nembra FROM THE IPHONE HOME SCREEN." \
  "Do NOT start the scooter capture unless the app shows the dedicated PRIVATE RESEARCH BUILD / Runtime provenance-ready path for $FIELD_RECIPE." \
  "Keep the scooter STATIONARY and the CHARGER DISCONNECTED for the entire first capture." \
  "The app must require your explicit Start action. Do not use or add any characteristic-write/command path." \
  "If those checks are visible, the next step is the one-time OFF -> ON -> OFF -> ON correlation and passive 60-second capture."
