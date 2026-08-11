#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BRANCH = "integration/v14-field-private-identity-sol-20260811"
FIELD_PARENT = "9aaa30918d66dc0a31706009d1d31a324850e558"
PRIVATE_BRANCH = "repair/v14-private-identity-final-name-after-crash-sol-20260811"
PRIVATE_HEAD = "3f662b7a3f3da667ce3f916ee3f0a65629269c8a"
SELF = Path(__file__)
TEMP_WORKFLOW = ROOT / ".github/workflows/tmp-v14-field-private-identity-sol.yml"

PRIVATE_FILES = (
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCapturePrimaryLanguageSourceTests.swift",
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaMetadataAccountUIDCustodySourceTests.swift",
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaMetadataSecretRedactionSourceTests.swift",
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift",
    "Scripts/provision_capture_tuya_identity.sh",
    "Scripts/provision_capture_tuya_identity_writer.py",
    "scripts/ci/tests/test_capture_private_identity_crash_residue.py",
    "scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py",
)


def run(*argv: str) -> str:
    return subprocess.check_output(argv, cwd=ROOT, text=True).strip()


subprocess.run(["/usr/bin/git", "merge-base", "--is-ancestor", FIELD_PARENT, "HEAD"], cwd=ROOT, check=True)
construction_delta = {
    line for line in run("git", "diff", "--name-only", f"{FIELD_PARENT}..HEAD").splitlines() if line
}
allowed = {SELF.relative_to(ROOT).as_posix(), TEMP_WORKFLOW.relative_to(ROOT).as_posix()}
if not construction_delta or not construction_delta.issubset(allowed):
    raise SystemExit("construction branch contains non-temporary drift before private composition: " + ", ".join(sorted(construction_delta)))
if run("git", "status", "--porcelain=v1", "--untracked-files=all"):
    raise SystemExit("construction checkout is not clean")

subprocess.run(
    [
        "/usr/bin/git", "fetch", "--no-tags", "origin",
        f"refs/heads/{PRIVATE_BRANCH}:refs/remotes/origin/{PRIVATE_BRANCH}",
    ],
    cwd=ROOT,
    check=True,
)
actual_private = run("git", "rev-parse", f"refs/remotes/origin/{PRIVATE_BRANCH}")
if actual_private != PRIVATE_HEAD:
    raise SystemExit(f"private identity source moved: {actual_private} != {PRIVATE_HEAD}")

# Verify the advertised source delta remains exactly nine files and deliberately
# keep its workflow file for connector publication after product/test validation.
private_base = "70b95a1a6be594045adf3d2e7769f682befabaf8"
source_delta = {
    line for line in run("git", "diff", "--name-only", f"{private_base}..{PRIVATE_HEAD}").splitlines() if line
}
expected_delta = set(PRIVATE_FILES) | {".github/workflows/capture-private-identity-publication-races-redteam.yml"}
if source_delta != expected_delta:
    raise SystemExit("private identity source delta changed: " + ", ".join(sorted(source_delta)))

for relative in PRIVATE_FILES:
    payload = subprocess.check_output(["/usr/bin/git", "show", f"{PRIVATE_HEAD}:{relative}"], cwd=ROOT)
    target = ROOT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(payload)

writer = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
shell = ROOT / "Scripts/provision_capture_tuya_identity.sh"
crash = ROOT / "scripts/ci/tests/test_capture_private_identity_crash_residue.py"
final_name = ROOT / "scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py"
publication = ROOT / "scripts/ci/tests/test_capture_private_identity_publication_races.py"
same_inode = ROOT / "scripts/ci/tests/test_capture_private_identity_same_inode_payload_current.py"
ancestor = ROOT / "scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py"

subprocess.run(["/usr/bin/python3", "-m", "py_compile", str(writer), str(crash), str(final_name), str(publication), str(same_inode), str(ancestor)], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/python3", str(writer), "--self-test"], cwd=ROOT, check=True)
for test in (publication, same_inode, ancestor, crash, final_name):
    subprocess.run(["/usr/bin/python3", "-I", str(test.relative_to(ROOT))], cwd=ROOT, check=True)
subprocess.run(["/bin/bash", "-n", str(shell)], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/swift", "test", "--package-path", "Packages/NembraBluetoothCapture"], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/git", "diff", "--check"], cwd=ROOT, check=True)

# Production shell must pin the exact converged writer and the package source
# contract must agree before the combined candidate is allowed to publish.
writer_sha256 = subprocess.check_output(["/usr/bin/shasum", "-a", "256", str(writer)], cwd=ROOT, text=True).split()[0]
shell_text = shell.read_text(encoding="utf-8")
swift_contract = (ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift").read_text(encoding="utf-8")
if writer_sha256 not in shell_text or writer_sha256 not in swift_contract:
    raise SystemExit("private identity writer digest is not consistently pinned in shell + package contract")

SELF.unlink()
subprocess.run(["/usr/bin/git", "add", *PRIVATE_FILES, str(SELF.relative_to(ROOT))], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/git", "diff", "--cached", "--check"], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/git", "config", "user.name", "nembra-sol-bot"], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/git", "config", "user.email", "nembra-sol-bot@users.noreply.github.com"], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/git", "commit", "-m", "Compose strongest private identity onto field authority"], cwd=ROOT, check=True)
subprocess.run(["/usr/bin/git", "push", "origin", f"HEAD:{BRANCH}"], cwd=ROOT, check=True)
print(f"composed private identity {PRIVATE_HEAD} onto field authority {FIELD_PARENT}; writer sha256 {writer_sha256}")
