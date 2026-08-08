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

required = (
    'manifest_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW',
    'os.open(manifest_name, manifest_flags, 0o600, dir_fd=artifacts_fd)',
    'os.fdopen(os.dup(manifest_fd), "wb", closefd=True)',
    'os.fsync(handle.fileno())',
    'manifest_after = os.fstat(manifest_fd)',
    'hashlib.sha256(manifest_bytes).hexdigest()',
    'VISUAL_EVIDENCE_MANIFEST_SHA256="$(python3 -',
)
for token in required:
    if token not in visual:
        raise SystemExit(f"visual manifest output must stay descriptor-bound and exclusive: missing {token!r}")

for forbidden in (
    'manifest_path.open("xb")',
    'shasum -a 256 "$VISUAL_EVIDENCE_MANIFEST"',
):
    if forbidden in visual:
        raise SystemExit(f"visual manifest output still reopens mutable pathname state: {forbidden!r}")

print("descriptor-bound Simulator visual-manifest output custody source contract: PASS")
