#!/usr/bin/env python3
from pathlib import Path

producer_path = Path("scripts/ci/xcode27_signed_field_candidate.sh")
producer = producer_path.read_text()

needle = '''mkdir -p "$ARTIFACTS_DIR/logs"
EXPORT_OPTIONS_SNAPSHOT="$ARTIFACTS_DIR/ExportOptions.plist"
'''
replacement = '''mkdir -p "$ARTIFACTS_DIR/logs"
# The producer owns the candidate root for diagnostics/provenance. The canonical inspector owns
# this initially-absent child and publishes it atomically with no replacement.
INSPECTOR_EVIDENCE_DIR="$ARTIFACTS_DIR/inspector-evidence"
if [[ -e "$INSPECTOR_EVIDENCE_DIR" ]]; then
  echo "Inspector evidence destination already exists; refusing non-atomic reuse: $INSPECTOR_EVIDENCE_DIR" >&2
  exit 12
fi
EXPORT_OPTIONS_SNAPSHOT="$ARTIFACTS_DIR/ExportOptions.plist"
'''
if producer.count(needle) != 1:
    raise SystemExit("producer artifact-root insertion point drifted")
producer = producer.replace(needle, replacement)

producer = producer.replace('exit 12\nfi\n\nrm -rf "$WORK_ROOT"', 'exit 13\nfi\n\nrm -rf "$WORK_ROOT"', 1)
for old, new in (("exit 13", "exit 14"), ("exit 14", "exit 15"), ("exit 15", "exit 16"), ("exit 16", "exit 17"), ("exit 17", "exit 18")):
    pass
# Exit numbers are diagnostic only; leave the existing later values stable to avoid a noisy rewrite.

old = '''  --intended-device-udid "$NEMBRA_FIELD_DEVICE_UDID" \\
  --output-dir "$ARTIFACTS_DIR"

EXTERNAL_RECORD="$ARTIFACTS_DIR/NembraCaptureExternalBuildRecord.json"
FIELD_BUILD_RECORD="$ARTIFACTS_DIR/NembraCaptureFieldBuildEvidenceRecord.json"
SIGNING_INSPECTION="$ARTIFACTS_DIR/NembraCaptureSignedFieldArtifactInspection.json"
RETAINED_IPA="$ARTIFACTS_DIR/build-evidence/NembraField.ipa"
'''
new = '''  --intended-device-udid "$NEMBRA_FIELD_DEVICE_UDID" \\
  --output-dir "$INSPECTOR_EVIDENCE_DIR"

EXTERNAL_RECORD="$INSPECTOR_EVIDENCE_DIR/NembraCaptureExternalBuildRecord.json"
FIELD_BUILD_RECORD="$INSPECTOR_EVIDENCE_DIR/NembraCaptureFieldBuildEvidenceRecord.json"
SIGNING_INSPECTION="$INSPECTOR_EVIDENCE_DIR/NembraCaptureSignedFieldArtifactInspection.json"
RETAINED_IPA="$INSPECTOR_EVIDENCE_DIR/build-evidence/NembraField.ipa"
'''
if producer.count(old) != 1:
    raise SystemExit("canonical inspector invocation block drifted")
producer = producer.replace(old, new)

old_env = '''  echo "export_options_sha256=$EXPORT_OPTIONS_SHA256"
  echo "archive_log=logs/xcodebuild-archive.log"
  echo "export_log=logs/xcodebuild-export.log"
'''
new_env = '''  echo "export_options_sha256=$EXPORT_OPTIONS_SHA256"
  echo "inspector_evidence_dir=inspector-evidence"
  echo "archive_log=logs/xcodebuild-archive.log"
  echo "export_log=logs/xcodebuild-export.log"
'''
if producer.count(old_env) != 1:
    raise SystemExit("candidate environment block drifted")
producer = producer.replace(old_env, new_env)

old_tail = '''} > "$ARTIFACTS_DIR/field-candidate-environment.txt"

echo "Signed Nembra iOS field-build CANDIDATE retained at: $ARTIFACTS_DIR"
'''
new_tail = '''} > "$ARTIFACTS_DIR/field-candidate-environment.txt"

# This marker is admitted only after the inspector has atomically published its immutable child and
# all producer-side cross-checks/environment evidence have completed. Its absence means diagnostics
# may exist, but there is no complete field candidate bundle.
printf '%s\\n' "CANDIDATE_EVIDENCE_COMPLETE_NOT_FIELD_AUTHORIZATION" > "$ARTIFACTS_DIR/CANDIDATE_COMPLETE"

echo "Signed Nembra iOS field-build CANDIDATE retained at: $ARTIFACTS_DIR"
'''
if producer.count(old_tail) != 1:
    raise SystemExit("candidate completion insertion point drifted")
producer = producer.replace(old_tail, new_tail)
producer_path.write_text(producer)

# Update the source contract so future convergence cannot re-use the producer-owned root as the
# inspector's no-replace destination.
test_path = Path("scripts/ci/tests/test_xcode27_signed_field_candidate_source.py")
test = test_path.read_text()
test = test.replace(
    "        self.assertIn('--output-dir \"$ARTIFACTS_DIR\"', self.source)\n",
    '''        self.assertIn('INSPECTOR_EVIDENCE_DIR="$ARTIFACTS_DIR/inspector-evidence"', self.source)\n        self.assertIn('if [[ -e "$INSPECTOR_EVIDENCE_DIR" ]]', self.source)\n        self.assertIn('--output-dir "$INSPECTOR_EVIDENCE_DIR"', self.source)\n        self.assertNotIn('--output-dir "$ARTIFACTS_DIR"', self.source)\n        self.assertIn('inspector_evidence_dir=inspector-evidence', self.source)\n        self.assertIn('CANDIDATE_EVIDENCE_COMPLETE_NOT_FIELD_AUTHORIZATION', self.source)\n''',
)
if '--output-dir "$INSPECTOR_EVIDENCE_DIR"' not in test:
    raise SystemExit("producer source test did not receive inspector output separation")
test_path.write_text(test)

# Keep the field runbook honest about where immutable inspector subjects live.
doc_path = Path("docs/ES80_SIGNED_FIELD_CANDIDATE_PRODUCTION.md")
doc = doc_path.read_text()
doc = doc.replace(
    "The producer does not create another field evidence schema. The machine-readable subjects remain:\n\n- `NembraCaptureExternalBuildRecord.json`",
    "The producer does not create another field evidence schema. The canonical inspector exclusively owns and atomically publishes the initially absent `inspector-evidence/` child. Its machine-readable subjects remain:\n\n- `inspector-evidence/NembraCaptureExternalBuildRecord.json`",
)
doc = doc.replace("- `NembraCaptureFieldBuildEvidenceRecord.json`", "- `inspector-evidence/NembraCaptureFieldBuildEvidenceRecord.json`")
doc = doc.replace("- `NembraCaptureSignedFieldArtifactInspection.json`", "- `inspector-evidence/NembraCaptureSignedFieldArtifactInspection.json`")
doc = doc.replace("- `build-evidence/NembraField.ipa`", "- `inspector-evidence/build-evidence/NembraField.ipa`")
doc = doc.replace(
    "- the canonical inspector outputs listed above;\n- `field-candidate-environment.txt`",
    "- the atomically published immutable `inspector-evidence/` child listed above;\n- `field-candidate-environment.txt`",
)
doc = doc.replace(
    "The archive and export commands are piped through `tee`; failure from either Xcode or log capture is a producer failure.",
    "The archive and export commands are piped through `tee`; failure from either Xcode or log capture is a producer failure. The candidate root may therefore retain partial diagnostics after failure, but it is not a complete candidate without the final `CANDIDATE_COMPLETE` marker. That marker is written only after the inspector atomically publishes its no-replace child and all cross-checks succeed.",
)
doc_path.write_text(doc)

# Transform-time assertions.
final = producer_path.read_text()
assert '--output-dir "$INSPECTOR_EVIDENCE_DIR"' in final
assert '--output-dir "$ARTIFACTS_DIR"' not in final
assert 'INSPECTOR_EVIDENCE_DIR="$ARTIFACTS_DIR/inspector-evidence"' in final
assert 'CANDIDATE_EVIDENCE_COMPLETE_NOT_FIELD_AUTHORIZATION' in final
