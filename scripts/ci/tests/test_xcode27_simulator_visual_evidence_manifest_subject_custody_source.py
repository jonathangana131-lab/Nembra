#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HARNESS = ROOT / "scripts" / "ci" / "xcode27_simulator_capture.sh"

source = HARNESS.read_text(encoding="utf-8")
marker = 'VISUAL_EVIDENCE_MANIFEST="$ARTIFACTS_DIR/NembraCaptureSimulatorVisualEvidence.json"'
start = source.find(marker)
if start < 0:
    raise SystemExit("Simulator harness must publish a retained visual-evidence manifest")
visual = source[start:]

required_tokens = (
    'VISUAL_EVIDENCE_MANIFEST_SHA256="$(python3 -',
    'hashlib.sha256(manifest_bytes).hexdigest()',
    'os.open(manifest_name, manifest_flags, 0o600, dir_fd=artifacts_fd)',
    'os.O_CREAT | os.O_EXCL | O_NOFOLLOW',
    'os.fsync(handle.fileno())',
    'finally:\n    os.close(artifacts_fd)',
)
for token in required_tokens:
    if token not in visual:
        raise SystemExit(
            f"Simulator visual manifest must keep publication and digest bound to the open artifact-root subject: missing {token!r}"
        )

forbidden_tokens = (
    'shasum -a 256 "$VISUAL_EVIDENCE_MANIFEST"',
    'with manifest_path.open("xb") as handle:',
)
for token in forbidden_tokens:
    if token in visual:
        raise SystemExit(
            f"Simulator visual manifest still separates publication/digest authority through a mutable pathname: {token!r}"
        )

print("Simulator visual-evidence manifest subject custody source contract: PASS")
