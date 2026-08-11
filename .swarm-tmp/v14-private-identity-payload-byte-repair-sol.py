#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib
import os
import re
import subprocess

PARENT = "cb72a47ee2489235febd40ac440bc9f8462ba432"
DIAGNOSTIC = "11e794ba6c7050c1e4d70342c68aab5f1896bc10"


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def output(*args: str) -> bytes:
    return subprocess.check_output(args)


writer_path = Path("Scripts/provision_capture_tuya_identity_writer.py")
writer = writer_path.read_text(encoding="utf-8")

old_import = "import ctypes\nimport os\n"
new_import = "import ctypes\nimport hmac\nimport os\n"
if writer.count(old_import) != 1:
    raise SystemExit(f"expected one ctypes/os import seam, found {writer.count(old_import)}")
writer = writer.replace(old_import, new_import, 1)

old_final = '''        final_fd = _open_relative_regular_file(checkout_fd, destination_relative)
        final = os.fstat(final_fd)
        if (
            not stat.S_ISREG(final.st_mode)
            or final.st_uid != os.geteuid()
            or final.st_nlink != 1
            or final.st_size != len(payload)
            or final.st_dev != sealed.st_dev
            or final.st_ino != sealed.st_ino
        ):
            raise ProvisionError("published private identity output is not the sealed staging inode")
        os.fchmod(final_fd, 0o600)
        os.fsync(final_fd)
        os.fsync(checkout_fd)
    except Exception:
        _unlink_owned_inode_if_named(checkout_fd, temporary_name, sealed)
        raise
'''
new_final = '''        final_fd = _open_relative_regular_file(checkout_fd, destination_relative)
        final = os.fstat(final_fd)
        if (
            not stat.S_ISREG(final.st_mode)
            or final.st_uid != os.geteuid()
            or final.st_nlink != 1
            or final.st_size != len(payload)
            or final.st_dev != sealed.st_dev
            or final.st_ino != sealed.st_ino
        ):
            raise ProvisionError("published private identity output is not the sealed staging inode")

        os.fchmod(final_fd, 0o600)
        os.fsync(final_fd)
        before_read = os.fstat(final_fd)
        os.lseek(final_fd, 0, os.SEEK_SET)
        published = bytearray()
        remaining = len(payload) + 1
        while remaining > 0:
            chunk = os.read(final_fd, min(65536, remaining))
            if not chunk:
                break
            published.extend(chunk)
            remaining -= len(chunk)
        after_read = os.fstat(final_fd)
        before_identity = (
            before_read.st_dev,
            before_read.st_ino,
            before_read.st_mode,
            before_read.st_uid,
            before_read.st_gid,
            before_read.st_nlink,
            before_read.st_size,
            before_read.st_mtime_ns,
            before_read.st_ctime_ns,
        )
        after_identity = (
            after_read.st_dev,
            after_read.st_ino,
            after_read.st_mode,
            after_read.st_uid,
            after_read.st_gid,
            after_read.st_nlink,
            after_read.st_size,
            after_read.st_mtime_ns,
            after_read.st_ctime_ns,
        )
        if before_identity != after_identity or not hmac.compare_digest(bytes(published), payload):
            raise ProvisionError("published private identity payload changed during final custody verification")
        os.fsync(checkout_fd)
    except Exception:
        _unlink_owned_inode_if_named(destination_parent_fd, final_name, sealed)
        _unlink_owned_inode_if_named(checkout_fd, temporary_name, sealed)
        raise
'''
if writer.count(old_final) != 1:
    raise SystemExit(f"expected one final-custody seam, found {writer.count(old_final)}")
writer = writer.replace(old_final, new_final, 1)

old_self_test = "        root = Path(temporary)\n"
new_self_test = "        root = Path(os.path.realpath(temporary))\n"
if writer.count(old_self_test) != 1:
    raise SystemExit(f"expected one raw TemporaryDirectory root, found {writer.count(old_self_test)}")
writer = writer.replace(old_self_test, new_self_test, 1)
writer_path.write_text(writer, encoding="utf-8")

run("git", "fetch", "--no-tags", "origin", DIAGNOSTIC, "--depth=2")
actual_parent = output("git", "rev-parse", f"{DIAGNOSTIC}^").decode().strip()
if actual_parent != PARENT:
    raise SystemExit(f"diagnostic parent drifted: {actual_parent}")
publication_test_path = Path("scripts/ci/tests/test_capture_private_identity_publication_races.py")
publication_test_path.write_bytes(output("git", "show", f"{DIAGNOSTIC}:{publication_test_path.as_posix()}"))

writer_digest = hashlib.sha256(writer_path.read_bytes()).hexdigest()
if len(writer_digest) != 64:
    raise SystemExit("writer digest was not canonical SHA-256")

shell_path = Path("Scripts/provision_capture_tuya_identity.sh")
shell = shell_path.read_text(encoding="utf-8")
shell, count = re.subn(r'WRITER_SHA256="[0-9a-f]{64}"', f'WRITER_SHA256="{writer_digest}"', shell, count=1)
if count != 1:
    raise SystemExit(f"expected one shell writer digest pin, replaced {count}")
shell_path.write_text(shell, encoding="utf-8")

swift_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift")
source = swift_path.read_text(encoding="utf-8")
old_digest = '#expect(shell.contains("WRITER_SHA256=\\"920e4c416fdf71909bdafecf6e69ed8b76986b87462efee979fc1fe01106be34\\""))'
new_digest = f'#expect(shell.contains("WRITER_SHA256=\\"{writer_digest}\\""))'
if source.count(old_digest) != 1:
    raise SystemExit(f"expected one stale Swift digest assertion, found {source.count(old_digest)}")
source = source.replace(old_digest, new_digest, 1)

old_markers = '''        #expect(writer.contains("dir_fd=parent_fd"))
        #expect(writer.contains("src_dir_fd=parent_fd"))
        #expect(writer.contains("dst_dir_fd=parent_fd"))'''
new_markers = '''        #expect(writer.contains("_require_sealed_staging_name(checkout_fd, source_name, sealed)"))
        #expect(writer.contains("_secure_replace_beneath(checkout_fd, temporary_name, destination_relative, sealed)"))
        #expect(writer.contains("renameatx_np"))
        #expect(writer.contains("_DARWIN_RENAME_NOFOLLOW_ANY | _DARWIN_RENAME_RESOLVE_BENEATH"))
        #expect(writer.contains("_unlink_owned_inode_if_named(destination_parent_fd, final_name, sealed)"))
        #expect(writer.contains("hmac.compare_digest(bytes(published), payload)"))
        #expect(!writer.contains("src_dir_fd=parent_fd"))
        #expect(!writer.contains("dst_dir_fd=parent_fd"))'''
if source.count(old_markers) != 1:
    raise SystemExit(f"expected one retired parent-local source marker block, found {source.count(old_markers)}")
source = source.replace(old_markers, new_markers, 1)
swift_path.write_text(source, encoding="utf-8")

run("python3", "-m", "py_compile", str(writer_path), str(publication_test_path))
run("python3", "-I", str(writer_path), "--self-test")
run("python3", "-I", str(publication_test_path))
run("bash", "-n", str(shell_path))

if f'WRITER_SHA256="{writer_digest}"' not in shell_path.read_text(encoding="utf-8"):
    raise SystemExit("shell writer digest did not bind final bytes")
final_swift = swift_path.read_text(encoding="utf-8")
if f'WRITER_SHA256=\\"{writer_digest}\\"' not in final_swift:
    raise SystemExit("Swift source contract did not bind final writer digest")

run("git", "diff", "--check")
expected = sorted([
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift",
    "Scripts/provision_capture_tuya_identity.sh",
    "Scripts/provision_capture_tuya_identity_writer.py",
    "scripts/ci/tests/test_capture_private_identity_publication_races.py",
])
actual = sorted(output("git", "diff", "--name-only").decode().splitlines())
if actual != expected:
    raise SystemExit(f"unexpected repair paths: {actual!r}")

print(f"FINAL_WRITER_SHA256={writer_digest}")
