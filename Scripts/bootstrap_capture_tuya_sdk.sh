#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TUYA_PRIVATE_SDK="$REPO_ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$REPO_ROOT/LocalSecrets/TuyaRuntime"
DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"
PRIVATE_INPUT_RESOLUTION_GUARD="$SCRIPT_DIR/capture_tuya_private_input_build_guard.py"
PRIVATE_IDENTITY_AUTHORITY_HELPER="$SCRIPT_DIR/capture_tuya_private_identity_authority.py"
PRIVATE_IDENTITY_AUTHORITY_HELPER_SHA256="40f5aee5c5e39c0a6146ba2ca7bc6bad7cf6abd6576fff8835d02f714589ae71"
PRIVATE_IDENTITY_WRITER_SHA256="6a27f9f0640a00dfe5f74a1cc4a65a0faf76994fe584efe23afb8f7ee1638fc2"
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
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
fi

# CocoaPods must never admit LocalSecrets identity bytes solely because they
# occupy the canonical path. Capture and pin the verifier from accepted source,
# then require a root-sealed receipt from the last successful transaction before
# executable discovery or dependency resolution.
[[ -f "$PRIVATE_IDENTITY_AUTHORITY_HELPER" && ! -L "$PRIVATE_IDENTITY_AUTHORITY_HELPER" ]] || {
  echo "ERROR: private identity authority helper is missing from accepted source." >&2
  exit 17
}
AUTHORITY_CAPTURE="$({ /bin/cat -- "$PRIVATE_IDENTITY_AUTHORITY_HELPER"; printf '\001'; })"
[[ "$AUTHORITY_CAPTURE" == *$'\001' ]] || {
  unset AUTHORITY_CAPTURE
  echo "ERROR: private identity authority helper could not be captured." >&2
  exit 17
}
AUTHORITY_SOURCE="${AUTHORITY_CAPTURE%$'\001'}"
unset AUTHORITY_CAPTURE
CAPTURED_AUTHORITY_SHA256="$(printf '%s' "$AUTHORITY_SOURCE" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
[[ "$CAPTURED_AUTHORITY_SHA256" == "$PRIVATE_IDENTITY_AUTHORITY_HELPER_SHA256" ]] || {
  unset AUTHORITY_SOURCE CAPTURED_AUTHORITY_SHA256
  echo "ERROR: private identity authority helper bytes do not match accepted source." >&2
  exit 17
}
unset CAPTURED_AUTHORITY_SHA256
if ! /usr/bin/python3 -I -c "$AUTHORITY_SOURCE" verify "$REPO_ROOT" "$PRIVATE_IDENTITY_WRITER_SHA256" >/dev/null; then
  unset AUTHORITY_SOURCE
  echo "ERROR: private app identity is not backed by the root-sealed last successful provisioning transaction. Run Scripts/provision_capture_tuya_identity.sh successfully before bootstrap." >&2
  exit 17
fi

POD_BIN="$(command -v pod || true)"
if [[ -z "$POD_BIN" || ! -x "$POD_BIN" ]]; then
  unset AUTHORITY_SOURCE
  cat >&2 <<'EOF'
ERROR: CocoaPods is not installed.

Nembra Capture's authenticated Tuya BLE path intentionally uses Tuya's official
SmartLife App SDK. Install CocoaPods on the development Mac, then run this
script again. Do not copy SDK binaries or private Tuya credentials into git.
EOF
  exit 2
fi

[[ -x /usr/bin/python3 ]] || {
  unset AUTHORITY_SOURCE
  echo "ERROR: System Python 3 is required for private Tuya input provenance." >&2
  exit 3
}

if [[ ! -f Podfile ]]; then
  unset AUTHORITY_SOURCE
  echo "ERROR: Podfile is missing at $REPO_ROOT/Podfile" >&2
  exit 4
fi

if [[ ! -d NembraCapture.xcodeproj ]]; then
  unset AUTHORITY_SOURCE
  echo "ERROR: NembraCapture.xcodeproj is missing." >&2
  exit 5
fi

if [[ ! -f "$PROVENANCE_HELPER" ]]; then
  unset AUTHORITY_SOURCE
  echo "ERROR: private Tuya input provenance helper is missing from the accepted source." >&2
  exit 6
fi

if [[ ! -f "$PRIVATE_INPUT_RESOLUTION_GUARD" || -L "$PRIVATE_INPUT_RESOLUTION_GUARD" ]]; then
  unset AUTHORITY_SOURCE
  echo "ERROR: private-input vnode custody guard is missing from the accepted source." >&2
  exit 6
fi

# Tuya's SmartLife iOS SDK requires the app-specific security package generated
# for the exact Developer Platform app/bundle identity. It must never be
# replaced with a public placeholder or omitted just to make CocoaPods resolve.
if [[ ! -f "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" || ! -d "$TUYA_PRIVATE_SDK/Build" ]]; then
  unset AUTHORITY_SOURCE
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
  unset AUTHORITY_SOURCE
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

# The existing field-build guard is generic vnode custody: its --lockfile slot
# is a watched regular-file anchor. During dependency resolution we deliberately
# use the tracked Podfile as that stable anchor because CocoaPods itself executes
# the Podfile while the private SDK/identity inputs are read. The child re-verifies
# the root-sealed identity receipt only after every watcher is armed, then runs
# CocoaPods under the same watcher set. A swap/restore race therefore cannot turn
# unsealed podspec/source bytes into dependency-resolution authority.
AUTHORITY_REVERIFY_AND_EXEC='set -euo pipefail
AUTHORITY_SOURCE_INNER="$1"
REPO_ROOT_INNER="$2"
WRITER_SHA_INNER="$3"
shift 3
/usr/bin/python3 -I -c "$AUTHORITY_SOURCE_INNER" verify "$REPO_ROOT_INNER" "$WRITER_SHA_INNER" >/dev/null
exec "$@"'

printf 'Resolving the official Tuya SmartLife iOS SDK and private field identity for Nembra Capture...\n'
# `pod install` preserves an existing Podfile.lock instead of silently upgrading
# resolved transitive SDK inputs. `--repo-update` refreshes specs only; the two
# public Tuya products themselves are exact-pinned in Podfile at 7.8.0.
if ! /usr/bin/python3 -I "$PRIVATE_INPUT_RESOLUTION_GUARD" \
  --lockfile "$REPO_ROOT/Podfile" \
  --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
  --security-build "$TUYA_PRIVATE_SDK/Build" \
  --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
  --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
  -- /bin/bash -c "$AUTHORITY_REVERIFY_AND_EXEC" _ \
     "$AUTHORITY_SOURCE" "$REPO_ROOT" "$PRIVATE_IDENTITY_WRITER_SHA256" \
     "$POD_BIN" install --repo-update
then
  unset AUTHORITY_SOURCE AUTHORITY_REVERIFY_AND_EXEC
  echo "ERROR: private-input custody rejected guarded CocoaPods dependency resolution." >&2
  exit 18
fi

if [[ ! -d NembraCapture.xcworkspace ]]; then
  unset AUTHORITY_SOURCE AUTHORITY_REVERIFY_AND_EXEC
  echo "ERROR: CocoaPods did not create NembraCapture.xcworkspace." >&2
  exit 9
fi

if [[ ! -f Podfile.lock ]]; then
  unset AUTHORITY_SOURCE AUTHORITY_REVERIFY_AND_EXEC
  echo "ERROR: CocoaPods did not create Podfile.lock; exact field dependency provenance is unavailable." >&2
  exit 10
fi

for expected in \
  "  - ThingSmartHomeKit (7.8.0)" \
  "  - ThingSmartBusinessExtensionKit (7.8.0)"
do
  if ! grep -Fq -- "$expected" Podfile.lock; then
    unset AUTHORITY_SOURCE AUTHORITY_REVERIFY_AND_EXEC
    echo "ERROR: resolved Tuya SDK does not match the exact reviewed 7.8.0 field dependency: $expected" >&2
    exit 11
  fi
done

# Snapshot every ignored input that can materially change the private field
# build. Re-arm the same vnode custody and re-verify the root receipt inside that
# watched window before running the snapshot helper. The resulting record can
# therefore only describe the same sealed private generation admitted by the
# successful transaction; the field installer independently verifies it again.
if ! /usr/bin/python3 -I "$PRIVATE_INPUT_RESOLUTION_GUARD" \
  --lockfile "$REPO_ROOT/Podfile" \
  --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
  --security-build "$TUYA_PRIVATE_SDK/Build" \
  --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
  --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
  -- /bin/bash -c "$AUTHORITY_REVERIFY_AND_EXEC" _ \
     "$AUTHORITY_SOURCE" "$REPO_ROOT" "$PRIVATE_IDENTITY_WRITER_SHA256" \
     /usr/bin/python3 -I "$PROVENANCE_HELPER" snapshot \
       --lockfile "$REPO_ROOT/Podfile.lock" \
       --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
       --security-build "$TUYA_PRIVATE_SDK/Build" \
       --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
       --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
       --record "$DEPENDENCY_PROVENANCE"
then
  unset AUTHORITY_SOURCE AUTHORITY_REVERIFY_AND_EXEC
  echo "ERROR: exact private Tuya build-input provenance could not be snapshotted under vnode custody." >&2
  exit 12
fi
unset AUTHORITY_SOURCE AUTHORITY_REVERIFY_AND_EXEC

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

DEPENDENCY LOCK CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY
  Podfile.lock SHA-256: $LOCK_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

Review and bind this exact dependency-lock digest to the exact accepted Capture
source through the current Final-GO control plane before any field build/install.
Then rerun the normal bootstrap/installer with that accepted digest supplied as
NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256. This review-only mode never invokes
xcodebuild, installs Nembra, scans Bluetooth, or authorizes a physical attempt.
EOF
  exit 0
fi

[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
  echo "ERROR: resolved Podfile.lock does not match the preaccepted dependency-lock SHA-256. Stop before xcodebuild/install and review the new dependency subject." >&2
  exit 16
}
printf 'Preaccepted Tuya dependency lock matched: %s\n' "$LOCK_SHA256"
unset ACCEPTED_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 || true

cat <<EOF

Tuya SDK dependencies are integrated locally, including the app-specific
ThingSmartCryption package and local-only app identity pod.

Resolved dependency provenance:
  Podfile.lock SHA-256: $LOCK_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

NEXT BUILD RULE:
  Open NembraCapture.xcworkspace, not NembraCapture.xcodeproj.
  Preserve this exact private-input fingerprint record with the field workspace.
  Do not run 'pod update', replace ThingSmartCryption, or regenerate the private
  identity before an accepted physical capture; any input change is a new
  reviewed field-build candidate and must earn a new exact-head acceptance.

This bootstrap still does NOT authorize the physical experiment. The exact app
must consume the private identity pod, authorize the user's own SDK session,
prove exact scooter membership, receive a genuine structured application
update, and survive the canonical authenticated 45-second gate before
stationary mapping can unlock.
EOF
