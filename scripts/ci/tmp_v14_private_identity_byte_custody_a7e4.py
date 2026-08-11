#!/usr/bin/env python3
"""Temporary exact-head materializer for Capture private identity byte custody.

This file is removed by the materializer commit after the focused regression
suite passes. It exists only because this execution environment cannot clone
the repository directly.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import textwrap

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "Scripts" / "provision_capture_tuya_identity_writer.py"
RACES = ROOT / "scripts" / "ci" / "tests" / "test_capture_private_identity_publication_races.py"
SELF = Path(__file__).resolve().relative_to(ROOT)
OLD_DIGEST = "920e4c416fdf71909bdafecf6e69ed8b76986b87462efee979fc1fe01106be34"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one exact source anchor, found {count}")
    return text.replace(old, new, 1)


def patch_writer() -> None:
    text = WRITER.read_text()

    if "def _require_staging_name_matches_fd(" not in text:
        marker = "\ndef _validate_existing_output(parent_fd: int, name: str) -> None:\n"
        helpers = textwrap.dedent(
            '''
            def _require_staging_name_matches_fd(
                checkout_fd: int,
                temporary_name: str,
                sealed: os.stat_result,
            ) -> None:
                try:
                    named = os.stat(temporary_name, dir_fd=checkout_fd, follow_symlinks=False)
                except OSError as exc:
                    raise ProvisionError("private identity staging name changed before publication") from exc
                if (
                    not stat.S_ISREG(named.st_mode)
                    or named.st_uid != os.geteuid()
                    or named.st_nlink != 1
                    or named.st_size != sealed.st_size
                    or named.st_dev != sealed.st_dev
                    or named.st_ino != sealed.st_ino
                ):
                    raise ProvisionError("private identity staging name no longer names the sealed staging inode")


            def _remove_final_if_same_inode_beneath(
                checkout_fd: int,
                relative_path: str,
                expected_dev: int,
                expected_ino: int,
            ) -> None:
                components = _relative_components(relative_path)
                parent_fd = os.dup(checkout_fd)
                try:
                    for component in components[:-1]:
                        next_fd = os.open(component, _directory_flags(), dir_fd=parent_fd)
                        os.close(parent_fd)
                        parent_fd = next_fd
                    try:
                        named = os.stat(components[-1], dir_fd=parent_fd, follow_symlinks=False)
                    except FileNotFoundError:
                        return
                    if (
                        stat.S_ISREG(named.st_mode)
                        and named.st_uid == os.geteuid()
                        and named.st_nlink == 1
                        and named.st_dev == expected_dev
                        and named.st_ino == expected_ino
                    ):
                        os.unlink(components[-1], dir_fd=parent_fd)
                        os.fsync(parent_fd)
                except OSError:
                    return
                finally:
                    os.close(parent_fd)


            def _publication_metadata_signature(metadata: os.stat_result) -> tuple[int, ...]:
                return (
                    stat.S_IFMT(metadata.st_mode),
                    metadata.st_uid,
                    metadata.st_nlink,
                    metadata.st_size,
                    metadata.st_dev,
                    metadata.st_ino,
                    metadata.st_mtime_ns,
                    metadata.st_ctime_ns,
                )


            def _read_exact_fd_payload(descriptor: int, expected_size: int) -> bytes:
                os.lseek(descriptor, 0, os.SEEK_SET)
                result = bytearray()
                while len(result) <= expected_size:
                    chunk = os.read(descriptor, min(65536, expected_size + 1 - len(result)))
                    if not chunk:
                        break
                    result.extend(chunk)
                return bytes(result)
            '''
        )
        text = replace_once(text, marker, "\n" + helpers + marker, "writer helper insertion")

    if "_require_staging_name_matches_fd(checkout_fd, temporary_name, sealed)" not in text:
        old = '''        _secure_replace_beneath(checkout_fd, temporary_name, destination_relative)\n\n        final_fd = _open_relative_regular_file(checkout_fd, destination_relative)\n'''
        new = '''        _require_staging_name_matches_fd(checkout_fd, temporary_name, sealed)\n        _secure_replace_beneath(checkout_fd, temporary_name, destination_relative)\n\n        final_fd = _open_relative_regular_file(checkout_fd, destination_relative)\n'''
        text = replace_once(text, old, new, "staging-name publication fence")

    if "published_payload = _read_exact_fd_payload(final_fd, len(payload))" not in text:
        old = '''        final = os.fstat(final_fd)\n        if (\n            not stat.S_ISREG(final.st_mode)\n            or final.st_uid != os.geteuid()\n            or final.st_nlink != 1\n            or final.st_size != len(payload)\n            or final.st_dev != sealed.st_dev\n            or final.st_ino != sealed.st_ino\n        ):\n            raise ProvisionError("published private identity output is not the sealed staging inode")\n        os.fchmod(final_fd, 0o600)\n'''
        new = '''        final = os.fstat(final_fd)\n        if (\n            not stat.S_ISREG(final.st_mode)\n            or final.st_uid != os.geteuid()\n            or final.st_nlink != 1\n            or final.st_size != len(payload)\n            or final.st_dev != sealed.st_dev\n            or final.st_ino != sealed.st_ino\n        ):\n            _remove_final_if_same_inode_beneath(\n                checkout_fd,\n                destination_relative,\n                final.st_dev,\n                final.st_ino,\n            )\n            raise ProvisionError("published private identity output is not the sealed staging inode")\n\n        before_read = _publication_metadata_signature(final)\n        published_payload = _read_exact_fd_payload(final_fd, len(payload))\n        after_read_metadata = os.fstat(final_fd)\n        after_read = _publication_metadata_signature(after_read_metadata)\n        if before_read != after_read or published_payload != payload:\n            _remove_final_if_same_inode_beneath(\n                checkout_fd,\n                destination_relative,\n                after_read_metadata.st_dev,\n                after_read_metadata.st_ino,\n            )\n            raise ProvisionError("published private identity output changed or does not match accepted bytes")\n        os.fchmod(final_fd, 0o600)\n'''
        text = replace_once(text, old, new, "published byte authority block")

    WRITER.write_text(text)


def patch_red_team_test() -> None:
    text = RACES.read_text()
    if "def test_same_staging_inode_payload_mutation_cannot_be_accepted" in text:
        return

    marker = "    def test_detached_private_directory_cannot_receive_or_stage_credential_identity(self) -> None:\n"
    regression = textwrap.dedent(
        '''
            def test_same_staging_inode_payload_mutation_cannot_be_accepted(self) -> None:
                writer = load_writer()
                payload = b"accepted-private-identity-payload"
                attacker_payload = b"Y" * len(payload)

                with tempfile.TemporaryDirectory(prefix="nembra-private-same-inode-race-") as temporary:
                    checkout = Path(temporary) / "repo"
                    parent = checkout / "private"
                    parent.mkdir(parents=True, mode=0o700)
                    checkout_fd = os.open(checkout, writer._directory_flags())
                    parent_fd = os.open(parent, writer._directory_flags())
                    original_publish = writer._secure_replace_beneath
                    attacked = False

                    def adversarial_publish(root_fd: int, src: str, dst: str) -> None:
                        nonlocal attacked
                        if not attacked:
                            attacked = True
                            mutation_fd = os.open(
                                src,
                                os.O_WRONLY | os.O_CLOEXEC | os.O_NOFOLLOW,
                                dir_fd=root_fd,
                            )
                            try:
                                os.lseek(mutation_fd, 0, os.SEEK_SET)
                                view = memoryview(attacker_payload)
                                offset = 0
                                while offset < len(view):
                                    written = os.write(mutation_fd, view[offset:])
                                    self.assertGreater(written, 0)
                                    offset += written
                                os.fsync(mutation_fd)
                            finally:
                                os.close(mutation_fd)
                        original_publish(root_fd, src, dst)

                    writer._secure_replace_beneath = adversarial_publish
                    rejected = False
                    try:
                        try:
                            writer._write_staged(
                                checkout_fd,
                                parent_fd,
                                "identity.swift",
                                "private/identity.swift",
                                payload,
                            )
                        except (writer.ProvisionError, OSError):
                            rejected = True
                    finally:
                        writer._secure_replace_beneath = original_publish
                        os.close(parent_fd)
                        os.close(checkout_fd)

                    final = parent / "identity.swift"
                    final_bytes = final.read_bytes() if final.exists() else None
                    self.assertTrue(attacked, "diagnostic never reached the sealed-inode publication boundary")
                    self.assertTrue(
                        rejected or final_bytes == payload,
                        "writer reported success after the sealed staging inode payload changed in place",
                    )
                    self.assertNotEqual(
                        final_bytes,
                        attacker_payload,
                        "same-inode attacker bytes were accepted as the published private identity",
                    )

        '''
    )
    # textwrap removes the class indentation; restore exactly four spaces.
    regression = "".join(("    " + line if line.strip() else line) for line in regression.splitlines(keepends=True))
    text = replace_once(text, marker, regression + marker, "same-inode red-team insertion")
    RACES.write_text(text)


def repin_writer_digest() -> None:
    digest = hashlib.sha256(WRITER.read_bytes()).hexdigest()
    result = subprocess.run(
        ["git", "grep", "-l", "-F", OLD_DIGEST, "--", "."],
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        text=True,
    )
    paths = [Path(line) for line in result.stdout.splitlines() if line]
    functional = [path for path in paths if path != SELF]
    if not functional:
        raise SystemExit("old writer digest is no longer pinned by tracked functional source")
    print(f"new writer digest: {digest}")
    print("re-pinning exact digest in:")
    for relative in functional:
        print(f"  {relative}")
        path = ROOT / relative
        text = path.read_text()
        if OLD_DIGEST not in text:
            raise SystemExit(f"digest grep/read mismatch for {relative}")
        path.write_text(text.replace(OLD_DIGEST, digest))


def main() -> None:
    patch_writer()
    patch_red_team_test()
    repin_writer_digest()


if __name__ == "__main__":
    main()
