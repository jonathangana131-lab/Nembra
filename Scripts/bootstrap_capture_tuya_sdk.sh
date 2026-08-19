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

REVIEW_ONLY=0
FIELD_MODE=0
PROVENANCE_HELPER_SOURCE_B64=""
EXPECTED_FIELD_SOURCE_SHA=""
ACCEPTED_PRIVATE_INPUT_COMMITMENT=""
PRIVATE_REVIEW_AUTHORITY_PATH="CAPTURE_TUYA_PRIVATE_INPUT_REVIEW_COMMITMENT.txt"

if [[ "${1:-}" == "--resolve-lock-for-review" ]]; then
  REVIEW_ONLY=1
  shift
elif [[ "${1:-}" == "--field-repo-root" ]]; then
  FIELD_MODE=1
  [[ "$#" == "6" && "${3:-}" == "--field-source-sha" && "${5:-}" == "--field-provenance-helper-base64" ]] || {
    echo "ERROR: internal field bootstrap arguments are malformed." >&2
    exit 2
  }
  REPO_ROOT="${2:-}"
  EXPECTED_FIELD_SOURCE_SHA="${4:-}"
  PROVENANCE_HELPER_SOURCE_B64="${6:-}"
  shift 6
fi

if [[ "$FIELD_MODE" == "1" ]]; then
  [[ "$REPO_ROOT" == /* ]] || {
    echo "ERROR: internal field bootstrap root must be absolute." >&2
    exit 2
  }
  CANONICAL_REPO_ROOT="$(cd "$REPO_ROOT" 2>/dev/null && /bin/pwd -P)" || {
    echo "ERROR: internal field bootstrap root is unavailable." >&2
    exit 2
  }
  [[ "$CANONICAL_REPO_ROOT" == "$REPO_ROOT" ]] || {
    echo "ERROR: internal field bootstrap root must already be canonical." >&2
    exit 2
  }
  [[ "$EXPECTED_FIELD_SOURCE_SHA" =~ ^[0-9A-Fa-f]{40}$ ]] || {
    echo "ERROR: internal field bootstrap source SHA is malformed." >&2
    exit 2
  }
  EXPECTED_FIELD_SOURCE_SHA="$(printf '%s' "$EXPECTED_FIELD_SOURCE_SHA" | tr '[:upper:]' '[:lower:]')"
  CURRENT_FIELD_SOURCE_SHA="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null | tr '[:upper:]' '[:lower:]')" || {
    echo "ERROR: internal field bootstrap could not resolve checkout HEAD." >&2
    exit 2
  }
  [[ "$CURRENT_FIELD_SOURCE_SHA" == "$EXPECTED_FIELD_SOURCE_SHA" ]] || {
    echo "ERROR: checkout HEAD changed before the accepted bootstrap started." >&2
    exit 2
  }
  [[ -n "$PROVENANCE_HELPER_SOURCE_B64" ]] || {
    echo "ERROR: accepted provenance-helper execution bytes are unavailable." >&2
    exit 2
  }

  PROVENANCE_HELPER_PATH="Scripts/capture_tuya_private_input_provenance.py"
  PROVENANCE_HELPER_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$REPO_ROOT" rev-parse "$EXPECTED_FIELD_SOURCE_SHA:$PROVENANCE_HELPER_PATH" 2>/dev/null)" || {
    echo "ERROR: accepted provenance helper is missing from the exact Git tree." >&2
    exit 2
  }
  [[ "$PROVENANCE_HELPER_BLOB" =~ ^[0-9a-f]{40}$ ]] || {
    echo "ERROR: accepted provenance-helper Git identity is malformed." >&2
    exit 2
  }
  CAPTURED_PROVENANCE_BLOB="$(printf '%s' "$PROVENANCE_HELPER_SOURCE_B64" | /usr/bin/base64 -D | GIT_NO_REPLACE_OBJECTS=1 git -C "$REPO_ROOT" hash-object --stdin 2>/dev/null)" || {
    echo "ERROR: accepted provenance-helper execution bytes could not be authenticated." >&2
    exit 2
  }
  [[ "$CAPTURED_PROVENANCE_BLOB" == "$PROVENANCE_HELPER_BLOB" ]] || {
    echo "ERROR: provenance-helper execution bytes do not match the exact accepted Git object." >&2
    exit 2
  }

  PRIVATE_REVIEW_AUTHORITY_BLOB="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$REPO_ROOT" rev-parse "$EXPECTED_FIELD_SOURCE_SHA:$PRIVATE_REVIEW_AUTHORITY_PATH" 2>/dev/null)" || {
    echo "ERROR: exact accepted source does not contain a private-input review commitment. Physical field admission remains locked." >&2
    exit 2
  }
  [[ "$PRIVATE_REVIEW_AUTHORITY_BLOB" =~ ^[0-9a-f]{40}$ ]] || {
    echo "ERROR: accepted private-input review authority Git identity is malformed." >&2
    exit 2
  }
  ACCEPTED_PRIVATE_INPUT_COMMITMENT="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$REPO_ROOT" cat-file blob "$PRIVATE_REVIEW_AUTHORITY_BLOB" 2>/dev/null)" || {
    echo "ERROR: accepted private-input review commitment could not be read from the exact Git object." >&2
    exit 2
  }
  [[ "$ACCEPTED_PRIVATE_INPUT_COMMITMENT" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERROR: exact accepted source has no canonical 64-hex private-input review commitment. Run review mode, independently accept the opaque commitment, and record it in CAPTURE_TUYA_PRIVATE_INPUT_REVIEW_COMMITMENT.txt before any field build." >&2
    exit 2
  }

  unset CANONICAL_REPO_ROOT CURRENT_FIELD_SOURCE_SHA CAPTURED_PROVENANCE_BLOB PRIVATE_REVIEW_AUTHORITY_BLOB
  SCRIPT_DIR="$REPO_ROOT/Scripts"
  PROVENANCE_HELPER=""
else
  SCRIPT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && /bin/pwd -P)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && /bin/pwd -P)"
  PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"
fi

[[ "$#" == "0" ]] || {
  echo "ERROR: usage: Scripts/bootstrap_capture_tuya_sdk.sh [--resolve-lock-for-review]" >&2
  exit 2
}
[[ "$FIELD_MODE" == "0" || "$REVIEW_ONLY" == "0" ]] || {
  echo "ERROR: review mode and internal field mode cannot be combined." >&2
  exit 2
}

TUYA_PRIVATE_SDK="$REPO_ROOT/LocalSecrets/TuyaSDK"
TUYA_PRIVATE_IDENTITY="$REPO_ROOT/LocalSecrets/TuyaRuntime"
DEPENDENCY_PROVENANCE="$TUYA_PRIVATE_IDENTITY/ResolvedTuyaDependencyProvenance.txt"
PRIVATE_REVIEW_KEY="$TUYA_PRIVATE_IDENTITY/PrivateInputReviewKey.bin"

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
if [[ "$FIELD_MODE" == "0" ]]; then
  [[ -f "$PROVENANCE_HELPER" ]] || {
    echo "ERROR: private Tuya input provenance helper is missing from the accepted source." >&2
    exit 5
  }
fi

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

run_private_input_provenance() {
  local operation="$1"
  shift
  if [[ "$FIELD_MODE" == "1" ]]; then
    /usr/bin/python3 -I -B - "$PROVENANCE_HELPER_SOURCE_B64" "$operation" \
      --lockfile "$REPO_ROOT/Podfile.lock" \
      --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
      --security-build "$TUYA_PRIVATE_SDK/Build" \
      --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
      --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
      --record "$DEPENDENCY_PROVENANCE" \
      "$@" <<'PY'
import base64
import sys

source = base64.b64decode(sys.argv[1], validate=True)
sys.argv = ["<accepted-tuya-private-input-provenance>"] + sys.argv[2:]
namespace = {
    "__name__": "__main__",
    "__file__": "<accepted-tuya-private-input-provenance>",
}
exec(compile(source, namespace["__file__"], "exec", dont_inherit=True), namespace)
PY
  else
    /usr/bin/python3 -I "$PROVENANCE_HELPER" "$operation" \
      --lockfile "$REPO_ROOT/Podfile.lock" \
      --security-podspec "$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec" \
      --security-build "$TUYA_PRIVATE_SDK/Build" \
      --identity-podspec "$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec" \
      --identity-sources "$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig" \
      --record "$DEPENDENCY_PROVENANCE" \
      "$@"
  fi
}

if [[ "$REVIEW_ONLY" == "1" ]]; then
  printf '%s\n' 'Resolving a candidate official Tuya SDK graph for review…'
  pod install --repo-update
else
  [[ -f Podfile.lock && ! -L Podfile.lock ]] || {
    echo "ERROR: accepted-lock mode requires an existing regular non-symlink Podfile.lock. Run --resolve-lock-for-review separately first." >&2
    exit 8
  }
  [[ -f "$DEPENDENCY_PROVENANCE" && ! -L "$DEPENDENCY_PROVENANCE" ]] || {
    echo "ERROR: accepted-lock mode requires the pre-existing reviewed private-input provenance record. Field mode will not create or replace this witness." >&2
    exit 8
  }
  [[ -f "$PRIVATE_REVIEW_KEY" && ! -L "$PRIVATE_REVIEW_KEY" ]] || {
    echo "ERROR: accepted-lock mode requires the private review key created by the separate review phase. Field mode will not create or replace it." >&2
    exit 8
  }
  [[ "$(stat -f '%Lp' "$DEPENDENCY_PROVENANCE" 2>/dev/null || true)" == "600" ]] || {
    echo "ERROR: pre-existing private Tuya dependency provenance record is not mode 0600." >&2
    exit 8
  }
  [[ "$(stat -f '%Lp' "$PRIVATE_REVIEW_KEY" 2>/dev/null || true)" == "600" ]] || {
    echo "ERROR: private Tuya review key is not mode 0600." >&2
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

  if ! run_private_input_provenance verify-review \
      --review-key "$PRIVATE_REVIEW_KEY" \
      --accepted-commitment "$ACCEPTED_PRIVATE_INPUT_COMMITMENT"; then
    echo "ERROR: current private Tuya build inputs do not match the externally accepted review commitment. No dependency command was run." >&2
    exit 11
  fi

  printf '%s\n' 'Installing only the preauthenticated official Tuya SDK graph…'
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

REVIEW_COMMITMENT=""
if [[ "$REVIEW_ONLY" == "1" ]]; then
  if ! REVIEW_COMMITMENT="$(run_private_input_provenance review --review-key "$PRIVATE_REVIEW_KEY")"; then
    echo "ERROR: exact private Tuya build-input review commitment could not be created." >&2
    exit 11
  fi
  [[ "$REVIEW_COMMITMENT" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERROR: private Tuya review produced a malformed opaque commitment." >&2
    exit 11
  }
else
  if ! run_private_input_provenance verify-review \
      --review-key "$PRIVATE_REVIEW_KEY" \
      --accepted-commitment "$ACCEPTED_PRIVATE_INPUT_COMMITMENT"; then
    echo "ERROR: private Tuya build inputs changed across dependency installation or no longer match the accepted review commitment." >&2
    exit 11
  fi
fi

LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
[[ "$LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: could not compute the Podfile.lock SHA-256 fingerprint." >&2
  exit 12
}
[[ -f "$DEPENDENCY_PROVENANCE" ]] || {
  echo "ERROR: private Tuya dependency provenance record is unavailable." >&2
  exit 12
}
[[ "$(stat -f '%Lp' "$DEPENDENCY_PROVENANCE" 2>/dev/null || true)" == "600" ]] || {
  echo "ERROR: private Tuya dependency provenance record is not mode 0600." >&2
  exit 13
}
[[ -f "$PRIVATE_REVIEW_KEY" && "$(stat -f '%Lp' "$PRIVATE_REVIEW_KEY" 2>/dev/null || true)" == "600" ]] || {
  echo "ERROR: private Tuya review key is unavailable or not mode 0600." >&2
  exit 13
}

if [[ "$REVIEW_ONLY" == "1" ]]; then
  cat <<EOF

REVIEW CANDIDATE ONLY — NO BUILD, INSTALL, BLUETOOTH, OR PHYSICAL AUTHORITY
  Podfile.lock SHA-256: $LOCK_SHA256
  Opaque private-input review commitment: $REVIEW_COMMITMENT
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE
  Local private review key: $PRIVATE_REVIEW_KEY

The review key and fingerprint record stay private. The 64-hex commitment is safe
to carry into the public acceptance plane because it is HMAC-bound to a random
local key rather than being a direct credential-derived hash.

After reviewing this candidate, record the exact opaque commitment in:
  $PRIVATE_REVIEW_AUTHORITY_PATH
on a new source commit. Field mode reads that value from the exact accepted Git
object, not from the mutable checkout pathname or a caller-supplied field value.
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
unset PROVENANCE_HELPER_SOURCE_B64 EXPECTED_FIELD_SOURCE_SHA PROVENANCE_HELPER_BLOB || true

printf 'Preaccepted Tuya dependency lock matched: %s\n' "$LOCK_SHA256"
printf 'Exact-source private-input review commitment matched: %s\n' "$ACCEPTED_PRIVATE_INPUT_COMMITMENT"
printf '%s\n' 'Private Tuya inputs matched the externally accepted review generation. Use NembraCapture.xcworkspace for the field build.'
