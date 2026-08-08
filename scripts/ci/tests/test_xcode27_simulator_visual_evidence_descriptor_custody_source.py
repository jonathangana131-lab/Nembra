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
    "import os",
    "os.open(",
    "O_NOFOLLOW",
    "O_DIRECTORY",
    "dir_fd=",
    "os.fstat(",
    "os.fdopen(os.dup(",
    "st_nlink",
    "visual-evidence directory changed during enumeration",
    "Simulator artifact root changed during visual-evidence enumeration",
)
for token in required_tokens:
    if token not in visual:
        raise SystemExit(
            f"visual-evidence manifest must bind and re-prove retained descriptor ancestry: missing {token!r}"
        )

forbidden_path_reopen_tokens = (
    'path.stat().st_size',
    'path.open("rb")',
)
for token in forbidden_path_reopen_tokens:
    if token in visual:
        raise SystemExit(
            f"visual-evidence manifest still measures/hashes mutable pathname state instead of one descriptor: {token!r}"
        )

if visual.count("os.fstat(") < 6:
    raise SystemExit(
        "visual-evidence custody must re-prove files plus retained directories/root, not only opened file bytes"
    )

print("descriptor-bound Simulator visual-evidence custody source contract: PASS")
