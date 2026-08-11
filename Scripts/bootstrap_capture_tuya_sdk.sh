#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TUYA_PRIVATE_SDK="$REPO_ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$REPO_ROOT/LocalSecrets/TuyaRuntime"
DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
PRIVATE_REVIEW_KEY="$TUYA_PRIVATE_IDENTITY/PrivateReviewCommitment.key"
PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"
PRIVATE_REVIEW_HELPER="$SCRIPT_DIR/capture_private_review_commitment.py"
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
  : "${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 to the preaccepted 64-hex Podfile.lock SHA-256 before field bootstrap.}"
  : "${NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 to the preaccepted 64-hex generated CocoaPods build-subject SHA-256 before field bootstrap.}"
  : "${NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 to the preaccepted 64-hex opaque private review commitment before field bootstrap.}"
  : "${NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256 to the preaccepted 64-hex private-review verifier source SHA-256 before field bootstrap.}"
  [[ "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  [[ "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  [[ "$NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  [[ "$NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
  ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" | tr '[:upper:]' '[:lower:]')"
  ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256" | tr '[:upper:]' '[:lower:]')"
  ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 \
    NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 \
    NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 \
    NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
  ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256=""
  ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256=""
  ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256=""
fi

[[ -x /usr/bin/python3 ]] || {
  echo "ERROR: System Python 3 is required for Capture field provenance." >&2
  exit 3
}

for required_source in "$PROVENANCE_HELPER" "$PRIVATE_REVIEW_HELPER" "$GENERATED_BUILD_SUBJECT_HELPER"; do
  [[ -f "$required_source" ]] || {
    echo "ERROR: required accepted Capture authority helper is missing: $required_source" >&2
    exit 6
  }
done
unset required_source


run_accepted_private_review_helper() {
  local expected_sha256="$1"
  shift
  /usr/bin/python3 -I - "$PRIVATE_REVIEW_HELPER" "$expected_sha256" "$@" <<'PY'
import hashlib
import hmac
import os
import stat
import sys

path = sys.argv[1]
expected = sys.argv[2].lower()
helper_argv = sys.argv[3:]
if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
    print("ERROR: accepted private-review verifier source digest is malformed", file=sys.stderr)
    raise SystemExit(72)
flags = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
try:
    descriptor = os.open(path, flags)
except OSError as error:
    print(f"ERROR: accepted private-review verifier source could not be opened: {error}", file=sys.stderr)
    raise SystemExit(73)
try:
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size <= 0 or before.st_size > 262144:
        print("ERROR: private-review verifier source is not one bounded regular single-link file", file=sys.stderr)
        raise SystemExit(74)
    chunks = []
    remaining = before.st_size
    while remaining:
        chunk = os.read(descriptor, min(65536, remaining))
        if not chunk:
            print("ERROR: private-review verifier source changed during descriptor read", file=sys.stderr)
            raise SystemExit(75)
        chunks.append(chunk)
        remaining -= len(chunk)
    source = b"".join(chunks)
    after = os.fstat(descriptor)
    before_identity = (before.st_dev, before.st_ino, before.st_mode, before.st_size, before.st_mtime_ns, before.st_ctime_ns, before.st_nlink)
    after_identity = (after.st_dev, after.st_ino, after.st_mode, after.st_size, after.st_mtime_ns, after.st_ctime_ns, after.st_nlink)
    if before_identity != after_identity:
        print("ERROR: private-review verifier source changed during descriptor custody", file=sys.stderr)
        raise SystemExit(76)
finally:
    os.close(descriptor)
actual = hashlib.sha256(source).hexdigest()
if not hmac.compare_digest(actual, expected):
    print("ERROR: private-review verifier source does not match the externally reviewed digest", file=sys.stderr)
    raise SystemExit(77)
namespace = {"__name__": "__main__", "__file__": "<accepted-private-review-verifier>"}
sys.argv = [path, *helper_argv]
exec(compile(source, "<accepted-private-review-verifier>", "exec"), namespace)
PY
}

[[ -f Podfile ]] || { echo "ERROR: Podfile is missing at $REPO_ROOT/Podfile" >&2; exit 4; }
[[ -d NembraCapture.xcodeproj ]] || { echo "ERROR: NembraCapture.xcodeproj is missing." >&2; exit 5; }

if [[ ! -f "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" || ! -d "$TUYA_PRIVATE_SDK/Build" ]]; then
  cat >&2 <<EOF
ERROR: Tuya's app-specific iOS security SDK is not provisioned.
Expected private files beneath ignored LocalSecrets/TuyaSDK:
  ThingSmartCryption.podspec
  Build/
EOF
  exit 7
fi

if [[ ! -f "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" ||
      ! -d "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" ||
      ! -f "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift" ]]; then
  cat >&2 <<EOF
ERROR: Tuya's private app identity is not provisioned for the field workspace.
Run Scripts/provision_capture_tuya_identity.sh. Private credentials must remain
beneath ignored LocalSecrets and must never be passed through build arguments.
EOF
  exit 8
fi

if [[ "$REVIEW_ONLY" == "1" ]]; then
  command -v pod >/dev/null 2>&1 || {
    echo "ERROR: CocoaPods is required only to create a review-only candidate." >&2
    exit 2
  }
  printf 'Resolving one review-only Tuya/CocoaPods candidate for Nembra Capture...\n'
  pod install --repo-update
else
  printf 'Verifying the already-reviewed Tuya/CocoaPods/private field subject...\n'
fi

[[ -d NembraCapture.xcworkspace ]] || {
  echo "ERROR: NembraCapture.xcworkspace is unavailable. Create/review a candidate first with --resolve-lock-for-review; normal field bootstrap never regenerates it." >&2
  exit 9
}
[[ -d Pods ]] || {
  echo "ERROR: Pods/ is unavailable. Create/review a candidate first with --resolve-lock-for-review; normal field bootstrap never regenerates it." >&2
  exit 9
}
[[ -f Podfile.lock ]] || {
  echo "ERROR: Podfile.lock is unavailable. Create/review a candidate first with --resolve-lock-for-review; normal field bootstrap never regenerates it." >&2
  exit 10
}

LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[[ "$LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: could not compute the Podfile.lock SHA-256 provenance fingerprint." >&2
  exit 13
}

if [[ "$REVIEW_ONLY" == "0" ]]; then
  [[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
    echo "ERROR: existing Podfile.lock does not match the preaccepted dependency-lock SHA-256. Normal field bootstrap will not run CocoaPods or mutate the candidate." >&2
    exit 16
  }
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
    --record "$DEPENDENCY_PROVENANCE" >/dev/null || {
      echo "ERROR: exact private Tuya build-input provenance could not be snapshotted for review." >&2
      exit 12
    }

  PRIVATE_REVIEW_COMMITMENT_SHA256="$(/usr/bin/python3 -I "$PRIVATE_REVIEW_HELPER" create \
    --witness "$DEPENDENCY_PROVENANCE" \
    --key "$PRIVATE_REVIEW_KEY")" || {
      echo "ERROR: opaque private-input review commitment could not be created." >&2
      exit 18
    }
  PRIVATE_REVIEW_HELPER_SHA256="$(shasum -a 256 "$PRIVATE_REVIEW_HELPER" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
else
  run_accepted_private_review_helper "$ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256" verify \
    --witness "$DEPENDENCY_PROVENANCE" \
    --key "$PRIVATE_REVIEW_KEY" \
    --expected "$ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256" >/dev/null || {
      echo "ERROR: local private-input witness/key do not match the externally accepted private review commitment, or verifier source does not match the externally accepted private review authority." >&2
      exit 18
    }
  PRIVATE_REVIEW_HELPER_SHA256="$ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256"

  /usr/bin/python3 -I "$PROVENANCE_HELPER" verify \
    --lockfile "$REPO_ROOT/Podfile.lock" \
    --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
    --security-build "$TUYA_PRIVATE_SDK/Build" \
    --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
    --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
    --record "$DEPENDENCY_PROVENANCE" >/dev/null || {
      echo "ERROR: current private Tuya build inputs do not match the externally committed review witness." >&2
      exit 12
    }

  PRIVATE_REVIEW_COMMITMENT_SHA256="$ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256"
fi

[[ "$PRIVATE_REVIEW_COMMITMENT_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: private review commitment helper did not return one lowercase SHA-256 tag." >&2
  exit 18
}
[[ -f "$DEPENDENCY_PROVENANCE" && -f "$PRIVATE_REVIEW_KEY" ]] || {
  echo "ERROR: private review witness/key are unavailable." >&2
  exit 14
}
[[ "$(stat -f '%Lp' "$DEPENDENCY_PROVENANCE" 2>/dev/null || true)" == "600" ]] || {
  echo "ERROR: private Tuya dependency provenance record is not mode 0600." >&2
  exit 15
}
[[ "$(stat -f '%Lp' "$PRIVATE_REVIEW_KEY" 2>/dev/null || true)" == "600" ]] || {
  echo "ERROR: private review commitment key is not mode 0600." >&2
  exit 15
}

GENERATED_BUILD_SUBJECT_SHA256="$(/usr/bin/python3 -I "$GENERATED_BUILD_SUBJECT_HELPER" \
  --lockfile "$REPO_ROOT/Podfile.lock" \
  --pods "$REPO_ROOT/Pods" \
  --workspace "$REPO_ROOT/NembraCapture.xcworkspace")" || {
    echo "ERROR: exact generated CocoaPods build subject could not be fingerprinted." >&2
    exit 13
  }
[[ "$GENERATED_BUILD_SUBJECT_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: generated CocoaPods build-subject helper did not return one lowercase SHA-256." >&2
  exit 13
}

if [[ "$REVIEW_ONLY" == "1" ]]; then
  cat <<EOF

DEPENDENCY LOCK CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY
  Generated CocoaPods build subject and opaque private-input commitment are additionally part of this review candidate.
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build subject SHA-256: $GENERATED_BUILD_SUBJECT_SHA256
  Private review commitment SHA-256: $PRIVATE_REVIEW_COMMITMENT_SHA256
  Private review verifier source SHA-256: $PRIVATE_REVIEW_HELPER_SHA256
  Local private-input fingerprint record (review witness): $DEPENDENCY_PROVENANCE
  Local private commitment key: retained privately; never publish or export

Review and bind all FOUR public authority values to the exact accepted Capture
source through Final GO. Keep the witness/key/generated workspace unchanged.
Normal field bootstrap requires those accepted values, never reruns CocoaPods,
never rewrites the witness/key, and verifies private bytes against the committed
witness before any build. The HMAC key and raw private fingerprints/credentials
must never enter GitHub review, argv, exported artifacts, or public provenance.
This review-only mode never invokes xcodebuild, installs Nembra, scans Bluetooth,
or authorizes a physical attempt.
EOF
  exit 0
fi

[[ "$GENERATED_BUILD_SUBJECT_SHA256" == "$ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256" ]] || {
  echo "ERROR: existing CocoaPods generated build inputs do not match the preaccepted generated-build subject SHA-256. Normal field bootstrap will not regenerate them." >&2
  exit 17
}
printf 'Preaccepted Tuya dependency lock matched: %s\n' "$LOCK_SHA256"
printf 'Preaccepted CocoaPods generated build subject matched: %s\n' "$GENERATED_BUILD_SUBJECT_SHA256"
printf 'Externally accepted opaque private review commitment matched: %s\n' "$PRIVATE_REVIEW_COMMITMENT_SHA256"
printf 'Externally accepted private review verifier source matched: %s\n' "$PRIVATE_REVIEW_HELPER_SHA256"
unset ACCEPTED_LOCK_SHA256 ACCEPTED_GENERATED_BUILD_SUBJECT_SHA256 ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256 \
  NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 \
  NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 \
  NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_COMMITMENT_SHA256 \
  NEMBRA_CAPTURE_ACCEPTED_PRIVATE_REVIEW_HELPER_SHA256 || true

cat <<EOF

The exact pre-reviewed dependency/generated/private field subject is present.
Normal field bootstrap did not run CocoaPods, replace the private witness/key,
or expose private credentials/fingerprints.

Verified public authority:
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build subject SHA-256: $GENERATED_BUILD_SUBJECT_SHA256
  Opaque private review commitment SHA-256: $PRIVATE_REVIEW_COMMITMENT_SHA256
  Private review verifier source SHA-256: $PRIVATE_REVIEW_HELPER_SHA256

NEXT BUILD RULE:
  Open NembraCapture.xcworkspace, not NembraCapture.xcodeproj.
  Preserve the private witness/key and generated workspace exactly.
  Any dependency/generated/private/key/witness change requires a new explicit
  review-only candidate and new Final-GO owner authority.

This bootstrap still does NOT authorize the physical experiment. The exact app
must consume the private identity pod, authorize the user's own SDK session,
prove exact scooter membership, receive genuine structured application evidence,
and survive the canonical authenticated 45-second stationary gate.
EOF