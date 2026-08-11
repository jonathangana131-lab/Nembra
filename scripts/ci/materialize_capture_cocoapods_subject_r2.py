#!/usr/bin/env python3
from pathlib import Path

path = Path("Scripts/bootstrap_capture_tuya_sdk.sh")
source = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one bootstrap marker, found {count}: {old[:120]!r}")
    source = source.replace(old, new, 1)


replace_once(
    'PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"\nREVIEW_ONLY=0',
    'PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"\n'
    'COCOAPODS_BUILD_SUBJECT_HELPER="$SCRIPT_DIR/capture_cocoapods_build_subject.py"\n'
    'REVIEW_ONLY=0',
)

replace_once(
    '''  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 || true
  ACCEPTED_LOCK_SHA256=""''',
    '''  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
  : "${NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 to the preaccepted 64-hex generated CocoaPods build-subject SHA-256 before field bootstrap.}"
  [[ "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
  ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256=""''',
)

replace_once(
    '''if [[ ! -f "$PROVENANCE_HELPER" ]]; then
  echo "ERROR: private Tuya input provenance helper is missing from the accepted source." >&2
  exit 6
fi''',
    '''if [[ ! -f "$PROVENANCE_HELPER" ]]; then
  echo "ERROR: private Tuya input provenance helper is missing from the accepted source." >&2
  exit 6
fi

if [[ ! -f "$COCOAPODS_BUILD_SUBJECT_HELPER" ]]; then
  echo "ERROR: CocoaPods generated-build subject helper is missing from the accepted source." >&2
  exit 6
fi''',
)

marker = "printf 'Resolving the official Tuya SmartLife iOS SDK and private field identity for Nembra Capture...\\n'"
precheck = '''if [[ "$REVIEW_ONLY" == "0" ]]; then
  [[ -f Podfile.lock ]] || {
    echo "ERROR: normal field bootstrap requires the reviewed Podfile.lock to already exist before CocoaPods starts. Run --resolve-lock-for-review first, review that exact lock, then retry from the unchanged workspace." >&2
    exit 16
  }
  PRE_COCOAPODS_LOCK_SHA256="$(shasum -a 256 Podfile.lock | awk '{print $1}' | tr '[:upper:]' '[:lower:]')"
  [[ "$PRE_COCOAPODS_LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERROR: could not compute the pre-CocoaPods Podfile.lock SHA-256." >&2
    exit 16
  }
  [[ "$PRE_COCOAPODS_LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
    echo "ERROR: on-disk Podfile.lock does not match the preaccepted dependency lock before CocoaPods. Refusing to run the generator." >&2
    exit 16
  }
  printf 'Preaccepted Tuya dependency lock matched before CocoaPods: %s\\n' "$PRE_COCOAPODS_LOCK_SHA256"
fi

'''
replace_once(marker, precheck + marker)

mode_guard = '''[[ "$(stat -f '%Lp' "$DEPENDENCY_PROVENANCE" 2>/dev/null || true)" == "600" ]] || {
  echo "ERROR: private Tuya dependency provenance record is not mode 0600." >&2
  exit 15
}'''
subject_block = mode_guard + '''

if ! COCOAPODS_BUILD_SUBJECT_SHA256="$(/usr/bin/python3 -I "$COCOAPODS_BUILD_SUBJECT_HELPER" \\
  --lockfile "$REPO_ROOT/Podfile.lock" \\
  --pods "$REPO_ROOT/Pods" \\
  --workspace "$REPO_ROOT/NembraCapture.xcworkspace")"
then
  echo "ERROR: exact generated CocoaPods build subject could not be fingerprinted." >&2
  exit 17
fi
[[ "$COCOAPODS_BUILD_SUBJECT_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: generated CocoaPods build-subject fingerprint is malformed." >&2
  exit 17
}'''
replace_once(mode_guard, subject_block)

old_review = '''if [[ "$REVIEW_ONLY" == "1" ]]; then
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
fi'''
new_review = '''if [[ "$REVIEW_ONLY" == "1" ]]; then
  cat <<EOF

DEPENDENCY BUILD SUBJECT CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build subject SHA-256: $COCOAPODS_BUILD_SUBJECT_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

Review and bind both this exact dependency-lock digest and generated CocoaPods
build-subject digest to the exact accepted Capture source before any field build/install.
Then rerun normal bootstrap with both reviewed values supplied as
NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 and
NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256. This review-only mode never
invokes xcodebuild, installs Nembra, scans Bluetooth, or authorizes a physical attempt.
EOF
  exit 0
fi'''
replace_once(old_review, new_review)

old_accept = '''[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
  echo "ERROR: resolved Podfile.lock does not match the preaccepted dependency-lock SHA-256. Stop before xcodebuild/install and review the new dependency subject." >&2
  exit 16
}
printf 'Preaccepted Tuya dependency lock matched: %s\\n' "$LOCK_SHA256"
unset ACCEPTED_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 || true'''
new_accept = '''[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
  echo "ERROR: resolved Podfile.lock does not match the preaccepted dependency-lock SHA-256. Stop before xcodebuild/install and review the new dependency subject." >&2
  exit 16
}
[[ "$COCOAPODS_BUILD_SUBJECT_SHA256" == "$ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" ]] || {
  echo "ERROR: generated CocoaPods build subject does not match the preaccepted build-subject SHA-256. Stop before xcodebuild/install and review the new generated build subject." >&2
  exit 18
}
printf 'Preaccepted Tuya dependency lock matched: %s\\n' "$LOCK_SHA256"
printf 'Preaccepted generated CocoaPods build subject matched: %s\\n' "$COCOAPODS_BUILD_SUBJECT_SHA256"
unset ACCEPTED_LOCK_SHA256 ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256 || true'''
replace_once(old_accept, new_accept)

old_final = '''Resolved dependency provenance:
  Podfile.lock SHA-256: $LOCK_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE'''
new_final = '''Resolved dependency provenance:
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build subject SHA-256: $COCOAPODS_BUILD_SUBJECT_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE'''
replace_once(old_final, new_final)

path.write_text(source, encoding="utf-8")
