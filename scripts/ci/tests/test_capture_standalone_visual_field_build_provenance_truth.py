from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
workflow = (root / ".github/workflows/capture-standalone-visual-evidence.yml").read_text(encoding="utf-8")
script = (root / "scripts/ci/capture_standalone_visual_evidence.sh").read_text(encoding="utf-8")
identity = (root / "NembraApp/App/NembraCaptureBuildIdentity.swift").read_text(encoding="utf-8")

# NembraCaptureBuildIdentity currently treats a syntactically valid 64-hex Tuya
# dependency-lock stamp as part of authoritative field-build identity. A public
# Simulator visual gate therefore must not mint a plausible-looking placeholder
# and then screenshot the UI as though reviewed dependency provenance existed.
required_identity_contract = [
    "tuyaDependencyLockSHA256.count == 64",
    "var isAuthoritativeFieldBuild: Bool",
]
for needle in required_identity_contract:
    if needle not in identity:
        raise SystemExit(f"missing Capture field-build identity contract: {needle}")

literal_dependency_stamp = re.search(
    r"(?m)^\s*dependency_sha=['\"]([0-9a-f]{64})['\"]\s*$",
    workflow,
)
if literal_dependency_stamp:
    raise SystemExit(
        "standalone visual evidence must not mint field-build authority from a hard-coded "
        f"Tuya dependency placeholder: {literal_dependency_stamp.group(1)}"
    )

# This harness is intentionally the public/unprovisioned presentation gate. Its
# retained manifest must make the field-build boundary explicit, just as it already
# does for physical/protocol authority. If reviewed private dependency provenance is
# unavailable, the app must remain visibly build-blocked rather than be synthetically
# promoted for a prettier screenshot.
if '"fieldBuildAuthorityCreated": False' not in script:
    raise SystemExit(
        "standalone public visual evidence must explicitly record fieldBuildAuthorityCreated=false"
    )

if '"physicalAuthorityCreated": False' not in script or '"protocolAuthorityCreated": False' not in script:
    raise SystemExit("existing physical/protocol no-authority manifest boundaries must remain explicit")

print("capture standalone visual field-build provenance truth contract: PASS")
