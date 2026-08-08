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
)
for token in required_tokens:
    if token not in visual:
        raise SystemExit(
            f"visual-evidence manifest must bind retained bytes through no-follow descriptor ancestry: missing {token!r}"
        )

forbidden_path_reopen_tokens = (
    'path.stat().st_size',
    'path.open("rb")',
    'shasum -a 256 "$VISUAL_EVIDENCE_MANIFEST"',
)
for token in forbidden_path_reopen_tokens:
    if token in visual:
        raise SystemExit(
            f"visual-evidence authority still re-resolves mutable pathname state after admission: {token!r}"
        )

if visual.count("os.fstat(") < 2:
    raise SystemExit(
        "visual-evidence hashing must re-prove descriptor identity/size after reading, not only before it"
    )

if "hashlib.sha256(manifest_bytes)" not in visual:
    raise SystemExit(
        "the published manifest digest must derive directly from the exact manifest bytes authored in-process, not a later pathname reopen"
    )

print("descriptor-bound Simulator visual-evidence custody source contract: PASS")
