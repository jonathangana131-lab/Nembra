#!/usr/bin/env python3
from pathlib import Path

CANONICAL_KEY = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256"
STALE_KEY = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_MANIFEST_SHA256"

bootstrap_path = Path("Scripts/bootstrap_capture_tuya_sdk.sh")
bootstrap = bootstrap_path.read_text()
if CANONICAL_KEY in bootstrap or STALE_KEY in bootstrap:
    raise SystemExit("bootstrap generated-manifest authority seam unexpectedly already present")

anchor = 'PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"\n'
replacement = anchor + 'ACCEPTED_BUILD_INPUT_HELPER="$REPO_ROOT/scripts/ci/capture_accepted_build_input_snapshot.py"\n'
if bootstrap.count(anchor) != 1:
    raise SystemExit("bootstrap provenance-helper anchor drifted")
bootstrap = bootstrap.replace(anchor, replacement, 1)

old = '''  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
fi
'''
new = '''  ACCEPTED_LOCK_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256" | tr '[:upper:]' '[:lower:]')"
  : "${NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256:?Set NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256 to the Final-GO-preaccepted generated/private compiler-input manifest SHA-256 before field bootstrap.}"
  [[ "$NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    echo "ERROR: NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256 must be exactly 64 hex characters." >&2
    exit 1
  }
  ACCEPTED_GENERATED_MANIFEST_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256" | tr '[:upper:]' '[:lower:]')"
else
  unset NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256 || true
  ACCEPTED_LOCK_SHA256=""
  ACCEPTED_GENERATED_MANIFEST_SHA256=""
fi
'''
if bootstrap.count(old) != 1:
    raise SystemExit("bootstrap accepted-lock authority anchor drifted")
bootstrap = bootstrap.replace(old, new, 1)

old = '''if [[ ! -f "$PROVENANCE_HELPER" ]]; then
  echo "ERROR: private Tuya input provenance helper is missing from the accepted source." >&2
  exit 6
fi
'''
new = old + '''if [[ ! -f "$ACCEPTED_BUILD_INPUT_HELPER" ]]; then
  echo "ERROR: accepted generated-input manifest helper is missing from the accepted source." >&2
  exit 6
fi
'''
if bootstrap.count(old) != 1:
    raise SystemExit("bootstrap helper-presence anchor drifted")
bootstrap = bootstrap.replace(old, new, 1)

anchor = '''[[ -f "$DEPENDENCY_PROVENANCE" ]] || {
  echo "ERROR: private Tuya dependency provenance record was not created." >&2
  exit 14
}
'''
insertion = anchor + '''SOURCE_SHA="$(GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || {
  echo "ERROR: accepted source SHA is unavailable while generating the compiler-input manifest." >&2
  exit 14
}
GENERATED_MANIFEST_SHA256="$(
  /usr/bin/python3 -I "$ACCEPTED_BUILD_INPUT_HELPER" manifest \
    --root "$REPO_ROOT" \
    --source-sha "$SOURCE_SHA" | \
    /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}' | /usr/bin/tr '[:upper:]' '[:lower:]'
)" || {
  echo "ERROR: accepted generated/private compiler-input manifest could not be fingerprinted." >&2
  exit 14
}
[[ "$GENERATED_MANIFEST_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
  echo "ERROR: generated/private compiler-input manifest SHA-256 is malformed." >&2
  exit 14
}
'''
if bootstrap.count(anchor) != 1:
    raise SystemExit("bootstrap manifest-generation anchor drifted")
bootstrap = bootstrap.replace(anchor, insertion, 1)

old = '''  Podfile.lock SHA-256: $LOCK_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

Review and bind this exact dependency-lock digest to the exact accepted Capture
source through the current Final-GO control plane before any field build/install.
Then rerun the normal bootstrap/installer with that accepted digest supplied as
NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256. This review-only mode never invokes
xcodebuild, installs Nembra, scans Bluetooth, or authorizes a physical attempt.
'''
new = '''  Podfile.lock SHA-256: $LOCK_SHA256
  Generated/private compiler-input manifest SHA-256: $GENERATED_MANIFEST_SHA256
  Local private-input fingerprint record: $DEPENDENCY_PROVENANCE

Review and bind both exact digests to the exact accepted Capture source through
the current Final-GO control plane before any field build/install. Then rerun
the normal bootstrap/installer with the accepted digests supplied as
NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 and
NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256. This review-only
mode never invokes xcodebuild, installs Nembra, scans Bluetooth, or authorizes a physical attempt.
'''
if bootstrap.count(old) != 1:
    raise SystemExit("bootstrap review-output anchor drifted")
bootstrap = bootstrap.replace(old, new, 1)

old = '''printf 'Preaccepted Tuya dependency lock matched: %s\\n' "$LOCK_SHA256"
unset ACCEPTED_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 || true
'''
new = '''printf 'Preaccepted Tuya dependency lock matched: %s\\n' "$LOCK_SHA256"
[[ "$GENERATED_MANIFEST_SHA256" == "$ACCEPTED_GENERATED_MANIFEST_SHA256" ]] || {
  echo "ERROR: generated/private compiler inputs do not match the Final-GO-preaccepted manifest SHA-256. Stop before xcodebuild/install and review the new generated-input subject." >&2
  exit 17
}
printf 'Preaccepted generated/private compiler-input manifest matched: %s\\n' "$GENERATED_MANIFEST_SHA256"
unset ACCEPTED_LOCK_SHA256 ACCEPTED_GENERATED_MANIFEST_SHA256 NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256 NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256 || true
'''
if bootstrap.count(old) != 1:
    raise SystemExit("bootstrap normal-authority anchor drifted")
bootstrap = bootstrap.replace(old, new, 1)
bootstrap_path.write_text(bootstrap)

installer_path = Path("scripts/field/install_one_time_capture.command")
installer = installer_path.read_text()
if CANONICAL_KEY in installer or STALE_KEY in installer:
    raise SystemExit("installer generated-manifest authority seam unexpectedly already present")
anchor = '''say "Exact requested Capture source matched: $SOURCE_SHA"
'''
insertion = anchor + '''
: "${NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256:?Final GO must provide NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256 as the accepted generated/private compiler-input manifest SHA-256.}"
[[ "$NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256 must be exactly 64 hex characters."
NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256="$(printf '%s' "$NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256" | tr '[:upper:]' '[:lower:]')"
export NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256
'''
if installer.count(anchor) != 1:
    raise SystemExit("installer source-authority anchor drifted")
installer = installer.replace(anchor, insertion, 1)

old = '''        --install-custody-base64 "$SIGNED_APP_CUSTODY_HELPER_BASE64" \\
        --install-custody-blob "$SIGNED_APP_CUSTODY_HELPER_BLOB" \\
        -- \\
'''
new = '''        --install-custody-base64 "$SIGNED_APP_CUSTODY_HELPER_BASE64" \\
        --install-custody-blob "$SIGNED_APP_CUSTODY_HELPER_BLOB" \\
        --accepted-generated-manifest-sha256 "$NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256" \\
        -- \\
'''
if installer.count(old) != 1:
    raise SystemExit("installer orchestrator-call anchor drifted")
installer = installer.replace(old, new, 1)

old = ''')"; then
    die "The signed build could not bind frozen selected-Xcode execution to isolated compiler output and protected install custody. No field artifact was admitted."
fi

[[ "$BUILD_ORIGIN_CUSTODY_RESULT" == *$'\\t'* ]] || die "Build-origin custody returned no canonical stage/fingerprint record."
'''
new = ''')"; then
    die "The signed build could not bind frozen selected-Xcode execution to isolated compiler output and protected install custody. No field artifact was admitted."
fi
unset NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256 || true

[[ "$BUILD_ORIGIN_CUSTODY_RESULT" == *$'\\t'* ]] || die "Build-origin custody returned no canonical stage/fingerprint record."
'''
if installer.count(old) != 1:
    raise SystemExit("installer post-orchestrator anchor drifted")
installer = installer.replace(old, new, 1)
installer_path.write_text(installer)

test_path = Path("scripts/ci/tests/test_capture_field_strict_accepted_root_wiring.py")
if test_path.exists():
    raise SystemExit("strict-root wiring test unexpectedly already exists")
test_path.write_text(r'''#!/usr/bin/env python3
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CANONICAL_KEY = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256"
STALE_KEY = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_MANIFEST_SHA256"

class CaptureFieldStrictAcceptedRootWiringTests(unittest.TestCase):
    def test_review_only_bootstrap_emits_both_preacceptance_subjects(self):
        source = (ROOT / "Scripts/bootstrap_capture_tuya_sdk.sh").read_text()
        self.assertIn("Generated/private compiler-input manifest SHA-256: $GENERATED_MANIFEST_SHA256", source)
        self.assertIn(CANONICAL_KEY, source)
        self.assertNotIn(STALE_KEY, source)
        self.assertIn('[[ "$GENERATED_MANIFEST_SHA256" == "$ACCEPTED_GENERATED_MANIFEST_SHA256" ]]', source)
        self.assertIn('"$ACCEPTED_BUILD_INPUT_HELPER" manifest', source)
        self.assertIn("This review-only", source)

    def test_field_installer_requires_and_transports_preaccepted_manifest(self):
        source = (ROOT / "scripts/field/install_one_time_capture.command").read_text()
        self.assertIn("Final GO must provide " + CANONICAL_KEY, source)
        self.assertIn('--accepted-generated-manifest-sha256 "$' + CANONICAL_KEY + '"', source)
        self.assertNotIn(STALE_KEY, source)
        self.assertNotIn("capture_accepted_build_input_snapshot.py manifest", source)

    def test_orchestrator_uses_digest_to_make_strict_root_and_native_lease(self):
        source = (ROOT / "scripts/ci/capture_selected_xcode_build_orchestrator.py").read_text()
        self.assertIn("if accepted_generated_manifest_sha256 is not None:", source)
        self.assertIn("private_subjects = (accepted_root,)", source)
        self.assertIn("use_native_darwin_acl=(accepted_root is not None)", source)

if __name__ == "__main__":
    unittest.main(verbosity=2)
''')
