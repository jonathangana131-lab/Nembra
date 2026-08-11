#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TUYA_PRIVATE_SDK="$REPO_ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$REPO_ROOT/LocalSecrets/TuyaRuntime"
DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
PRIVATE_REVIEW_KEY="$TUYA_PRIVATE_IDENTITY/PrivateInputReviewKey.bin"
PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"
PRIVATE_REVIEW_HELPER="$SCRIPT_DIR/capture_tuya_private_input_review.py"
GENERATED_BUILD_SUBJECT_HELPER="$SCRIPT_DIR/capture_cocoapods_generated_build_subject.py"
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
  : "${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 to the preaccepted 64-hex Podfile.lock SHA-256 before field bootstrap. To create a candidate dependency subject without build authority, use --resolve-lock-for-review.}"
  : "${NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 to the preaccepted 64-hex generated CocoaPods build-subject SHA-256 before field bootstrap. To create a candidate generated subject without build authority, use --resolve-lock-for-review.}"
  : "${NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT:?Set NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT to the exact opaque lowercase 64-hex private-input review commitment produced by review-only bootstrap.}"
  [[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  [[ "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  [[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT must be canonical lowercase 64-hex authority." >&2
    exit 1
  }
  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
  ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" | tr '[:upper:]' '[:lower:]')"
  ACCEPTED_PRIVATE_INPUT_COMMITMENT="$NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 \
    NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 \
    NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT || true
  ACCEPTED_LOCK_SHA256=""
  ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256=""
  ACCEPTED_PRIVATE_INPUT_COMMITMENT=""
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

if [[ ! -f "$PROVENANCE_HELPER" || ! -f "$PRIVATE_REVIEW_HELPER" ]]; then
  echo "ERROR: private Tuya provenance/review helper is missing from the accepted source." >&2
  exit 6
fi

if [[ ! -f "$GENERATED_BUILD_SUBJECT_HELPER" ]]; then
  echo "ERROR: generated CocoaPods build-subject helper is missing from the accepted source." >&2
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

if [[ "$REVIEW_ONLY" == "0" ]]; then
  [[ -f "$REPO_ROOT/Podfile.lock" ]] || {
    echo "ERROR: normal field bootstrap requires the exact reviewed Podfile.lock before private-input admission." >&2
    exit 16
  }
  PREINSTALL_LOCK_SHA256="$(shasum -a 256 "$REPO_ROOT/Podfile.lock" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
  [[ "$PREINSTALL_LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
    echo "ERROR: current Podfile.lock does not match preaccepted authority before private inputs/CocoaPods can be consumed." >&2
    exit 16
  }
  if ! /usr/bin/python3 -I "$PRIVATE_REVIEW_HELPER" verify \
    --lockfile "$REPO_ROOT/Podfile.lock" \
    --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
    --security-build "$TUYA_PRIVATE_SDK/Build" \
    --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
    --record "$DEPENDENCY_PROVENANCE" \
    --key "$PRIVATE_REVIEW_KEY" \
    --accepted-commitment "$ACCEPTED_PRIVATE_INPUT_COMMITMENT" >/dev/null
  then
    echo "ERROR: current private Tuya SDK/app-identity generation is not the externally reviewed field-build subject. Stop before CocoaPods/xcodebuild." >&2
    exit 18
  fi
fi

printf 'Resolving the official Tuya SmartLife iOS SDK and private field identity for Nembra Capture...\n'
# `pod install` preserves an existing Podfile.lock instead of silently upgrading
# resolved transitive SDK inputs. `--repo-update` refreshes specs only; the two
# public Tuya products themselves are exact-pinned in Podfile at 7.8.0.
pod install --repo-update

if [[ ! -d NembraCapture.xcworkspace ]]; then
  echo "ERROR: CocoaPods did not create NembraCapture.xcworkspace." >&2
  exit 9
fi
if [[ ! -d Pods ]]; then
  echo "ERROR: CocoaPods did not create Pods/; generated field build authority is unavailable." >&2
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

LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[[ "$LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: could not compute the Podfile.lock SHA-256 provenance fingerprint." >&2
  exit 13
}

if ! GENERATED_BUILD_SUBJECT_SHA256="$(/usr/bin/python3 -I "$GENERATED_BUILD_SUBJECT_HELPER" \
  --lockfile "$REPO_ROOT/Podfile.lock" \
  --pods "$REPO_ROOT/Pods" \
  --workspace "$REPO_ROOT/NembraCapture.xcworkspace")"
then
  echo "ERROR: exact generated CocoaPods build subject could not be fingerprinted." >&2
  exit 13
fi
[[ "$GENERATED_BUILD_SUBJECT_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: generated CocoaPods build-subject helper did not return one lowercase SHA-256." >&2
  exit 13
}

if [[ "$REVIEW_ONLY" == "1" ]]; then
  # Review-only is the sole authority-creation phase for ignored/private build
  # inputs. Normal field bootstrap never rewrites this witness.
  if ! PRIVATE_INPUT_REVIEW_COMMITMENT="$(/usr/bin/python3 -I "$PRIVATE_REVIEW_HELPER" review \
    --lockfile "$REPO_ROOT/Podfile.lock" \
    --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
    --security-build "$TUYA_PRIVATE_SDK/Build" \
    --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
    --record "$DEPENDENCY_PROVENANCE" \
    --key "$PRIVATE_REVIEW_KEY")"
  then
    echo "ERROR: exact private Tuya review witness could not be created." >&2
    exit 12
  fi
else
  [[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
    echo "ERROR: resolved Podfile.lock does not match the preaccepted dependency-lock SHA-256. Stop before xcodebuild/install and review the new dependency subject." >&2
    exit 16
  }
  [[ "$GENERATED_BUILD_SUBJECT_SHA256" == "$ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256" ]] || {
    echo "ERROR: generated CocoaPods build inputs do not match the preaccepted generated-build subject SHA-256. Stop before xcodebuild/install and review the new build subject." >&2
    exit 17
  }
  if ! PRIVATE_INPUT_REVIEW_COMMITMENT="$(/usr/bin/python3 -I "$PRIVATE_REVIEW_HELPER" verify \
    --lockfile "$REPO_ROOT/Podfile.lock" \
    --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
    --security-build "$TUYA_PRIVATE_SDK/Build" \
    --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
    --record "$DEPENDENCY_PROVENANCE" \
    --key "$PRIVATE_REVIEW_KEY" \
    --accepted-commitment "$ACCEPTED_PRIVATE_INPUT_COMMITMENT")"
  then
    echo "ERROR: private Tuya SDK/app-identity inputs changed after external review. Stop before xcodebuild/install." >&2
    exit 18
  fi
fi
[[ "$PRIVATE_INPUT_REVIEW_COMMITMENT" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: private-input review commitment is malformed." >&2
  exit 18
}

[[ -f "$DEPENDENCY_PROVENANCE" && -f "$PRIVATE_REVIEW_KEY" ]] || {
  echo "ERROR: private Tuya review witness/key was not created." >&2
  exit 14
}
[[ "$(stat -f '%Lp' "$DEPENDENCY_PROVENANCE" 2>/dev/null || true)" == "600" ]] || {
  echo "ERROR: private Tuya dependency provenance record is not mode 0600." >&2
  exit 15
}
[[ "$(stat -f '%Lp' "$PRIVATE_REVIEW_KEY" 2>/dev/null || true)" == "600" ]] || {
  echo "ERROR: private Tuya review key is not mode 0600." >&2
  exit 15
}

if [[ "$REVIEW_ONLY" == "1" ]]; then
  cat <<EOF

DEPENDENCY LOCK CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY
  Generated CocoaPods build subject and private Tuya input commitment are part of this same review candidate.
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build subject SHA-256: $GENERATED_BUILD_SUBJECT_SHA256
  Private Tuya input review commitment: $PRIVATE_INPUT_REVIEW_COMMITMENT
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE
  Local private review key: protected mode-0600 material (never export)

Review and bind all THREE exact public/opaque authority values to the exact
accepted Capture source through the current Final-GO control plane before any
field build/install. Then rerun the normal bootstrap/installer with them as
NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256,
NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256, and
NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_INPUT_COMMITMENT. The private commitment is
HMAC-keyed by random local material so Final-GO never needs the raw AppKey,
AppSecret, SDK bytes, local key, or direct credential-derived fingerprints.
This review-only mode never invokes xcodebuild, installs Nembra, scans Bluetooth,
or authorizes a physical attempt.
EOF
  exit 0
fi

[[ "$PRIVATE_INPUT_REVIEW_COMMITMENT" == "$ACCEPTED_PRIVATE_INPUT_COMMITMENT" ]] || {
  echo "ERROR: private-input review commitment drifted during normal bootstrap." >&2
  exit 18
}
printf 'Preaccepted Tuya dependency lock matched: %s\n' "$LOCK_SHA256"
printf 'Preaccepted CocoaPods generated build subject matched: %s\n' "$GENERATED_BUILD_SUBJECT_SHA256"
printf 'Preaccepted private Tuya input review commitment matched: %s\n' "$PRIVATE_INPUT_REVIEW_COMMITMENT"
unset ACCEPTED_LOCK_SHA256 ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256 \
  ACCEPTED_PRIVATE_INPUT_COMMITMENT PREINSTALL_LOCK_SHA256 \
  NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 \
  NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 || true

cat <<EOF

Tuya SDK dependencies are integrated locally, including the app-specific
ThingSmartCryption package and local-only app identity pod.

Resolved dependency provenance:
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build subject SHA-256: $GENERATED_BUILD_SUBJECT_SHA256
  Private Tuya input review commitment: $PRIVATE_INPUT_REVIEW_COMMITMENT
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

NEXT BUILD RULE:
  Open NembraCapture.xcworkspace, not NembraCapture.xcodeproj.
  Preserve this exact private-input witness/key and both accepted public build
  digests with the field workspace. Do not run 'pod update', replace
  ThingSmartCryption, regenerate the private identity, or regenerate CocoaPods
  inputs before an accepted physical capture; any input change is a new reviewed
  field-build candidate and must earn new exact-head acceptance.

This bootstrap still does NOT authorize the physical experiment. The exact app
must consume the private identity pod, authorize the user's own SDK session,
prove exact scooter membership, receive a genuine structured application
update, and survive the canonical authenticated 45-second gate before
stationary mapping can unlock.
EOF
