#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TUYA_PRIVATE_SDK="$REPO_ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$REPO_ROOT/LocalSecrets/TuyaRuntime"
DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"
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
  : "${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 to the independently accepted 64-hex Podfile.lock SHA-256. Use --resolve-lock-for-review only to create a non-authoritative candidate.}"
  : "${NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256 to the independently accepted 64-hex canonical private-input provenance-record SHA-256. Use --resolve-lock-for-review only to create a non-authoritative candidate.}"
  [[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  [[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
  ACCEPTED_PROVENANCE_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
  ACCEPTED_PROVENANCE_SHA256=""
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

provenance_verify() {
  /usr/bin/python3 -I "$PROVENANCE_HELPER" verify \
    --lockfile "$REPO_ROOT/Podfile.lock" \
    --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
    --security-build "$TUYA_PRIVATE_SDK/Build" \
    --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
    --record "$DEPENDENCY_PROVENANCE"
}

fingerprint_lock() {
  shasum -a 256 "$REPO_ROOT/Podfile.lock" | awk '{print $1}' | tr '[:upper:]' '[:lower:]'
}

fingerprint_provenance() {
  shasum -a 256 "$DEPENDENCY_PROVENANCE" | awk '{print $1}' | tr '[:upper:]' '[:lower:]'
}

require_provenance_mode() {
  [[ "$(stat -f '%Lp' "$DEPENDENCY_PROVENANCE" 2>/dev/null || true)" == "600" ]] || {
    echo "ERROR: private Tuya dependency provenance record is not mode 0600." >&2
    exit 15
  }
}

if [[ "$REVIEW_ONLY" == "0" ]]; then
  [[ -f "$REPO_ROOT/Podfile.lock" ]] || {
    echo "ERROR: normal field bootstrap requires the exact pre-reviewed Podfile.lock. Run --resolve-lock-for-review first; do not resolve a new lock inside an authoritative field attempt." >&2
    exit 10
  }
  [[ -f "$DEPENDENCY_PROVENANCE" ]] || {
    echo "ERROR: normal field bootstrap requires the pre-reviewed private-input provenance record. Run --resolve-lock-for-review first; normal mode will never create or refresh this authority subject." >&2
    exit 14
  }
  require_provenance_mode

  PRE_LOCK_SHA256="$(fingerprint_lock)"
  PRE_PROVENANCE_SHA256="$(fingerprint_provenance)"
  [[ "$PRE_LOCK_SHA256" =~ ^[0-9a-f]{64}$ && "$PRE_PROVENANCE_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERROR: could not compute pre-bootstrap Tuya dependency/provenance fingerprints." >&2
    exit 13
  }
  [[ "$PRE_LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
    echo "ERROR: pre-bootstrap Podfile.lock does not match the independently accepted dependency-lock SHA-256. Stop before CocoaPods/xcodebuild." >&2
    exit 16
  }
  [[ "$PRE_PROVENANCE_SHA256" == "$ACCEPTED_PROVENANCE_SHA256" ]] || {
    echo "ERROR: pre-bootstrap private-input provenance record does not match the independently accepted SHA-256. Normal mode may not refresh or rebind it." >&2
    exit 17
  }
  provenance_verify || {
    echo "ERROR: live private Tuya inputs do not match the independently accepted pre-bootstrap provenance record. Stop before CocoaPods/xcodebuild." >&2
    exit 18
  }
  printf 'Preaccepted Tuya dependency lock and private-input provenance matched before CocoaPods.\n'
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

if [[ "$REVIEW_ONLY" == "1" ]]; then
  # REVIEW MODE ONLY: create a candidate record. This record is not field-build
  # authority until its digest is independently accepted by the Final-GO control
  # plane. Normal mode above never executes `snapshot` and cannot self-refresh it.
  if ! /usr/bin/python3 -I "$PROVENANCE_HELPER" snapshot \
    --lockfile "$REPO_ROOT/Podfile.lock" \
    --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
    --security-build "$TUYA_PRIVATE_SDK/Build" \
    --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
    --record "$DEPENDENCY_PROVENANCE"
  then
    echo "ERROR: exact private Tuya build-input provenance candidate could not be snapshotted." >&2
    exit 12
  fi
  chmod 600 "$DEPENDENCY_PROVENANCE"
  require_provenance_mode
  provenance_verify || {
    echo "ERROR: newly generated review-only private-input provenance candidate failed self-verification." >&2
    exit 18
  }

  LOCK_SHA256="$(fingerprint_lock)"
  PROVENANCE_SHA256="$(fingerprint_provenance)"
  [[ "$LOCK_SHA256" =~ ^[0-9a-f]{64}$ && "$PROVENANCE_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERROR: could not compute review-only Tuya dependency/provenance fingerprints." >&2
    exit 13
  }
  cat <<EOF

DEPENDENCY + PRIVATE-INPUT CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY
  Podfile.lock SHA-256: $LOCK_SHA256
  Canonical private-input provenance SHA-256: $PROVENANCE_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

Review and bind BOTH exact digests to the exact accepted Capture source through
the current Final-GO control plane before any field build/install. Then rerun the
normal bootstrap/installer with NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 and
NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256. Review-only mode never invokes
xcodebuild, installs Nembra, scans Bluetooth, or authorizes a physical attempt.
EOF
  exit 0
fi

LOCK_SHA256="$(fingerprint_lock)"
PROVENANCE_SHA256="$(fingerprint_provenance)"
[[ "$LOCK_SHA256" =~ ^[0-9a-f]{64}$ && "$PROVENANCE_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: could not compute post-bootstrap Tuya dependency/provenance fingerprints." >&2
  exit 13
}
[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
  echo "ERROR: CocoaPods changed Podfile.lock away from the independently accepted dependency-lock SHA-256. Stop before xcodebuild/install." >&2
  exit 16
}
[[ "$PROVENANCE_SHA256" == "$ACCEPTED_PROVENANCE_SHA256" ]] || {
  echo "ERROR: private-input provenance record changed away from the independently accepted SHA-256 during bootstrap. Normal mode may not refresh or rebind it." >&2
  exit 17
}
require_provenance_mode
provenance_verify || {
  echo "ERROR: live private Tuya inputs no longer match the independently accepted provenance after CocoaPods. Stop before xcodebuild/install." >&2
  exit 18
}
printf 'Preaccepted Tuya dependency lock matched after CocoaPods: %s\n' "$LOCK_SHA256"
printf 'Preaccepted private-input provenance matched after CocoaPods: %s\n' "$PROVENANCE_SHA256"
unset ACCEPTED_LOCK_SHA256 ACCEPTED_PROVENANCE_SHA256 PRE_LOCK_SHA256 PRE_PROVENANCE_SHA256 || true

cat <<EOF

Tuya SDK dependencies are integrated locally, including the app-specific
ThingSmartCryption package and local-only app identity pod.

Accepted dependency provenance:
  Podfile.lock SHA-256: $LOCK_SHA256
  Canonical private-input provenance SHA-256: $PROVENANCE_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

NEXT BUILD RULE:
  Open NembraCapture.xcworkspace, not NembraCapture.xcodeproj.
  Preserve this exact preaccepted private-input fingerprint record with the field workspace.
  Do not run 'pod update', replace ThingSmartCryption, regenerate the private identity,
  or run review-mode snapshot inside an accepted attempt. Any input change is a new
  reviewed field-build candidate and must earn new independent digest acceptance.

This bootstrap still does NOT authorize the physical experiment. The exact app
must consume the private identity pod, authorize the user's own SDK session,
prove exact scooter membership, receive a genuine structured application
update, and survive the canonical authenticated 45-second gate before
stationary mapping can unlock.
EOF
