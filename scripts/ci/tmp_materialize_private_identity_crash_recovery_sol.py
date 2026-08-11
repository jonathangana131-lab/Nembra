#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
SHELL = ROOT / "Scripts/provision_capture_tuya_identity.sh"
SWIFT = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift"
CRASH_TEST = ROOT / "scripts/ci/tests/test_capture_private_identity_crash_residue.py"
TEMP_SCRIPT = ROOT / "scripts/ci/tmp_materialize_private_identity_crash_recovery_sol.py"
TEMP_WORKFLOW = ROOT / ".github/workflows/tmp-v14-private-identity-crash-recovery-sol.yml"
REDTEAM_HEAD = "6ef21ee7b7ca44e26ca8e478f41b14505fe90d8b"
OLD_WRITER_SHA256 = "b697044a4de0cf1afcd40bc68722bbf4c316e59c6258cfd4de0497d3b4145276"
EXPECTED_BLOBS = {
    WRITER: "ed473ca81fed3a729c4618c65c2fcd0d272987a5",
    SHELL: "e8b2da09350ffb1e53ceb13bd69e3dcea33a7daf",
    SWIFT: "43d8c83d543efdfe7aafc219e6eb1f79d091cb4a",
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
writer = replace_once(
    writer,
    '_DARWIN_RENAME_RESOLVE_BENEATH = 0x00000020\n',
    '_DARWIN_RENAME_RESOLVE_BENEATH = 0x00000020\n_PRIVATE_STAGE_PREFIX = ".nembra-private-stage-"\n',
    "private-stage prefix",
)
recovery = '''\n\ndef _reserved_staging_names(checkout_fd: int) -> list[str]:\n    try:\n        names = os.listdir(checkout_fd)\n    except OSError as exc:\n        raise ProvisionError("could not inspect reserved private identity staging namespace") from exc\n    result: list[str] = []\n    for name in names:\n        if not isinstance(name, str):\n            raise ProvisionError("reserved private identity staging namespace returned a non-text name")\n        if name.startswith(_PRIVATE_STAGE_PREFIX):\n            result.append(name)\n    return sorted(result)\n\n\ndef _recover_private_staging_residue(checkout_fd: int) -> None:\n    removed_any = False\n    for name in _reserved_staging_names(checkout_fd):\n        descriptor = -1\n        try:\n            try:\n                named = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)\n            except OSError as exc:\n                raise ProvisionError("reserved private identity staging entry changed during recovery") from exc\n            if (\n                not stat.S_ISREG(named.st_mode)\n                or named.st_uid != os.geteuid()\n                or named.st_nlink != 1\n                or stat.S_IMODE(named.st_mode) != 0o600\n            ):\n                raise ProvisionError(\n                    "reserved private identity staging entry is not one recoverable writer-owned 0600 regular file"\n                )\n            descriptor = os.open(\n                name,\n                os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW,\n                dir_fd=checkout_fd,\n            )\n            held = os.fstat(descriptor)\n            rebound = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)\n            if (\n                not stat.S_ISREG(held.st_mode)\n                or held.st_uid != os.geteuid()\n                or held.st_nlink != 1\n                or stat.S_IMODE(held.st_mode) != 0o600\n                or held.st_dev != named.st_dev\n                or held.st_ino != named.st_ino\n                or rebound.st_dev != held.st_dev\n                or rebound.st_ino != held.st_ino\n                or rebound.st_nlink != 1\n            ):\n                raise ProvisionError("reserved private identity staging entry lost exact inode custody during recovery")\n            os.unlink(name, dir_fd=checkout_fd)\n            removed = os.fstat(descriptor)\n            if removed.st_dev != held.st_dev or removed.st_ino != held.st_ino or removed.st_nlink != 0:\n                raise ProvisionError("reserved private identity staging unlink did not retire the admitted inode")\n            removed_any = True\n        finally:\n            if descriptor >= 0:\n                os.close(descriptor)\n    if removed_any:\n        os.fsync(checkout_fd)\n    if _reserved_staging_names(checkout_fd):\n        raise ProvisionError("reserved private identity staging namespace is not clean after recovery")\n'''
writer = replace_once(
    writer,
    '\n\nclass _SealedStaging:\n',
    recovery + '\n\nclass _SealedStaging:\n',
    "recovery function insertion",
)
writer = replace_once(
    writer,
    '    temporary_name = f".nembra-private-stage-{os.getpid()}-{secrets.token_hex(12)}"\n',
    '    temporary_name = f"{_PRIVATE_STAGE_PREFIX}{os.getpid()}-{secrets.token_hex(12)}"\n',
    "reserved stage name",
)
writer = replace_once(
    writer,
    '        _require_checkout_path_identity(checkout_fd, checkout_root)\n        local_secrets_fd = _ensure_private_directory(checkout_fd, "LocalSecrets")\n',
    '        _require_checkout_path_identity(checkout_fd, checkout_root)\n        _recover_private_staging_residue(checkout_fd)\n        _require_checkout_path_identity(checkout_fd, checkout_root)\n        local_secrets_fd = _ensure_private_directory(checkout_fd, "LocalSecrets")\n',
    "provision recovery admission",
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
    '        #expect(writer.contains("_recover_private_staging_residue"))\n'
    '        #expect(writer.contains("_PRIVATE_STAGE_PREFIX"))\n'
    '        #expect(writer.contains("os.listdir(checkout_fd)"))\n'
    '        #expect(writer.contains("os.unlink(name, dir_fd=checkout_fd)"))\n',
    "Swift crash-recovery source contract",
)
SWIFT.write_text(swift, encoding="utf-8")

crash_bytes = subprocess.check_output(
    ["git", "show", f"{REDTEAM_HEAD}:scripts/ci/tests/test_capture_private_identity_crash_residue.py"],
    cwd=ROOT,
)
crash_source = crash_bytes.decode("utf-8")
crash_source = replace_once(
    crash_source,
    '                    def hard_exit_after_seal(_root_fd: int, _src: str, _dst: str) -> None:\n',
    '                    def hard_exit_after_seal(_root_fd: int, _src: str, _dst: str, _sealed) -> None:\n',
    "current four-argument publication seam adapter",
)
CRASH_TEST.write_text(crash_source, encoding="utf-8")

TEMP_SCRIPT.unlink()
TEMP_WORKFLOW.unlink()

print(f"materialized crash-recovery writer digest {new_writer_sha256}")