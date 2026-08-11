#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = "bccdab041235982ee95a9a4bd366d7b1ec50ccda"
INGREDIENT_PARENT = "da86226ba36bb2d4f441cc3cb876244af17853cb"
INGREDIENT_HEAD = "d8416aeba19b826cfb50bde9e0b3e2778766a286"
ISSUER = "scripts/ci/es80_authenticated_stationary_final_go.py"
MAIN_TEST = "scripts/ci/tests/test_es80_authenticated_stationary_final_go.py"
ENV_TEST = "scripts/ci/tests/test_es80_authenticated_stationary_final_go_installer_environment_custody.py"
SIGNED_TEST = "scripts/ci/tests/test_es80_authenticated_stationary_signed_artifact.py"


def run(*args: str, capture: bool = False) -> str:
    completed = subprocess.run(
        list(args),
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return completed.stdout if capture else ""


run("git", "fetch", "--no-tags", "origin", INGREDIENT_PARENT, INGREDIENT_HEAD)
patch = run(
    "git", "diff", "--binary", INGREDIENT_PARENT, INGREDIENT_HEAD, "--", ISSUER, MAIN_TEST,
    capture=True,
)
if not patch.strip():
    raise SystemExit("reviewed-lock core ingredient diff is empty")
patch_path = Path("/tmp/nembra-reviewed-lock-core.patch")
patch_path.write_text(patch)
run("git", "apply", "--3way", str(patch_path))
unmerged = run("git", "diff", "--name-only", "--diff-filter=U", capture=True).strip()
if unmerged:
    raise SystemExit(f"unexpected core conflict: {unmerged}")

env_path = ROOT / ENV_TEST
source = env_path.read_text()
replacements = [
    (
        '            installer = repository / GO.INSTALLER\n',
        '            accepted_lock = "a" * 64\n            installer = repository / GO.INSTALLER\n',
    ),
    (
        '                f"[[ \\\"${{PATH:-}}\\\" == {GO.TRUSTED_INSTALLER_PATH!r} ]] || exit 46\\n"\n',
        '                f"[[ \\\"${{PATH:-}}\\\" == {GO.TRUSTED_INSTALLER_PATH!r} ]] || exit 46\\n"\n'
        '                f"[[ \\\"${{NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:-}}\\\" == {accepted_lock!r} ]] || exit 47\\n"\n',
    ),
    (
        '            os.environ["NEMBRA_TUYA_APP_KEY"] = "caller-key-must-not-cross"\n',
        '            os.environ["NEMBRA_TUYA_APP_KEY"] = "caller-key-must-not-cross"\n'
        '            os.environ["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"] = "b" * 64\n',
    ),
    (
        '                result = GO.installer(repository, source, private_device)\n',
        '                result = GO.installer(repository, source, private_device, accepted_lock)\n',
    ),
    (
        '            env = GO.installer_environment(device)\n',
        '            accepted_lock = "c" * 64\n            env = GO.installer_environment(device, accepted_lock)\n',
    ),
    (
        '            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"], str(device))\n',
        '            self.assertEqual(env["NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"], str(device))\n'
        '            self.assertEqual(env["NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"], accepted_lock)\n',
    ),
    (
        '                GO.installer_environment(alias / "device")\n',
        '                GO.installer_environment(alias / "device", "d" * 64)\n',
    ),
]
for old, new in replacements:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"environment-custody seam changed ({count}): {old!r}")
    source = source.replace(old, new, 1)
marker = '    def test_installer_environment_rejects_symlinked_private_device_parent(self) -> None:\n'
extra = '''    def test_noncanonical_tuya_lock_digest_is_rejected_before_installer(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-final-go-lock-shape-") as temporary:
            device = Path(temporary).resolve(strict=True) / "device"
            device.write_text("device", encoding="utf-8")
            device.chmod(0o600)
            for digest in ("A" * 64, "a" * 63, "not-a-digest"):
                with self.assertRaises(GO.GoError):
                    GO.installer_environment(device, digest)

'''
if source.count(marker) != 1:
    raise SystemExit("symlink regression marker changed")
env_path.write_text(source.replace(marker, extra + marker, 1))

issuer = (ROOT / ISSUER).read_text()
required = [
    'stable_pr=("number","headSHA","headBranch","base","mainSHA","state","merged","draft")',
    '"mainSHA":main_sha',
    'nembra-capture-human-review-github-v2',
    'NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256',
    'retained signed artifact Tuya dependency lock does not match prebuild GitHub review',
]
for token in required:
    if token not in issuer:
        raise SystemExit(f"required composed authority token missing: {token}")

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
for path in (ISSUER, MAIN_TEST, ENV_TEST):
    compile((ROOT / path).read_text(), path, "exec")
run("python3", "-B", MAIN_TEST)
run("python3", "-B", ENV_TEST)
run("python3", "-B", SIGNED_TEST)
if any(ROOT.glob("scripts/ci/**/__pycache__")):
    raise SystemExit("validation created Python bytecode residue")

product = sorted(
    p for p in run("git", "diff", "--name-only", BASE, capture=True).splitlines()
    if not p.startswith(".github/workflows/tmp-v14-final-go-reviewed-tuya-lock-current")
    and p != "scripts/ci/tmp_v14_converge_reviewed_lock.py"
)
expected = sorted([ISSUER, MAIN_TEST, ENV_TEST])
if product != expected:
    raise SystemExit(f"unexpected product scope: {product!r}")
print("reviewed Tuya lock convergence validated")
