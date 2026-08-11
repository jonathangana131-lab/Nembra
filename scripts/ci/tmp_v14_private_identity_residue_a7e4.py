#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import textwrap

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "Scripts" / "provision_capture_tuya_identity_writer.py"
RACES = ROOT / "scripts" / "ci" / "tests" / "test_capture_private_identity_publication_races.py"
SELF = Path(__file__).resolve().relative_to(ROOT)
OLD_DIGEST = "8a3bc75629a384f54d4c7dd4cf6f63e4bfc994dbde472683826dfb3acfa19d4f"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor, found {count}")
    return text.replace(old, new, 1)


def patch_writer() -> None:
    text = WRITER.read_text()
    if "def _scrub_fd_best_effort(" not in text:
        marker = "\ndef _validate_existing_output(parent_fd: int, name: str) -> None:\n"
        helper = textwrap.dedent(
            '''
            def _scrub_fd_best_effort(descriptor: int) -> None:
                """Best-effort logical erasure for a rejected credential-bearing inode."""
                try:
                    os.ftruncate(descriptor, 0)
                    os.fsync(descriptor)
                except OSError:
                    pass
            '''
        )
        text = replace_once(text, marker, "\n" + helper + marker, "scrub helper insertion")

    old = '''    except Exception:\n        try:\n            os.unlink(temporary_name, dir_fd=checkout_fd)\n        except FileNotFoundError:\n            pass\n        except OSError:\n            pass\n        raise\n'''
    new = '''    except Exception:\n        # The staging descriptor is the last trustworthy handle to the exact\n        # credential-bearing inode. A hostile rename can make its pathname\n        # unknowable, so erase through the held descriptor before pathname\n        # cleanup. This is a rejection-path logical erasure guarantee, not a\n        # claim of secure physical-media erasure against a same-UID attacker.\n        if staging_fd >= 0:\n            _scrub_fd_best_effort(staging_fd)\n\n        # If publication created/opened a destination before a later custody\n        # check failed, remove only the exact rejected inode we actually hold.\n        if final_fd >= 0:\n            try:\n                rejected_final = os.fstat(final_fd)\n            except OSError:\n                rejected_final = None\n            if rejected_final is not None:\n                _remove_final_if_same_inode_beneath(\n                    checkout_fd,\n                    destination_relative,\n                    rejected_final.st_dev,\n                    rejected_final.st_ino,\n                )\n\n        try:\n            os.unlink(temporary_name, dir_fd=checkout_fd)\n        except FileNotFoundError:\n            pass\n        except OSError:\n            pass\n        raise\n'''
    if "The staging descriptor is the last trustworthy handle" not in text:
        text = replace_once(text, old, new, "rejection cleanup")
    WRITER.write_text(text)


def patch_race_test() -> None:
    text = RACES.read_text()
    old = '''            original_publish = writer._secure_replace_beneath\n            attacked = False\n\n            def adversarial_publish(root_fd: int, src: str, dst: str) -> None:\n                nonlocal attacked\n                if not attacked:\n                    attacked = True\n                    stolen = f"{src}.attacker-stolen"\n                    os.rename(src, stolen, src_dir_fd=root_fd, dst_dir_fd=root_fd)\n'''
    new = '''            original_publish = writer._secure_replace_beneath\n            attacked = False\n            stolen_name: str | None = None\n\n            def adversarial_publish(root_fd: int, src: str, dst: str) -> None:\n                nonlocal attacked, stolen_name\n                if not attacked:\n                    attacked = True\n                    stolen_name = f"{src}.attacker-stolen"\n                    os.rename(src, stolen_name, src_dir_fd=root_fd, dst_dir_fd=root_fd)\n'''
    if "stolen_name: str | None = None" not in text:
        text = replace_once(text, old, new, "capture stolen staging alias")

    old_assert = '''            self.assertNotEqual(\n                final_bytes,\n                attacker_payload,\n                "attacker-controlled replacement bytes remained accepted at the final private identity path",\n            )\n\n\n    def test_same_staging_inode_payload_mutation_cannot_be_accepted(self) -> None:\n'''
    new_assert = '''            self.assertNotEqual(\n                final_bytes,\n                attacker_payload,\n                "attacker-controlled replacement bytes remained accepted at the final private identity path",\n            )\n            self.assertIsNotNone(stolen_name, "diagnostic did not retain the renamed staging alias")\n            stolen = checkout / stolen_name  # type: ignore[arg-type]\n            stolen_bytes = stolen.read_bytes() if stolen.exists() else None\n            self.assertNotEqual(\n                stolen_bytes,\n                payload,\n                "rejected publication left credential-bearing staging bytes under the attacker-chosen alias",\n            )\n\n\n    def test_same_staging_inode_payload_mutation_cannot_be_accepted(self) -> None:\n'''
    if "rejected publication left credential-bearing staging bytes" not in text:
        text = replace_once(text, old_assert, new_assert, "credential residue assertion")
    RACES.write_text(text)


def repin() -> None:
    digest = hashlib.sha256(WRITER.read_bytes()).hexdigest()
    result = subprocess.run(
        ["git", "grep", "-l", "-F", OLD_DIGEST, "--", "."],
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        text=True,
    )
    paths = [Path(line) for line in result.stdout.splitlines() if line]
    functional = [p for p in paths if p != SELF]
    if not functional:
        raise SystemExit("current writer digest is not pinned by tracked functional source")
    print(f"new writer digest: {digest}")
    for relative in functional:
        path = ROOT / relative
        data = path.read_text()
        if OLD_DIGEST not in data:
            raise SystemExit(f"digest grep/read mismatch: {relative}")
        path.write_text(data.replace(OLD_DIGEST, digest))
        print(f"repinned: {relative}")


def main() -> None:
    patch_writer()
    patch_race_test()
    repin()


if __name__ == "__main__":
    main()
