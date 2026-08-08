#!/usr/bin/env python3
from pathlib import Path

SOURCE = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
text = SOURCE.read_text(encoding="utf-8")

# The Share surface must export the exact already-verified artifact bytes, not a mutable
# temporary pathname that can diverge after integrity verification.
assert "ShareLink(item: shareURL)" not in text, (
    "Capture Share still hands ShareLink a mutable file URL after verifying separate in-memory bytes"
)
assert "FileManager.default.temporaryDirectory" not in text, (
    "Capture Share still stages the accepted artifact through a mutable temporary pathname"
)

# Keep the verified byte subject as the share authority. The eventual implementation may use
# Data directly or a Transferable wrapper, but the actual share item must derive from the exact
# retained verified bytes rather than reopening/re-resolving a pathname.
share_anchor = "finalShareData"
assert share_anchor in text, "verified final Share bytes are no longer retained"
assert (
    "ShareLink(item: finalShareData" in text
    or "VerifiedFinalShareTransfer" in text
    or "FinalShareTransfer" in text
), (
    "Capture Share must expose the exact verified bytes (directly or through a byte-backed Transferable)"
)

# Readiness must remain tied to successful integrity inspection, not merely successful staging.
assert "finalShareIntegrityReport != nil" in text
assert "PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)" in text

print("PASS: Capture Share is bound to exact verified bytes rather than a mutable temporary pathname")
