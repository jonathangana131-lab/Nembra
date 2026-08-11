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
  : "${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 to the preaccepted lowercase/uppercase 64-hex Podfile.lock SHA-256 before field bootstrap. To create a candidate dependency subject without build authority, use --resolve-lock-for-review.}"
  [[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
  : "${NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 to the separately reviewed generated CocoaPods build-subject SHA-256 before field bootstrap.}"
  [[ "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 must be exactly 64 hex characters." >&2
    exit 17
  }
  ACCEPTED_BUILD_SUBJECT_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
  ACCEPTED_BUILD_SUBJECT_SHA256=""
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

if [[ ! -f "$PROVENANCE_HELPER" ]]; then
  echo "ERROR: private Tuya input provenance helper is missing from the accepted source." >&2
  exit 6
fi
if [[ ! -f "$BUILD_SUBJECT_HELPER" ]]; then
  echo "ERROR: CocoaPods generated build-subject helper is missing from the accepted source." >&2
  exit 18
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

# Normal field bootstrap must never let CocoaPods run against an unreviewed lock.
# Review mode is the only path allowed to resolve a candidate lock/build subject.
if [[ "$REVIEW_ONLY" == "0" ]]; then
  [[ -f Podfile.lock ]] || {
    echo "ERROR: reviewed Podfile.lock is absent. Resolve a dependency candidate for review before CocoaPods is allowed to run." >&2
    exit 19
  }
  PRE_POD_LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
  [[ "$PRE_POD_LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
    echo "ERROR: on-disk Podfile.lock does not match reviewed authority; CocoaPods was not started." >&2
    exit 20
  }
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

# CocoaPods-generated support/workspace bytes are part of the executable build
# subject, not merely a consequence of the reviewed resolver lock. Local path pod
# symlinks are admitted only into the two separately-provenanced private roots.
if ! COCOAPODS_BUILD_SUBJECT_SHA256="$(/usr/bin/python3 -I "$BUILD_SUBJECT_HELPER" \
  --pods "$REPO_ROOT/Pods" \
  --workspace "$REPO_ROOT/NembraCapture.xcworkspace" \
  --externally-custodied-root "$TUYA_PRIVATE_SDK" \
  --externally-custodied-root "$TUYA_PRIVATE_IDENTITY")"
then
  echo "ERROR: CocoaPods generated build subject could not be fingerprinted." >&2
  exit 21
fi
[[ "$COCOAPODS_BUILD_SUBJECT_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: CocoaPods generated build-subject fingerprint is malformed." >&2
  exit 22
}

# Snapshot every ignored input that can materially change the private field
# build. The helper writes only SHA-256 fingerprints + public reviewed versions;
# it never serializes credentials, SDK bytes, or device identifiers.
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

LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[[ "$LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: could not compute the Podfile.lock SHA-256 provenance fingerprint." >&2
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

DEPENDENCY BUILD SUBJECT CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build-subject SHA-256: $COCOAPODS_BUILD_SUBJECT_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

Review and bind both exact dependency digests to the exact accepted Capture
source through the current Final-GO control plane before any field build/install.
Then rerun the normal bootstrap/installer with those accepted digests supplied as
NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 and
NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256. This review-only mode never invokes
xcodebuild, installs Nembra, scans Bluetooth, or authorizes a physical attempt.
EOF
  exit 0
fi

[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
  echo "ERROR: resolved Podfile.lock does not match the preaccepted dependency-lock SHA-256. Stop before xcodebuild/install and review the new dependency subject." >&2
  exit 16
}
[[ "$COCOAPODS_BUILD_SUBJECT_SHA256" == "$ACCEPTED_BUILD_SUBJECT_SHA256" ]] || {
  echo "ERROR: generated CocoaPods build subject does not match separately reviewed authority. Stop before xcodebuild/install and review the new generated build subject." >&2
  exit 23
}
printf 'Preaccepted Tuya dependency lock matched: %s\n' "$LOCK_SHA256"
printf 'Preaccepted CocoaPods generated build subject matched: %s\n' "$COCOAPODS_BUILD_SUBJECT_SHA256"
unset ACCEPTED_LOCK_SHA256 ACCEPTED_BUILD_SUBJECT_SHA256 NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 || true

cat <<EOF

Tuya SDK dependencies are integrated locally, including the app-specific
ThingSmartCryption package and local-only app identity pod.

Resolved dependency provenance:
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build-subject SHA-256: $COCOAPODS_BUILD_SUBJECT_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

NEXT BUILD RULE:
  Open NembraCapture.xcworkspace, not NembraCapture.xcodeproj.
  Preserve this exact private-input fingerprint record with the field workspace.
  Do not run 'pod update', replace ThingSmartCryption, regenerate the private
  identity, or regenerate CocoaPods support/workspace bytes before an accepted
  physical capture; any input/build-subject change is a new reviewed field-build
  candidate and must earn new exact-head acceptance.

This bootstrap still does NOT authorize the physical experiment. The exact app
must consume the private identity pod, authorize the user's own SDK session,
prove exact scooter membership, receive a genuine structured application
update, and survive the canonical authenticated 45-second gate before
stationary mapping can unlock.
EOF
