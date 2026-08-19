#!/bin/bash -p
set -euo pipefail

if [[ $- != *p* ]]; then
  builtin printf '%s\n' 'ERROR: execute Scripts/bootstrap_capture_tuya_sdk.sh directly so imported Bash startup state stays disabled.' >&2
  exit 2
fi

set +x
PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset BASH_ENV ENV CDPATH GLOBIGNORE || true

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && /bin/pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && /bin/pwd -P)"
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
  exit 2
}

cd "$REPO_ROOT"
umask 077

if [[ "$REVIEW_ONLY" == "0" ]]; then
  : "${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 to the reviewed 64-hex Podfile.lock SHA-256. Use --resolve-lock-for-review first when no digest has been accepted.}"
  [[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 must be exactly 64 hex characters." >&2
    exit 3
  }
  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
fi

command -v pod >/dev/null 2>&1 || {
  echo "ERROR: CocoaPods is required to integrate Tuya's official SmartLife SDK." >&2
  exit 4
}
[[ -x /usr/bin/python3 ]] || {
  echo "ERROR: System Python 3 is required for private Tuya input provenance." >&2
  exit 4
}
[[ -f Podfile && -d NembraCapture.xcodeproj ]] || {
  echo "ERROR: run this from an accepted Nembra checkout containing Podfile and NembraCapture.xcodeproj." >&2
  exit 5
}
[[ -f "$PROVENANCE_HELPER" ]] || {
  echo "ERROR: private Tuya input provenance helper is missing from the accepted source." >&2
  exit 5
}

if [[ ! -f "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" || ! -d "$TUYA_PRIVATE_SDK/Build" ]]; then
  cat >&2 <<EOF
ERROR: Tuya's app-specific iOS security SDK is not provisioned.

Download the SmartLife iOS security package for the exact Capture bundle ID,
then place ThingSmartCryption.podspec and its Build directory beneath:
  $TUYA_PRIVATE_SDK

LocalSecrets is ignored. Never commit or upload this SDK or any Tuya secret.
EOF
  exit 6
fi

if [[ ! -f "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" ||
      ! -f "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift" ]]; then
  cat >&2 <<'EOF'
ERROR: the local-only Tuya app identity is not provisioned.
Run Scripts/provision_capture_tuya_identity.sh, entering AppKey/AppSecret only at
its hidden terminal prompts. Do not pass either value as an argument or env var.
EOF
  exit 7
fi

if [[ "$REVIEW_ONLY" == "1" ]]; then
  printf '%s\n' 'Resolving a candidate official Tuya SDK graph for review…'
  # This is the only mode allowed to refresh public spec metadata or create a
  # new lock. Its output is non-authorizing until the operator reviews and
  # separately accepts the exact resulting Podfile.lock digest.
  pod install --repo-update
else
  [[ -f Podfile.lock && ! -L Podfile.lock ]] || {
    echo "ERROR: accepted-lock mode requires an existing regular non-symlink Podfile.lock. Run --resolve-lock-for-review separately first." >&2
    exit 8
  }
  PREINSTALL_LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
  [[ "$PREINSTALL_LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERROR: could not pre-authenticate the existing Podfile.lock." >&2
    exit 8
  }
  [[ "$PREINSTALL_LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
    echo "ERROR: existing Podfile.lock does not match the preaccepted dependency-lock SHA-256. No dependency command was run." >&2
    exit 8
  }

  printf '%s\n' 'Installing only the preauthenticated official Tuya SDK graph…'
  # Accepted mode is deployment-only: do not refresh specs, update the repo,
  # or permit CocoaPods to rewrite the reviewed lock.
  pod install --deployment --no-repo-update
fi

[[ -d NembraCapture.xcworkspace ]] || {
  echo "ERROR: CocoaPods did not create NembraCapture.xcworkspace." >&2
  exit 8
}
if [[ ! -f Podfile.lock ]]; then
  echo "ERROR: CocoaPods did not create Podfile.lock; exact dependency provenance is unavailable." >&2
  exit 9
fi

for expected in \
  "  - ThingSmartHomeKit (7.8.0)" \
  "  - ThingSmartBusinessExtensionKit (7.8.0)"
do
  /usr/bin/grep -Fq -- "$expected" Podfile.lock || {
    echo "ERROR: resolved Tuya SDK does not contain exact reviewed dependency: $expected" >&2
    exit 10
  }
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
  exit 11
fi

LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[[ "$LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: could not compute the Podfile.lock SHA-256 fingerprint." >&2
  exit 12
}
[[ -f "$DEPENDENCY_PROVENANCE" ]] || {
  echo "ERROR: private Tuya dependency provenance record was not created." >&2
  exit 12
}
[[ "$(stat -f '%Lp' "$DEPENDENCY_PROVENANCE" 2>/dev/null || true)" == "600" ]] || {
  echo "ERROR: private Tuya dependency provenance record is not mode 0600." >&2
  exit 13
}

if [[ "$REVIEW_ONLY" == "1" ]]; then
  cat <<EOF

LOCK CANDIDATE ONLY — NO BUILD, INSTALL, BLUETOOTH, OR PHYSICAL AUTHORITY
  Podfile.lock SHA-256: $LOCK_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

Review the lock, then rerun the field installer with this exact digest in
NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256. The installer rechecks the ignored
inputs immediately before and after xcodebuild.
EOF
  exit 0
fi

[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
  echo "ERROR: Podfile.lock changed after deployment-only install and no longer matches the preaccepted dependency-lock SHA-256. Stop before xcodebuild/install." >&2
  exit 14
}
[[ "$PREINSTALL_LOCK_SHA256" == "$LOCK_SHA256" ]] || {
  echo "ERROR: deployment-only install mutated the preauthenticated Podfile.lock. Stop before xcodebuild/install." >&2
  exit 14
}
unset ACCEPTED_LOCK_SHA256 PREINSTALL_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 || true

printf 'Preaccepted Tuya dependency lock matched: %s\n' "$LOCK_SHA256"
printf '%s\n' 'Private Tuya inputs were snapshotted. Use NembraCapture.xcworkspace for the field build.'
