#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
WRITER = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
SHELL = ROOT / "Scripts/provision_capture_tuya_identity.sh"
SWIFT = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift"
WORKFLOW = ROOT / ".github/workflows/capture-private-identity-publication-races-redteam.yml"
ATTACK = ROOT / "scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py"
SELF = Path(__file__)
TEMP_WORKFLOW = ROOT / ".github/workflows/tmp-v14-private-identity-final-name-binding-sol.yml"

EXPECTED_BLOBS = {
    WRITER: "ed473ca81fed3a729c4618c65c2fcd0d272987a5",
    SHELL: "e8b2da09350ffb1e53ceb13bd69e3dcea33a7daf",
    SWIFT: "43d8c83d543efdfe7aafc219e6eb1f79d091cb4a",
    WORKFLOW: "b4e3ca960b4dce46ce0d772b7e5909f756fe2dfe",
}


def run(*argv: str) -> str:
    return subprocess.check_output(argv, cwd=ROOT, text=True).strip()


def require_blob(path: Path, expected: str) -> None:
    relative = path.relative_to(ROOT).as_posix()
    actual = run("git", "hash-object", relative)
    if actual != expected:
        raise SystemExit(f"refusing stale materialization for {relative}: {actual} != {expected}")


for path, expected in EXPECTED_BLOBS.items():
    require_blob(path, expected)
if not ATTACK.is_file():
    raise SystemExit("permanent final-name attack is missing")

writer = WRITER.read_text(encoding="utf-8")
helper_anchor = '''def _validate_existing_output(parent_fd: int, name: str) -> None:\n'''
helper = '''def _require_relative_name_matches_descriptor(\n    checkout_fd: int,\n    relative_path: str,\n    held_fd: int,\n) -> None:\n    """Re-bind the canonical credential name to the exact held published inode."""\n\n    current_fd = _open_relative_regular_file(checkout_fd, relative_path)\n    try:\n        held = os.fstat(held_fd)\n        current = os.fstat(current_fd)\n        if (\n            not stat.S_ISREG(held.st_mode)\n            or not stat.S_ISREG(current.st_mode)\n            or held.st_uid != os.geteuid()\n            or current.st_uid != os.geteuid()\n            or held.st_nlink != 1\n            or current.st_nlink != 1\n            or held.st_dev != current.st_dev\n            or held.st_ino != current.st_ino\n            or held.st_size != current.st_size\n        ):\n            raise ProvisionError(\n                "canonical private identity destination no longer names the sealed published inode"\n            )\n    finally:\n        os.close(current_fd)\n\n\n'''
if helper_anchor not in writer or "def _require_relative_name_matches_descriptor(" in writer:
    raise SystemExit("writer helper insertion contract drifted")
writer = writer.replace(helper_anchor, helper + helper_anchor, 1)

old_success = '''            _require_descriptor_payload(\n                final_fd,\n                payload,\n                "published private identity payload changed before durable success",\n            )\n        except Exception:\n            compromised = os.fstat(final_fd)\n            _unlink_owned_relative_inode_if_named(checkout_fd, destination_relative, compromised)\n            raise\n        os.fsync(checkout_fd)\n'''
new_success = '''            _require_descriptor_payload(\n                final_fd,\n                payload,\n                "published private identity payload changed before durable success",\n            )\n            os.fsync(checkout_fd)\n            _require_relative_name_matches_descriptor(\n                checkout_fd,\n                destination_relative,\n                final_fd,\n            )\n        except Exception:\n            compromised = os.fstat(final_fd)\n            _unlink_owned_relative_inode_if_named(checkout_fd, destination_relative, compromised)\n            raise\n'''
if old_success not in writer:
    raise SystemExit("writer durable-success seam drifted")
writer = writer.replace(old_success, new_success, 1)
WRITER.write_text(writer, encoding="utf-8")
writer_digest = hashlib.sha256(WRITER.read_bytes()).hexdigest()

shell = SHELL.read_text(encoding="utf-8")
old_digest = 'WRITER_SHA256="b697044a4de0cf1afcd40bc68722bbf4c316e59c6258cfd4de0497d3b4145276"'
new_digest = f'WRITER_SHA256="{writer_digest}"'
if shell.count(old_digest) != 1:
    raise SystemExit("privileged shell writer digest contract drifted")
SHELL.write_text(shell.replace(old_digest, new_digest, 1), encoding="utf-8")

swift = SWIFT.read_text(encoding="utf-8")
old_swift_digest = '#expect(shell.contains("WRITER_SHA256=\\"b697044a4de0cf1afcd40bc68722bbf4c316e59c6258cfd4de0497d3b4145276\\""))'
new_swift_digest = f'#expect(shell.contains("WRITER_SHA256=\\"{writer_digest}\\""))'
if swift.count(old_swift_digest) != 1:
    raise SystemExit("Swift writer digest source contract drifted")
swift = swift.replace(old_swift_digest, new_swift_digest, 1)
source_anchor = '        #expect(writer.contains("_unlink_owned_relative_inode_if_named"))\n'
if source_anchor not in swift:
    raise SystemExit("Swift publication source contract anchor drifted")
swift = swift.replace(
    source_anchor,
    source_anchor + '        #expect(writer.contains("_require_relative_name_matches_descriptor"))\n',
    1,
)
SWIFT.write_text(swift, encoding="utf-8")

workflow = WORKFLOW.read_text(encoding="utf-8")
path_anchor = "      - scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py\n"
if workflow.count(path_anchor) != 2:
    raise SystemExit("publication workflow path-filter contract drifted")
workflow = workflow.replace(
    path_anchor,
    path_anchor + "      - scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py\n",
)
compile_anchor = "          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py\n"
if workflow.count(compile_anchor) != 1:
    raise SystemExit("publication workflow compile contract drifted")
workflow = workflow.replace(
    compile_anchor,
    compile_anchor + "          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py\n",
    1,
)
run_anchor = "          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py\n"
if workflow.count(run_anchor) != 1:
    raise SystemExit("publication workflow execution contract drifted")
workflow = workflow.replace(
    run_anchor,
    run_anchor + "          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py\n",
    1,
)
WORKFLOW.write_text(workflow, encoding="utf-8")

# Focused construction validation before publishing any production bytes.
subprocess.run(["python3", "-m", "py_compile", str(WRITER), str(ATTACK)], cwd=ROOT, check=True)
subprocess.run(["python3", str(WRITER), "--self-test"], cwd=ROOT, check=True)
for test in (
    "scripts/ci/tests/test_capture_private_identity_publication_races.py",
    "scripts/ci/tests/test_capture_private_identity_same_inode_payload_current.py",
    "scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py",
    "scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py",
):
    subprocess.run(["python3", "-I", test], cwd=ROOT, check=True)
subprocess.run(["bash", "-n", str(SHELL)], cwd=ROOT, check=True)
subprocess.run(["git", "diff", "--check"], cwd=ROOT, check=True)

shell_after = SHELL.read_text(encoding="utf-8")
swift_after = SWIFT.read_text(encoding="utf-8")
if new_digest not in shell_after or writer_digest not in swift_after:
    raise SystemExit("writer digest was not carried through shell + package contract")

# Leave only durable product/regression bytes. The running workflow remains valid
# after these materializer paths are removed from the working tree.
SELF.unlink()
TEMP_WORKFLOW.unlink()
subprocess.run(
    [
        "git",
        "add",
        "Scripts/provision_capture_tuya_identity_writer.py",
        "Scripts/provision_capture_tuya_identity.sh",
        "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift",
        ".github/workflows/capture-private-identity-publication-races-redteam.yml",
        "scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py",
        str(SELF.relative_to(ROOT)),
        str(TEMP_WORKFLOW.relative_to(ROOT)),
    ],
    cwd=ROOT,
    check=True,
)
subprocess.run(["git", "diff", "--cached", "--check"], cwd=ROOT, check=True)
subprocess.run(["git", "config", "user.name", "nembra-sol-bot"], cwd=ROOT, check=True)
subprocess.run(["git", "config", "user.email", "nembra-sol-bot@users.noreply.github.com"], cwd=ROOT, check=True)
subprocess.run(
    ["git", "commit", "-m", "Bind private identity canonical destination name"],
    cwd=ROOT,
    check=True,
)
subprocess.run(
    ["git", "push", "origin", "HEAD:repair/v14-private-identity-final-name-binding-sol-20260811"],
    cwd=ROOT,
    check=True,
)
print(f"published writer sha256 {writer_digest}")
