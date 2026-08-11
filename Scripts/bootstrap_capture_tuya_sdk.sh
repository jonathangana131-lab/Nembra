#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TUYA_PRIVATE_SDK="$REPO_ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$REPO_ROOT/LocalSecrets/TuyaRuntime"
DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
PRIVATE_REVIEW_KEY="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyReview.key"
PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"
PRIVATE_REVIEW_HELPER="$SCRIPT_DIR/capture_tuya_private_review_commitment.py"
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
  : "${NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256 to the owner-reviewed 64-hex opaque private-input commitment before field bootstrap. To create a candidate without build authority, use --resolve-lock-for-review.}"
  for value in \
    "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" \
    "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" \
    "$NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256"
  do
    [[ "$value" =~ ^[0-9A-Fa-f]{64}$ ]] || {
      echo "ERROR: every accepted field-build review subject must be exactly 64 hex characters." >&2
      exit 1
    }
  done
  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
  ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" | tr '[:upper:]' '[:lower:]')"
  ACCEPTED_PRIVATE_REVIEW_HMAC_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 \
    NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 \
    NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
  ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256=""
  ACCEPTED_PRIVATE_REVIEW_HMAC_SHA256=""
fi

[[ -x /usr/bin/python3 ]] || {
  echo "ERROR: System Python 3 is required for private Tuya input provenance." >&2
  exit 3
}
[[ -f Podfile ]] || {
  echo "ERROR: Podfile is missing at $REPO_ROOT/Podfile" >&2
  exit 4
}
[[ -d NembraCapture.xcodeproj ]] || {
  echo "ERROR: NembraCapture.xcodeproj is missing." >&2
  exit 5
}
for helper in "$PROVENANCE_HELPER" "$PRIVATE_REVIEW_HELPER" "$GENERATED_BUILD_SUBJECT_HELPER"; do
  [[ -f "$helper" ]] || {
    echo "ERROR: required Capture build-authority helper is missing from the accepted source: $(basename "$helper")" >&2
    exit 6
  }
done

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

if [[ "$REVIEW_ONLY" == "1" ]]; then
  command -v pod >/dev/null 2>&1 || {
    echo "ERROR: CocoaPods is required only to create an explicit review candidate." >&2
    exit 2
  }
  printf 'Resolving one review-only Tuya/CocoaPods candidate for Nembra Capture...\n'
  pod install --repo-update
else
  printf 'Verifying the already-reviewed Tuya/CocoaPods field build subject without regeneration...\n'
fi

[[ -d NembraCapture.xcworkspace ]] || {
  echo "ERROR: NembraCapture.xcworkspace is unavailable. Create/review a candidate with --resolve-lock-for-review; normal field bootstrap never regenerates it." >&2
  exit 9
}
[[ -d Pods ]] || {
  echo "ERROR: Pods/ is unavailable. Create/review a candidate with --resolve-lock-for-review; normal field bootstrap never regenerates it." >&2
  exit 9
}
[[ -f Podfile.lock ]] || {
  echo "ERROR: Podfile.lock is unavailable. Create/review a candidate with --resolve-lock-for-review; normal field bootstrap never regenerates it." >&2
  exit 10
}

LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[[ "$LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: could not compute the Podfile.lock SHA-256 provenance fingerprint." >&2
  exit 13
}
if [[ "$REVIEW_ONLY" == "0" && "$LOCK_SHA256" != "$ACCEPTED_LOCK_SHA256" ]]; then
  echo "ERROR: existing Podfile.lock does not match the preaccepted dependency-lock SHA-256. Normal field bootstrap will not run CocoaPods or mutate the candidate." >&2
  exit 16
fi

for expected in \
  "  - ThingSmartHomeKit (7.8.0)" \
  "  - ThingSmartBusinessExtensionKit (7.8.0)"
do
  grep -Fq -- "$expected" Podfile.lock || {
    echo "ERROR: resolved Tuya SDK does not match the exact reviewed 7.8.0 field dependency: $expected" >&2
    exit 11
  }
done

if [[ "$REVIEW_ONLY" == "1" ]]; then
  /usr/bin/python3 -I "$PROVENANCE_HELPER" snapshot \
    --lockfile "$REPO_ROOT/Podfile.lock" \
    --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
    --security-build "$TUYA_PRIVATE_SDK/Build" \
    --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
    --record "$DEPENDENCY_PROVENANCE" || {
      echo "ERROR: exact private Tuya build-input provenance could not be snapshotted for review." >&2
      exit 12
    }
  PRIVATE_REVIEW_HMAC_SHA256="$(/usr/bin/python3 -I "$PRIVATE_REVIEW_HELPER" create \
    --repository-root "$REPO_ROOT" \
    --witness "$DEPENDENCY_PROVENANCE" \
    --key-file "$PRIVATE_REVIEW_KEY")" || {
      echo "ERROR: opaque private-input review commitment could not be created." >&2
      exit 12
    }
else
  [[ -f "$DEPENDENCY_PROVENANCE" && -f "$PRIVATE_REVIEW_KEY" ]] || {
    echo "ERROR: reviewed private-input witness/key is missing. Normal field bootstrap never creates or replaces review authority." >&2
    exit 12
  }
  /usr/bin/python3 -I "$PROVENANCE_HELPER" verify \
    --lockfile "$REPO_ROOT/Podfile.lock" \
    --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
    --security-build "$TUYA_PRIVATE_SDK/Build" \
    --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
    --record "$DEPENDENCY_PROVENANCE" || {
      echo "ERROR: current private Tuya inputs do not match the reviewed local continuity witness." >&2
      exit 12
    }
  /usr/bin/python3 -I "$PRIVATE_REVIEW_HELPER" verify \
    --repository-root "$REPO_ROOT" \
    --witness "$DEPENDENCY_PROVENANCE" \
    --key-file "$PRIVATE_REVIEW_KEY" \
    --accepted-tag "$ACCEPTED_PRIVATE_REVIEW_HMAC_SHA256" || {
      echo "ERROR: private Tuya field inputs do not match the owner-reviewed opaque commitment." >&2
      exit 12
    }
  PRIVATE_REVIEW_HMAC_SHA256="$ACCEPTED_PRIVATE_REVIEW_HMAC_SHA256"
fi
[[ "$PRIVATE_REVIEW_HMAC_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: private review helper did not return one lowercase SHA-256 HMAC tag." >&2
  exit 12
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
  cat <<EOF

DEPENDENCY + PRIVATE + GENERATED BUILD CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build subject SHA-256: $GENERATED_BUILD_SUBJECT_SHA256
  Private-input review HMAC-SHA256: $PRIVATE_REVIEW_HMAC_SHA256
  Local private-input witness: $DEPENDENCY_PROVENANCE
  Local private review key: retained privately; bytes are never printed

Review and bind all THREE public subjects to the exact accepted Capture source
through the current Final-GO control plane before any field build/install. Keep
the local witness, private review key, and generated workspace unchanged. Then
rerun normal bootstrap with NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256,
NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256, and
NEMBRA_CAPTURE_ACCEPTED_TUYA_PRIVATE_REVIEW_HMAC_SHA256. Normal field bootstrap
is verification-only: it never runs CocoaPods, snapshots private inputs, rotates
the key, invokes xcodebuild, installs Nembra, scans Bluetooth, or authorizes a
physical attempt.
EOF
  exit 0
fi

[[ "$GENERATED_BUILD_SUBJECT_SHA256" == "$ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256" ]] || {
  echo "ERROR: existing CocoaPods generated build inputs do not match the preaccepted generated-build subject SHA-256. Normal field bootstrap will not regenerate them." >&2
  exit 17
}
printf 'Preaccepted Tuya dependency lock matched: %s\n' "$LOCK_SHA256"
printf 'Preaccepted CocoaPods generated build subject matched: %s\n' "$GENERATED_BUILD_SUBJECT_SHA256"
printf 'Owner-reviewed opaque private-input commitment matched: %s\n' "$PRIVATE_REVIEW_HMAC_SHA256"
unset ACCEPTED_LOCK_SHA256 ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256 \
  ACCEPTED_PRIVATE_REVIEW_HMAC_SHA256 || true

cat <<EOF

The exact pre-reviewed Tuya SDK/CocoaPods/private field subject is present
locally. Normal field bootstrap did not regenerate dependency bytes or rewrite
private review authority.

Verified dependency provenance:
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build subject SHA-256: $GENERATED_BUILD_SUBJECT_SHA256
  Private-input review HMAC-SHA256: $PRIVATE_REVIEW_HMAC_SHA256

NEXT BUILD RULE:
  Open NembraCapture.xcworkspace, not NembraCapture.xcodeproj.
  Preserve the exact private witness/key and generated workspace through the
  guarded build. Any private input, witness/key, lock, Pods, or workspace change
  is a new review candidate and must earn new exact-head authority.

This bootstrap still does NOT authorize the physical experiment. The exact app
must consume the private identity pod, authorize the user's own SDK session,
prove exact scooter membership, receive a genuine structured application
update, and survive the canonical authenticated 45-second gate before
stationary mapping can unlock.
EOF
