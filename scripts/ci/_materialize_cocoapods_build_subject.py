#!/usr/bin/env python3
from pathlib import Path

bootstrap_path = Path("Scripts/bootstrap_capture_tuya_sdk.sh")
bootstrap = bootstrap_path.read_text()
if "NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256" not in bootstrap:
    replacements = []
    replacements.append((
        'PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"\nREVIEW_ONLY=0\n',
        'PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"\nBUILD_SUBJECT_HELPER="$SCRIPT_DIR/capture_cocoapods_build_subject.py"\nREVIEW_ONLY=0\n',
    ))
    replacements.append((
'''  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
fi
''',
'''  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
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
'''))
    provenance_block = '''if [[ ! -f "$PROVENANCE_HELPER" ]]; then
  echo "ERROR: private Tuya input provenance helper is missing from the accepted source." >&2
  exit 6
fi
'''
    replacements.append((provenance_block, provenance_block + '''if [[ ! -f "$BUILD_SUBJECT_HELPER" ]]; then
  echo "ERROR: CocoaPods generated build-subject helper is missing from the accepted source." >&2
  exit 18
fi
'''))
    replacements.append((
'''printf 'Resolving the official Tuya SmartLife iOS SDK and private field identity for Nembra Capture...\n'
# `pod install` preserves an existing Podfile.lock instead of silently upgrading
''',
'''if [[ "$REVIEW_ONLY" == "0" ]]; then
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
'''))
    version_block = '''for expected in \\
  "  - ThingSmartHomeKit (7.8.0)" \\
  "  - ThingSmartBusinessExtensionKit (7.8.0)"
do
  if ! grep -Fq -- "$expected" Podfile.lock; then
    echo "ERROR: resolved Tuya SDK does not match the exact reviewed 7.8.0 field dependency: $expected" >&2
    exit 11
  fi
done

# Snapshot every ignored input that can materially change the private field
'''
    replacements.append((version_block, version_block.replace(
        "# Snapshot every ignored input that can materially change the private field\n",
'''if ! COCOAPODS_BUILD_SUBJECT_SHA256="$(/usr/bin/python3 -I "$BUILD_SUBJECT_HELPER" \\
  --pods "$REPO_ROOT/Pods" \\
  --workspace "$REPO_ROOT/NembraCapture.xcworkspace")"
then
  echo "ERROR: CocoaPods generated build subject could not be fingerprinted." >&2
  exit 21
fi
[[ "$COCOAPODS_BUILD_SUBJECT_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: CocoaPods generated build-subject fingerprint is malformed." >&2
  exit 22
}

# Snapshot every ignored input that can materially change the private field
''')))
    replacements.append((
'''DEPENDENCY LOCK CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY
  Podfile.lock SHA-256: $LOCK_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

Review and bind this exact dependency-lock digest to the exact accepted Capture
source through the current Final-GO control plane before any field build/install.
Then rerun the normal bootstrap/installer with that accepted digest supplied as
NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256. This review-only mode never invokes
''',
'''DEPENDENCY BUILD SUBJECT CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY
  Podfile.lock SHA-256: $LOCK_SHA256
  CocoaPods generated build-subject SHA-256: $COCOAPODS_BUILD_SUBJECT_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

Review and bind both exact dependency digests to the exact accepted Capture
source through the current Final-GO control plane before any field build/install.
Then rerun the normal bootstrap/installer with those accepted digests supplied as
NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 and
NEMBRA_CAPTURE_ACCEPTED_COCOAPODS_BUILD_SUBJECT_SHA256. This review-only mode never invokes
'''))
    replacements.append((
'''[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
  echo "ERROR: resolved Podfile.lock does not match the preaccepted dependency-lock SHA-256. Stop before xcodebuild/install and review the new dependency subject." >&2
  exit 16
}
printf 'Preaccepted Tuya dependency lock matched: %s\n' "$LOCK_SHA256"
unset ACCEPTED_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 || true
''',
'''[[ "$LOCK_SHA256" == "$ACCEPTED_LOCK_SHA256" ]] || {
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
'''))
    for old, new in replacements:
        if bootstrap.count(old) != 1:
            raise SystemExit(f"bootstrap anchor count {bootstrap.count(old)} for {old[:50]!r}")
        bootstrap = bootstrap.replace(old, new, 1)
    bootstrap_path.write_text(bootstrap)

workflow_path = Path(".github/workflows/capture-field-build-provenance.yml")
workflow = workflow_path.read_text()
if "test_capture_cocoapods_generated_build_subject.py" not in workflow:
    replacements = [
        (
            "      - Scripts/capture_tuya_private_input_provenance.py\n      - Scripts/capture_tuya_private_input_build_guard.py\n",
            "      - Scripts/capture_tuya_private_input_provenance.py\n      - Scripts/capture_cocoapods_build_subject.py\n      - Scripts/capture_tuya_private_input_build_guard.py\n",
        ),
        (
            "      - scripts/ci/tests/test_capture_tuya_private_input_provenance.py\n      - scripts/ci/tests/test_capture_apple_signin_field_entitlement_custody.py\n",
            "      - scripts/ci/tests/test_capture_tuya_private_input_provenance.py\n      - scripts/ci/tests/test_capture_cocoapods_generated_build_subject.py\n      - scripts/ci/tests/test_capture_apple_signin_field_entitlement_custody.py\n",
        ),
        (
            "          /usr/bin/python3 -m py_compile Scripts/capture_tuya_private_input_provenance.py\n          /usr/bin/python3 scripts/ci/tests/test_capture_tuya_private_input_provenance.py\n",
            "          /usr/bin/python3 -m py_compile Scripts/capture_tuya_private_input_provenance.py Scripts/capture_cocoapods_build_subject.py\n          /usr/bin/python3 -I Scripts/capture_cocoapods_build_subject.py --self-test\n          /usr/bin/python3 scripts/ci/tests/test_capture_tuya_private_input_provenance.py\n          /usr/bin/python3 scripts/ci/tests/test_capture_cocoapods_generated_build_subject.py\n",
        ),
    ]
    for old, new in replacements:
        if workflow.count(old) != 1:
            raise SystemExit(f"workflow anchor count {workflow.count(old)} for {old[:50]!r}")
        workflow = workflow.replace(old, new, 1)
    workflow_path.write_text(workflow)
