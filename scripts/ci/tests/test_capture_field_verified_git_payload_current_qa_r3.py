#!/usr/bin/env python3
"""Independent R3 QA for #2937's materialized accepted-Git payload verifier.

Unlike the earlier QA, this fixture explicitly makes the read-only pack index
produced by git pack-objects owner-writable before corrupting its object-name
table. A pass therefore judges the materialized verifier instead of failing in
fixture setup.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import shlex
import stat
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
INSTALLER = ROOT / "scripts/field/install_one_time_capture.command"
GIT = "/usr/bin/git"
RELATIVE = "Scripts/bootstrap_capture_tuya_sdk.sh"


def git_blob_oid(payload: bytes) -> str:
    return hashlib.sha1(
        b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    ).hexdigest()


def git(repo: Path, *args: str, input_bytes: bytes | None = None) -> bytes:
    return subprocess.check_output([GIT, "-C", str(repo), *args], input=input_bytes)


def forge_single_blob_alias(repo: Path, accepted_blob_oid: str, attacker_payload: bytes) -> None:
    attacker_oid = git(repo, "hash-object", "-w", "--stdin", input_bytes=attacker_payload).decode().strip()
    pack_prefix = repo / ".git" / "objects" / "pack" / "pack"
    pack_hash = subprocess.check_output(
        [GIT, "-C", str(repo), "pack-objects", str(pack_prefix)],
        input=(attacker_oid + "\n").encode("ascii"),
    ).decode("ascii").strip()

    for oid in (attacker_oid, accepted_blob_oid):
        loose = repo / ".git" / "objects" / oid[:2] / oid[2:]
        if loose.exists():
            loose.unlink()

    index = repo / ".git" / "objects" / "pack" / f"pack-{pack_hash}.idx"
    original_mode = stat.S_IMODE(index.stat().st_mode)
    if original_mode & 0o222:
        raise AssertionError("fixture expected git pack index to begin read-only")
    index.chmod(0o600)
    data = bytearray(index.read_bytes())
    if data[:4] != b"\xfftOc" or struct.unpack(">I", data[4:8])[0] != 2:
        raise AssertionError("fixture requires a v2 Git pack index")
    fanout_offset = 8
    names_offset = fanout_offset + 256 * 4
    count = struct.unpack(">I", data[fanout_offset + 255 * 4 : fanout_offset + 256 * 4])[0]
    if count != 1:
        raise AssertionError("fixture pack must contain exactly one object")
    data[names_offset : names_offset + 20] = bytes.fromhex(accepted_blob_oid)
    first_byte = int(accepted_blob_oid[:2], 16)
    for value in range(256):
        struct.pack_into(">I", data, fanout_offset + value * 4, 0 if value < first_byte else 1)
    data[-20:] = hashlib.sha1(data[:-20]).digest()
    index.write_bytes(data)


def extract_verifier(installer: str) -> str:
    start = installer.index("read_verified_accepted_git_blob() {")
    end_marker = "\n}\n\nSOURCE_SHA="
    end = installer.index(end_marker, start) + 2
    return installer[start:end]


class CaptureFieldVerifiedGitPayloadCurrentQAR3(unittest.TestCase):
    def test_all_interpreter_bound_sources_use_verified_payload_boundary(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        self.assertIn("read_verified_accepted_git_blob() {", source)
        self.assertIn('read_verified_accepted_git_blob "$PRIVATE_DEVICE_RUNNER_RELATIVE" |', source)

        bash_start = source.index("run_accepted_source_bash() {")
        bash_end = source.index("\n}\n", bash_start) + 2
        bash_body = source[bash_start:bash_end]
        self.assertIn('read_verified_accepted_git_blob "$relative_path" |', bash_body)

        python_start = source.index("run_accepted_source_python() {")
        python_end = source.index("\n}\n", python_start) + 2
        python_body = source[python_start:python_end]
        self.assertIn('read_verified_accepted_git_blob "$relative_path" |', python_body)

        for forbidden in (
            'run_authority_git show "$SOURCE_SHA:$relative_path" |',
            'run_authority_git show "$SOURCE_SHA:scripts/ci/es80_signed_field_artifact_private_runner.py" |',
            '["/usr/bin/git", "show", f"{source_sha}:{relative_path}"]',
        ):
            self.assertNotIn(forbidden, source)

    def test_actual_verifier_is_bounded_and_buffers_before_emission(self) -> None:
        verifier = extract_verifier(INSTALLER.read_text(encoding="utf-8"))
        for token in (
            "limit = 2 * 1024 * 1024",
            "remaining = limit + 1 - len(payload)",
            "process.kill()",
            "source = bytes(payload)",
            'b"blob " + str(len(source)).encode("ascii") + b"\\0" + source',
            "hmac.compare_digest(actual_oid, expected_oid)",
            "sys.stdout.buffer.write(source)",
        ):
            self.assertIn(token, verifier)
        self.assertLess(
            verifier.index("hmac.compare_digest(actual_oid, expected_oid)"),
            verifier.index("sys.stdout.buffer.write(source)"),
            "verified payload must not emit any prefix before identity succeeds",
        )
        self.assertIn("subprocess.Popen(", verifier)
        self.assertNotIn("subprocess.check_output", verifier)

    def test_actual_materialized_verifier_rejects_forged_pack_alias_without_stdout(self) -> None:
        verifier = extract_verifier(INSTALLER.read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory(prefix="nembra-verified-git-payload-r3-") as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            subprocess.run([GIT, "init", "-q", str(repo)], check=True)
            subprocess.run([GIT, "-C", str(repo), "config", "user.email", "nembra@example.invalid"], check=True)
            subprocess.run([GIT, "-C", str(repo), "config", "user.name", "Nembra QA R3"], check=True)
            path = repo / RELATIVE
            path.parent.mkdir(parents=True)
            accepted_payload = b"#!/bin/bash\necho accepted\n"
            path.write_bytes(accepted_payload)
            subprocess.run([GIT, "-C", str(repo), "add", RELATIVE], check=True)
            subprocess.run([GIT, "-C", str(repo), "commit", "-qm", "accepted"], check=True)
            source_sha = git(repo, "rev-parse", "HEAD").decode().strip()
            accepted_oid = git(repo, "rev-parse", f"HEAD:{RELATIVE}").decode().strip()
            self.assertEqual(git_blob_oid(accepted_payload), accepted_oid)

            attacker_payload = b"#!/bin/bash\necho attacker-must-not-emit\n"
            forge_single_blob_alias(repo, accepted_oid, attacker_payload)
            self.assertEqual(git(repo, "cat-file", "blob", accepted_oid), attacker_payload)
            self.assertNotEqual(git_blob_oid(attacker_payload), accepted_oid)

            harness = Path(directory) / "verify.sh"
            harness.write_text(
                "#!/bin/bash\nset -euo pipefail\n"
                "die() { printf '%s\\n' \"$*\" >&2; return 1; }\n"
                f"ROOT={shlex.quote(str(repo))}\n"
                f"AUTHORITY_GIT_DIR={shlex.quote(str(repo / '.git'))}\n"
                f"SOURCE_SHA={shlex.quote(source_sha)}\n"
                + verifier
                + "\nread_verified_accepted_git_blob "
                + shlex.quote(RELATIVE)
                + "\n",
                encoding="utf-8",
            )
            result = subprocess.run(
                ["/bin/bash", str(harness)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0, result.stderr.decode("utf-8", errors="replace"))
            self.assertEqual(
                result.stdout,
                b"",
                "forged Git payload emitted interpreter-visible bytes before identity rejection",
            )
            self.assertIn(b"does not match the accepted tree identity", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
