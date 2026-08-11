#!/usr/bin/env python3
from pathlib import Path
import subprocess

BASE = "fd1ba71c3f3df0f2a0a78b445138c85cb05c1181"
BRANCH = "agent/v14-capture-live-main-visual-acceptance-sol"
WORKFLOW = Path(".github/workflows/tmp-capture-ax-copy-truth.yml")
SCRIPT = Path("scripts/ci/tmp_capture_ax_copy_truth.py")
ROOT = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift")


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(args, check=True, text=True, capture_output=capture)
    return result.stdout if capture else ""


run("git", "merge-base", "--is-ancestor", BASE, "HEAD")
changed = set(run("git", "diff", "--name-only", f"{BASE}..HEAD", capture=True).splitlines())
allowed = {str(WORKFLOW), str(SCRIPT)}
assert changed <= allowed, f"unexpected product drift before materialization: {sorted(changed - allowed)}"

source = ROOT.read_text()
old = 'Text("Account setup only in this public build.")'
new = 'Text(fieldBuildIsAuthoritative ? "Account metadata only here. Bluetooth stays locked until preflight verifies account and scooter authority." : "Account setup only in this public build.")'
assert source.count(old) == 1, f"expected exactly one AX public-copy anchor, found {source.count(old)}"
source = source.replace(old, new, 1)
ROOT.write_text(source)

tests = TEST.read_text()
old_test = '#expect(root.contains("Account setup only in this public build."))'
new_test = '#expect(root.contains("fieldBuildIsAuthoritative ? \\"Account metadata only here. Bluetooth stays locked until preflight verifies account and scooter authority.\\" : \\"Account setup only in this public build.\\""))'
assert tests.count(old_test) == 1, f"expected exactly one stale AX-copy assertion, found {tests.count(old_test)}"
tests = tests.replace(old_test, new_test, 1)
TEST.write_text(tests)

assert new in ROOT.read_text()
assert "Account metadata only here. Bluetooth stays locked until preflight verifies account and scooter authority." in TEST.read_text()

WORKFLOW.unlink(missing_ok=False)
SCRIPT.unlink(missing_ok=False)
run("git", "diff", "--check")

final_changed = set(run("git", "diff", "--name-only", BASE, capture=True).splitlines())
expected = {str(ROOT), str(TEST)}
assert final_changed == expected, f"unexpected final delta: {sorted(final_changed)}"

run("git", "config", "user.name", "nembra-v14-materializer")
run("git", "config", "user.email", "nembra-v14-materializer@users.noreply.github.com")
run("git", "add", "-A")
run("git", "commit", "-m", "fix(capture): scope AX public copy to public builds")
run("git", "push", "origin", f"HEAD:{BRANCH}")
