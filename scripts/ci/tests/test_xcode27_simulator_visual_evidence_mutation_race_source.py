#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HARNESS = ROOT / "scripts" / "ci" / "xcode27_simulator_capture.sh"
source = HARNESS.read_text(encoding="utf-8")
marker = 'VISUAL_EVIDENCE_MANIFEST="$ARTIFACTS_DIR/NembraCaptureSimulatorVisualEvidence.json"'
start = source.find(marker)
if start < 0:
    raise SystemExit("Simulator harness must publish retained visual evidence")
visual = source[start:]

# Opening the final file descriptor must itself be non-blocking. O_NOFOLLOW stops
# the final component from being a symlink, but a same-UID replacement to a FIFO
# can otherwise block O_RDONLY before fstat has a chance to reject the subject.
if "O_NONBLOCK" not in visual:
    raise SystemExit("retained visual evidence file admission must use O_NONBLOCK before fstat regular-file validation")
if "FILE_FLAGS" not in visual or "O_NONBLOCK" not in visual[visual.find("FILE_FLAGS"):visual.find("FILE_FLAGS") + 220]:
    raise SystemExit("final retained-evidence FILE_FLAGS must include O_NONBLOCK")

# Directory/root custody must remain stable around enumeration. The stronger
# manifest-publication successor must not regress the pre/post identity proof
# that existed in the earlier descriptor-custody implementation.
required_markers = (
    "st_nlink",
    "directory changed during enumeration",
    "artifact root changed during visual-evidence enumeration",
)
for token in required_markers:
    if token not in visual:
        raise SystemExit(f"visual evidence ancestry mutation contract missing {token!r}")

if visual.count("os.fstat(") < 6:
    raise SystemExit("visual evidence custody must fstat file, directory, and artifact-root subjects before/after mutation-sensitive work")

# Preserve #1143's stronger publication result while tightening admission races.
for token in (
    "os.O_EXCL",
    "dir_fd=artifacts_fd",
    "hashlib.sha256(manifest_bytes).hexdigest()",
):
    if token not in visual:
        raise SystemExit(f"descriptor-published manifest contract regressed: missing {token!r}")

print("Simulator visual-evidence mutation-race source contract: PASS")
