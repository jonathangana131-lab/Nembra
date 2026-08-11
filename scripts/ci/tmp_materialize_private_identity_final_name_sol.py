#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
SHELL = ROOT / "Scripts/provision_capture_tuya_identity.sh"
SWIFT = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift"
FINAL_NAME_TEST = ROOT / "scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py"
TEMP_SCRIPT = ROOT / "scripts/ci/tmp_materialize_private_identity_final_name_sol.py"
TEMP_WORKFLOW = ROOT / ".github/workflows/tmp-v14-private-identity-final-name-sol.yml"
REDTEAM_HEAD = "692bed2ad27f154b782eb04f980b3ad0c1bbbee9"
OLD_WRITER_SHA256 = "213d75a80c87a887737296db93dcceefdfe73ab1218a0916128823ed17cbe771"
EXPECTED_BLOBS = {
    WRITER: "86fad360144fed7b26937476f6cd8f4caeba9831",
    SHELL: "5162c6e35297fcf2315dc22c8a296828d7216be5",
    SWIFT: "af4c47324260727a9788b8ac5b637883fd4b2dea",
}


def git_blob(path: Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    return source.replace(old, new, 1)


for path, expected in EXPECTED_BLOBS.items():
    actual = git_blob(path)
    if actual != expected:
        raise SystemExit(f"stale materializer for {path.relative_to(ROOT)}: {actual} != {expected}")

writer = WRITER.read_text(encoding="utf-8")
helper = '''\n\ndef _require_final_relative_name_binding(\n    checkout_fd: int,\n    relative_path: str,\n    sealed: os.stat_result,\n    payload: bytes,\n) -> None:\n    \"\"\"Re-bind the canonical credential name to the accepted inode at success.\"\"\"\n    rebound_fd = -1\n    try:\n        rebound_fd = _open_relative_regular_file(checkout_fd, relative_path)\n        rebound = os.fstat(rebound_fd)\n        if (\n            not stat.S_ISREG(rebound.st_mode)\n            or rebound.st_uid != os.geteuid()\n            or rebound.st_nlink != 1\n            or stat.S_IMODE(rebound.st_mode) != 0o600\n            or rebound.st_size != len(payload)\n            or rebound.st_dev != sealed.st_dev\n            or rebound.st_ino != sealed.st_ino\n        ):\n            raise ProvisionError(\n                \"private identity canonical destination no longer names the accepted sealed inode\"\n            )\n        _require_descriptor_payload(\n            rebound_fd,\n            payload,\n            \"private identity canonical destination failed final payload binding\",\n        )\n    finally:\n        if rebound_fd >= 0:\n            os.close(rebound_fd)\n'''
writer = replace_once(
    writer,
    '\n\nclass _SealedStaging:\n',
    helper + '\n\nclass _SealedStaging:\n',
    "final-name helper insertion",
)
writer = replace_once(
    writer,
    '        os.fsync(checkout_fd)\n    except Exception:\n',
    '        os.fsync(checkout_fd)\n'
    '        try:\n'
    '            _require_final_relative_name_binding(\n'
    '                checkout_fd,\n'
    '                destination_relative,\n'
    '                sealed,\n'
    '                payload,\n'
    '            )\n'
    '        except Exception:\n'
    '            _unlink_owned_relative_inode_if_named(checkout_fd, destination_relative, sealed)\n'
    '            os.fsync(checkout_fd)\n'
    '            raise\n'
    '    except Exception:\n',
    "final success-boundary rebind",
)
WRITER.write_text(writer, encoding="utf-8")
new_writer_sha256 = hashlib.sha256(WRITER.read_bytes()).hexdigest()
if new_writer_sha256 == OLD_WRITER_SHA256:
    raise SystemExit("writer digest unexpectedly unchanged")

shell = SHELL.read_text(encoding="utf-8")
shell = replace_once(shell, OLD_WRITER_SHA256, new_writer_sha256, "shell writer digest")
SHELL.write_text(shell, encoding="utf-8")

swift = SWIFT.read_text(encoding="utf-8")
swift = replace_once(swift, OLD_WRITER_SHA256, new_writer_sha256, "Swift writer digest")
swift = replace_once(
    swift,
    '        #expect(writer.contains("_unlink_owned_relative_inode_if_named"))\n',
    '        #expect(writer.contains("_unlink_owned_relative_inode_if_named"))\n'
    '        #expect(writer.contains("_require_final_relative_name_binding"))\n'
    '        #expect(writer.contains("private identity canonical destination no longer names the accepted sealed inode"))\n',
    "Swift final-name source contract",
)
SWIFT.write_text(swift, encoding="utf-8")

final_name_bytes = subprocess.check_output(
    ["git", "show", f"{REDTEAM_HEAD}:scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py"],
    cwd=ROOT,
)
FINAL_NAME_TEST.write_bytes(final_name_bytes)

TEMP_SCRIPT.unlink()
TEMP_WORKFLOW.unlink()
print(f"materialized final-name binding writer digest {new_writer_sha256}")
