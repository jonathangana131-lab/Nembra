#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TUYA_PRIVATE_SDK="$REPO_ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$REPO_ROOT/LocalSecrets/TuyaRuntime"
DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"
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
  [[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  [[ "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
  ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
  ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256=""
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

if [[ ! -f "$PROVENANCE_HELPER" ]]; then
  echo "ERROR: private Tuya input provenance helper is missing from the accepted source." >&2
  exit 6
fi

if [[ ! -f "$GENERATED_BUILD_SUBJECT_HELPER" ]]; then
  echo "ERROR: generated CocoaPods build-subject helper is missing from the accepted source." >&2
  exit 6
fi

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
  if ! command -v pod >/dev/null 2>&1; then
    cat >&2 <<'EOF'
ERROR: CocoaPods is not installed.

Review-only candidate generation intentionally uses CocoaPods to create the
exact dependency/build subject that will later be reviewed. Install CocoaPods
on the development Mac, then run this review-only command again. Do not copy
SDK binaries or private Tuya credentials into git.
EOF
    exit 2
  fi

  printf 'Resolving one review-only Tuya/CocoaPods candidate for Nembra Capture...\n'
  pod install --repo-update
else
  printf 'Verifying the already-reviewed Tuya/CocoaPods field build subject...\n'
fi

if [[ ! -d NembraCapture.xcworkspace ]]; then
  echo "ERROR: NembraCapture.xcworkspace is unavailable. Create/review the candidate first with --resolve-lock-for-review; normal field bootstrap never regenerates it." >&2
  exit 9
fi

if [[ ! -d Pods ]]; then
  echo "ERROR: Pods/ is unavailable. Create/review the candidate first with --resolve-lock-for-review; normal field bootstrap never regenerates it." >&2
  exit 9
fi

if [[ ! -f Podfile.lock ]]; then
  echo "ERROR: Podfile.lock is unavailable. Create/review the candidate first with --resolve-lock-for-review; normal field bootstrap never regenerates it." >&2
  exit 10
fi

LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[[ "$LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: could not compute the Podfile.lock SHA-256 provenance fingerprint." >&2
  exit 13
}

if [[ "$REVIEW_ONLY" == "0" && "$LOCK_SHA256" != "$ACCEPTED_LOCK_SHA256" ]]; then
  echo "ERROR: existing Podfile.lock does not match the preaccepted dependency-lock SHA-256. Normal field bootstrap will not run CocoaPods or mutate the candidate; review a new subject explicitly." >&2
  exit 16
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

DEPENDENCY + GENERATED BUILD CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build subject SHA-256: $GENERATED_BUILD_SUBJECT_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

Review and bind BOTH exact digests to the exact accepted Capture source through
the current Final-GO control plane before any field build/install. Preserve this
same generated workspace. Then rerun the normal bootstrap/installer with those
accepted digests supplied as NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 and
NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256. Normal field bootstrap
will verify this exact subject in place and will not invoke CocoaPods again.
This review-only mode never invokes xcodebuild, installs Nembra, scans Bluetooth,
or authorizes a physical attempt.
EOF
  exit 0
fi

[[ "$GENERATED_BUILD_SUBJECT_SHA256" == "$ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256" ]] || {
  echo "ERROR: existing CocoaPods generated build inputs do not match the preaccepted generated-build subject SHA-256. Normal field bootstrap will not regenerate them; stop before xcodebuild/install and review a new build subject." >&2
  exit 17
}
printf 'Preaccepted Tuya dependency lock matched: %s\n' "$LOCK_SHA256"
printf 'Preaccepted CocoaPods generated build subject matched: %s\n' "$GENERATED_BUILD_SUBJECT_SHA256"
unset ACCEPTED_LOCK_SHA256 ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256 \
  NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 \
  NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 || true

cat <<EOF

The exact pre-reviewed Tuya SDK/CocoaPods field subject is present locally,
including the app-specific ThingSmartCryption package and local-only app identity
pod. Normal field bootstrap did not run CocoaPods or regenerate dependency bytes.

Verified dependency provenance:
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build subject SHA-256: $GENERATED_BUILD_SUBJECT_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

NEXT BUILD RULE:
  Open NembraCapture.xcworkspace, not NembraCapture.xcodeproj.
  Preserve this exact private-input fingerprint record and accepted generated
  build-subject digest with the field workspace.
  Do not run 'pod install', 'pod update', replace ThingSmartCryption, regenerate
  the private identity, or regenerate CocoaPods inputs before an accepted
  physical capture; any input change is a new reviewed field-build candidate and
  must earn new exact-head authority through review-only candidate generation.

This bootstrap still does NOT authorize the physical experiment. The exact app
must consume the private identity pod, authorize the user's own SDK session,
prove exact scooter membership, receive a genuine structured application
update, and survive the canonical authenticated 45-second gate before
stationary mapping can unlock.
EOF
