#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TUYA_PRIVATE_SDK="$REPO_ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$REPO_ROOT/LocalSecrets/TuyaRuntime"
DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"
BUILD_SUBJECT_HELPER="$SCRIPT_DIR/capture_cocoapods_build_subject.py"
REVIEW_ONLY=0
if [[ "${1:-}" == "--resolve-lock-for-review" ]]; then
  REVIEW_ONLY=1
  shift
fi
[[ "$#" == "0" ]] || {
  echo "ERROR: usage: Scripts/bootstrap_capture_tuya_sdk.sh [--resolve-lock-for-review]" >&2
  exit 1
}
cd "$REPO_ROOT"

if [[ "$REVIEW_ONLY" == "0" ]]; then
  : "${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 to the preaccepted lowercase/uppercase 64-hex attested Podfile.lock SHA-256 before field bootstrap. To create a candidate dependency subject without build authority, use --resolve-lock-for-review.}"
  [[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
fi

if ! command -v pod >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ERROR: CocoaPods is not installed.

Nembra Capture's authenticated Tuya BLE path intentionally uses Tuya's official
SmartLife App SDK. Install CocoaPods on the development Mac, then run this
script again. Do not copy SDK binaries or private Tuya credentials into git.
EOF
  exit 2
fi

[[ -x /usr/bin/python3 ]] || {
  echo "ERROR: System Python 3 is required for private Tuya input provenance." >&2
  exit 3
}

if [[ ! -f Podfile ]]; then
  echo "ERROR: Podfile is missing at $REPO_ROOT/Podfile" >&2
  exit 4
fi

if [[ ! -d NembraCapture.xcodeproj ]]; then
  echo "ERROR: NembraCapture.xcodeproj is missing." >&2
  exit 5
fi

if [[ ! -f "$PROVENANCE_HELPER" || ! -f "$BUILD_SUBJECT_HELPER" ]]; then
  echo "ERROR: accepted Capture provenance/build-subject helper is missing from source." >&2
  exit 6
fi

# Tuya's SmartLife iOS SDK requires the app-specific security package generated
# for the exact Developer Platform app/bundle identity. It must never be
# replaced with a public placeholder or omitted just to make CocoaPods resolve.
if [[ ! -f "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" || ! -d "$TUYA_PRIVATE_SDK/Build" ]]; then
  cat >&2 <<EOF
ERROR: Tuya's app-specific iOS security SDK is not provisioned.

Expected private files:
  $TUYA_PRIVATE_SDK/ThingSmartCryption.podspec
  $TUYA_PRIVATE_SDK/Build/

On the Tuya Developer Platform, build/download the SmartLife iOS SDK for the
EXACT Nembra Capture Bundle ID, extract ios_core_sdk.tar.gz, and place its
ThingSmartCryption.podspec plus Build directory in:
  $TUYA_PRIVATE_SDK

LocalSecrets/ is git-ignored. Do not commit, paste, upload, or export this SDK,
AppKey/AppSecret, account tokens, device keys, or session material.
EOF
  exit 7
fi

if [[ ! -f "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" ||
      ! -d "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" ||
      ! -f "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift" ]]; then
  cat >&2 <<EOF
ERROR: Tuya's private app identity is not provisioned for the field workspace.

Run:
  Scripts/provision_capture_tuya_identity.sh

That script reads AppKey/AppSecret with terminal echo disabled and writes them
only beneath ignored LocalSecrets/TuyaRuntime as a local Swift pod. The values
must not be passed through xcodebuild/devicectl arguments or committed to Git.
EOF
  exit 8
fi

EXPECTED_GENERATED_BUILD_SUBJECT=""
if [[ "$REVIEW_ONLY" == "0" ]]; then
  [[ -f Podfile.lock ]] || {
    echo "ERROR: normal field bootstrap requires the exact preaccepted attested Podfile.lock from review-only resolution." >&2
    exit 16
  }
  PREINSTALL_LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
  [[ "$PREINSTALL_LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
    echo "ERROR: current Podfile.lock bytes do not match the preaccepted dependency/build-subject lock before CocoaPods runs." >&2
    exit 16
  }
  if ! EXPECTED_GENERATED_BUILD_SUBJECT="$(/usr/bin/python3 -I "$BUILD_SUBJECT_HELPER" read-attestation --lockfile "$REPO_ROOT/Podfile.lock")"; then
    echo "ERROR: preaccepted Podfile.lock does not carry one valid generated-build subject attestation." >&2
    exit 16
  fi
  [[ "$EXPECTED_GENERATED_BUILD_SUBJECT" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERROR: generated-build subject attestation is malformed." >&2
    exit 16
  }
fi

printf 'Resolving the official Tuya SmartLife iOS SDK and private field identity for Nembra Capture...\n'
# The reviewed lock now cryptographically binds both dependency resolution and
# the CocoaPods-generated build graph. Normal bootstrap starts from those exact
# accepted attested bytes, then requires pod install to reproduce the same graph.
pod install --repo-update

if [[ ! -d NembraCapture.xcworkspace || ! -d Pods ]]; then
  echo "ERROR: CocoaPods did not create both NembraCapture.xcworkspace and Pods." >&2
  exit 9
fi

if [[ ! -f Podfile.lock ]]; then
  echo "ERROR: CocoaPods did not create Podfile.lock; exact field dependency provenance is unavailable." >&2
  exit 10
fi

for expected in \
  "  - ThingSmartHomeKit (7.8.0)" \
  "  - ThingSmartBusinessExtensionKit (7.8.0)"
do
  if ! grep -Fq -- "$expected" Podfile.lock; then
    echo "ERROR: resolved Tuya SDK does not match the exact reviewed 7.8.0 field dependency: $expected" >&2
    exit 11
  fi
done

if ! OBSERVED_GENERATED_BUILD_SUBJECT="$(/usr/bin/python3 -I "$BUILD_SUBJECT_HELPER" fingerprint \
  --pods "$REPO_ROOT/Pods" \
  --workspace "$REPO_ROOT/NembraCapture.xcworkspace")"; then
  echo "ERROR: CocoaPods generated-build subject could not be fingerprinted safely." >&2
  exit 17
fi
[[ "$OBSERVED_GENERATED_BUILD_SUBJECT" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: CocoaPods generated-build subject fingerprint is malformed." >&2
  exit 17
}

# Review-only creates the authority candidate. Normal bootstrap restores the
# exact accepted attestation even on a mismatch so the accepted lock bytes do
# not silently mutate; the command still fails before xcodebuild below.
if [[ "$REVIEW_ONLY" == "1" ]]; then
  ATTESTED_GENERATED_BUILD_SUBJECT="$OBSERVED_GENERATED_BUILD_SUBJECT"
else
  ATTESTED_GENERATED_BUILD_SUBJECT="$EXPECTED_GENERATED_BUILD_SUBJECT"
fi
if ! /usr/bin/python3 -I "$BUILD_SUBJECT_HELPER" attest-lock \
  --lockfile "$REPO_ROOT/Podfile.lock" \
  --digest "$ATTESTED_GENERATED_BUILD_SUBJECT" >/dev/null
then
  echo "ERROR: Podfile.lock could not be bound to the generated CocoaPods build subject." >&2
  exit 17
fi

LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[[ "$LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: could not compute the Podfile.lock SHA-256 provenance fingerprint." >&2
  exit 13
}

if [[ "$REVIEW_ONLY" == "0" ]]; then
  [[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
    echo "ERROR: resolved/attested Podfile.lock does not reproduce the preaccepted dependency + generated-build subject. Stop before xcodebuild/install and review a new subject." >&2
    exit 16
  }
  [[ "$OBSERVED_GENERATED_BUILD_SUBJECT" == "$EXPECTED_GENERATED_BUILD_SUBJECT" ]] || {
    echo "ERROR: CocoaPods generated different build-affecting bytes under the exact preaccepted lock. Stop before xcodebuild; the generator/build graph is not the reviewed subject." >&2
    exit 17
  }
fi

# Snapshot every ignored private input that can materially change the field
# build. Podfile.lock now also carries the accepted generated-build fingerprint,
# so this existing private record inherits that binding without serializing SDK
# bytes, credentials, generated workspace contents, or device identifiers.
if ! /usr/bin/python3 -I "$PROVENANCE_HELPER" snapshot \
  --lockfile "$REPO_ROOT/Podfile.lock" \
  --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
  --security-build "$TUYA_PRIVATE_SDK/Build" \
  --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
  --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
  --record "$DEPENDENCY_PROVENANCE"
then
  echo "ERROR: exact private Tuya build-input provenance could not be snapshotted." >&2
  exit 12
fi

[[ -f "$DEPENDENCY_PROVENANCE" ]] || {
  echo "ERROR: private Tuya dependency provenance record was not created." >&2
  exit 14
}
[[ "$(stat -f '%Lp' "$DEPENDENCY_PROVENANCE" 2>/dev/null || true)" == "600" ]] || {
  echo "ERROR: private Tuya dependency provenance record is not mode 0600." >&2
  exit 15
}

if [[ "$REVIEW_ONLY" == "1" ]]; then
  cat <<EOF

DEPENDENCY + GENERATED BUILD SUBJECT CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY
  Attested Podfile.lock SHA-256: $LOCK_SHA256
  Generated CocoaPods build subject SHA-256: $OBSERVED_GENERATED_BUILD_SUBJECT
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

Review and bind this exact attested lock digest to the exact accepted Capture
source through the current Final-GO control plane before any field build/install.
The attested lock cryptographically binds both dependency resolution and the
actual generated Pods/workspace bytes. Then rerun normal bootstrap/installer
with that accepted digest as NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256.
This review-only mode never invokes xcodebuild, installs Nembra, scans Bluetooth,
or authorizes a physical attempt.
EOF
  exit 0
fi

printf 'Preaccepted Tuya dependency + generated-build lock matched: %s\n' "$LOCK_SHA256"
unset ACCEPTED_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 PREINSTALL_LOCK_SHA256 || true

cat <<EOF

Tuya SDK dependencies are integrated locally, including the app-specific
ThingSmartCryption package and local-only app identity pod.

Resolved dependency provenance:
  Attested Podfile.lock SHA-256: $LOCK_SHA256
  Generated CocoaPods build subject SHA-256: $OBSERVED_GENERATED_BUILD_SUBJECT
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

NEXT BUILD RULE:
  Open NembraCapture.xcworkspace, not NembraCapture.xcodeproj.
  Preserve this exact private-input fingerprint record with the field workspace.
  Do not run 'pod update', replace ThingSmartCryption, regenerate the private
  identity, or mutate Pods/workspace before an accepted physical capture; any
  input change is a new reviewed field-build candidate.

This bootstrap still does NOT authorize the physical experiment. The exact app
must consume the private identity pod, authorize the user's own SDK session,
prove exact scooter membership, receive a genuine structured application
update, and survive the canonical authenticated 45-second gate before
stationary mapping can unlock.
EOF
