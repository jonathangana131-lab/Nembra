#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
GIT = "/usr/bin/git"
TRANSPORT = ROOT / "scripts/field/run_apple_signing_context_preflight.command"
WRAPPER_PATH = "scripts/field/run_apple_signing_context_preflight.command"
ORACLE_PATH = "scripts/ci/tests/test_capture_signed_app_field_uid_apple_development_signing.py"
SEALER_PATH = "scripts/ci/capture_apple_signing_preflight_receipt_seal.py"


class VerifiedObjectChainTests(unittest.TestCase):
    def raw_git(
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

    def write(self, repo: Path, path: str, payload: bytes) -> None:
        target = repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)

    def resolver(self) -> str:
        source = TRANSPORT.read_text(encoding="utf-8")
        start_marker = "OBJECT_RESOLVER=\"$(/bin/cat <<'PY'\n"
        end_marker = "\nPY\n)\""
        start = source.index(start_marker) + len(start_marker)
        end = source.index(end_marker, start)
        return source[start:end]

    def fixture(self, repo: Path) -> tuple[str, str, list[str]]:
        repo.mkdir()
        self.raw_git(repo, "init", "-q")
        self.raw_git(repo, "config", "user.email", "nembra@example.invalid")
        self.raw_git(repo, "config", "user.name", "Nembra Repair Validation")
        accepted = [
            b"#!/bin/bash\necho wrapper\n",
            b'print("accepted oracle")\n',
            b'print("accepted sealer")\n',
        ]
        paths = (WRAPPER_PATH, ORACLE_PATH, SEALER_PATH)
        for path, payload in zip(paths, accepted):
            self.write(repo, path, payload)
        self.raw_git(repo, "add", ".")
        self.raw_git(repo, "commit", "-qm", "accepted fixture")
        accepted_commit = self.raw_git(repo, "rev-parse", "HEAD").stdout.decode().strip()
        accepted_blobs = [
            self.raw_git(repo, "rev-parse", f"HEAD:{path}").stdout.decode().strip()
            for path in paths
        ]

        self.write(repo, ORACLE_PATH, b'print("ATTACKER ORACLE")\n')
        self.write(repo, SEALER_PATH, b'print("ATTACKER SEALER")\n')
        self.raw_git(repo, "add", ORACLE_PATH, SEALER_PATH)
        self.raw_git(repo, "commit", "-qm", "attacker fixture")
        attacker_commit = self.raw_git(repo, "rev-parse", "HEAD").stdout.decode().strip()
        self.assertEqual(
            self.raw_git(repo, "rev-parse", f"HEAD:{WRAPPER_PATH}").stdout.decode().strip(),
            accepted_blobs[0],
        )
        return accepted_commit, attacker_commit, accepted_blobs

    def forge(self, repo: Path, source_oid: str, alias_oid: str) -> Path:
        prefix = repo / ".git" / "objects" / "pack" / "pack"
        pack_hash = self.raw_git(
            repo,
            "pack-objects",
            str(prefix),
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
        fanout = 8
        names = fanout + 256 * 4
        self.assertEqual(
            struct.unpack(">I", data[fanout + 255 * 4 : fanout + 256 * 4])[0],
            1,
        )
        data[names : names + 20] = bytes.fromhex(alias_oid)
        first = int(alias_oid[:2], 16)
        for position in range(256):
            struct.pack_into(
                ">I",
                data,
                fanout + position * 4,
                0 if position < first else 1,
            )
        data[-20:] = hashlib.sha1(data[:-20]).digest()
        index.chmod(index.stat().st_mode | 0o200)
        index.write_bytes(data)
        return index

    def run_resolver(self, repo: Path, source_sha: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "/usr/bin/python3",
                "-B",
                "-I",
                "-c",
                self.resolver(),
                str(repo / ".git"),
                source_sha,
                WRAPPER_PATH,
                ORACLE_PATH,
                SEALER_PATH,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )

    def test_normal_chain_resolves_exact_accepted_blobs(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-chain-green-") as directory:
            repo = Path(directory) / "repo"
            accepted, _, accepted_blobs = self.fixture(repo)
            self.raw_git(repo, "reset", "--hard", accepted)
            result = self.run_resolver(repo, accepted)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip().split("\t"), accepted_blobs)

    def test_corrupt_accepted_commit_alias_is_rejected_before_helper_resolution(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-chain-red-") as directory:
            repo = Path(directory) / "repo"
            accepted, attacker, _ = self.fixture(repo)
            index = self.forge(repo, attacker, accepted)
            (repo / ".git" / "HEAD").write_text(accepted + "\n", encoding="ascii")

            self.assertEqual(
                self.raw_git(repo, "rev-parse", "HEAD").stdout.decode().strip(),
                accepted,
            )
            self.assertEqual(
                self.raw_git(repo, "status", "--porcelain=v1", "--untracked-files=all").stdout,
                b"",
            )

            result = self.run_resolver(repo, accepted)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "accepted Git object lookup returned bytes outside accepted identity",
                result.stderr,
            )
            verify = self.raw_git(repo, "verify-pack", "-v", str(index), check=False)
            self.assertNotEqual(verify.returncode, 0)

    def test_transport_uses_verified_commit_tree_chain_not_path_rev_parse_authority(self) -> None:
        source = TRANSPORT.read_text(encoding="utf-8")
        self.assertIn(
            'commit_payload = capture("commit", source_sha, MAX_COMMIT_BYTES)',
            source,
        )
        self.assertIn("actual = object_oid(object_type, payload)", source)
        self.assertIn("root_tree_oid = commit_tree(commit_payload)", source)
        self.assertIn(
            "resolved = [resolve_path(root_tree_oid, path) for path in paths]",
            source,
        )
        self.assertNotIn('rev-parse "$SOURCE_SHA:$SCRIPT_PATH"', source)
        self.assertNotIn('rev-parse "$SOURCE_SHA:$ORACLE_PATH"', source)
        self.assertNotIn('rev-parse "$SOURCE_SHA:$SEALER_PATH"', source)
        self.assertIn('materialize_blob "$ORACLE_BLOB" "$ORACLE_EXEC"', source)
        self.assertIn('materialize_blob "$SEALER_BLOB" "$SEALER_EXEC"', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
