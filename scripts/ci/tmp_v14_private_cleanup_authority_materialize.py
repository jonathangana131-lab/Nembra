#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib

WRITER = Path("Scripts/provision_capture_tuya_identity_writer.py")
SHELL = Path("Scripts/provision_capture_tuya_identity.sh")
SWIFT = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift")
REGRESSION = Path("scripts/ci/tests/test_capture_private_identity_recovery_unlink_race.py")
OLD_DIGEST = "c4c18a77731c781ca203516f061f87929adf829a6acce0b33da81ea2e6bd4f7f"


def require(condition: bool, label: str) -> None:
    if not condition:
        raise RuntimeError(label)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    require(count == 1, f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def main() -> None:
    writer = WRITER.read_text(encoding="utf-8")
    helper = '''def _sanitize_held_private_descriptor(descriptor: int) -> None:\n    """Sanitize only the exact already-held private inode on a failed write path."""\n    try:\n        os.ftruncate(descriptor, 0)\n        os.fsync(descriptor)\n    except OSError as exc:\n        raise ProvisionError("could not sanitize held private identity staging inode after failure") from exc\n\n\n'''
    marker = "def _write_staged(\n"
    require(helper not in writer, "descriptor sanitation helper already present")
    writer = replace_once(writer, marker, helper + marker, "_write_staged insertion point")

    write_start = writer.index("def _write_staged(")
    write_end = writer.index("\ndef _decode_input", write_start)
    write = writer[write_start:write_end]

    old_mismatch = '''        if (\n            not stat.S_ISREG(final.st_mode)\n            or final.st_uid != os.geteuid()\n            or final.st_nlink != 1\n            or final.st_size != len(payload)\n            or final.st_dev != sealed.st_dev\n            or final.st_ino != sealed.st_ino\n        ):\n            _unlink_owned_relative_inode_if_named(checkout_fd, destination_relative, final)\n            raise ProvisionError("published private identity output is not the sealed staging inode")\n'''
    new_mismatch = '''        if (\n            not stat.S_ISREG(final.st_mode)\n            or final.st_uid != os.geteuid()\n            or final.st_nlink != 1\n            or final.st_size != len(payload)\n            or final.st_dev != sealed.st_dev\n            or final.st_ino != sealed.st_ino\n        ):\n            raise ProvisionError("published private identity output is not the sealed staging inode")\n'''
    write = replace_once(write, old_mismatch, new_mismatch, "post-publication mismatch cleanup")

    old_payload_cleanup = '''        except Exception:\n            compromised = os.fstat(final_fd)\n            _unlink_owned_relative_inode_if_named(checkout_fd, destination_relative, compromised)\n            raise\n'''
    new_payload_cleanup = '''        except Exception:\n            raise\n'''
    write = replace_once(write, old_payload_cleanup, new_payload_cleanup, "post-publication payload cleanup")

    old_final_binding_cleanup = '''        except Exception:\n            _unlink_owned_relative_inode_if_named(checkout_fd, destination_relative, sealed)\n            os.fsync(checkout_fd)\n            raise\n'''
    new_final_binding_cleanup = '''        except Exception:\n            raise\n'''
    write = replace_once(write, old_final_binding_cleanup, new_final_binding_cleanup, "final-name cleanup")

    old_outer_cleanup = '''    except Exception:\n        if recovered_stage is not None:\n            if recovered_mutation_started and staging_fd >= 0:\n                try:\n                    os.ftruncate(staging_fd, 0)\n                    os.fsync(staging_fd)\n                except OSError:\n                    pass\n        else:\n            _unlink_owned_inode_if_named(checkout_fd, temporary_name, sealed)\n        raise\n'''
    new_outer_cleanup = '''    except Exception:\n        if staging_fd >= 0 and (recovered_stage is None or recovered_mutation_started):\n            _sanitize_held_private_descriptor(staging_fd)\n        raise\n'''
    write = replace_once(write, old_outer_cleanup, new_outer_cleanup, "outer staging cleanup")
    require("_unlink_owned_inode_if_named" not in write, "pathname inode unlink remains in _write_staged")
    require("_unlink_owned_relative_inode_if_named" not in write, "relative pathname unlink remains in _write_staged")
    writer = writer[:write_start] + write + writer[write_end:]
    WRITER.write_text(writer, encoding="utf-8")

    regression = REGRESSION.read_text(encoding="utf-8")
    old_source_guard = '''        recovery = source[start:end]\n        self.assertNotIn("os.unlink(", recovery)\n        self.assertIn("return recovered", recovery)\n        self.assertIn("_RecoveredPrivateStage", recovery)\n'''
    new_source_guard = '''        recovery = source[start:end]\n        self.assertNotIn("os.unlink(", recovery)\n        self.assertIn("return recovered", recovery)\n        self.assertIn("_RecoveredPrivateStage", recovery)\n\n        write_start = source.index("def _write_staged(")\n        write_end = source.index("def _decode_input", write_start)\n        write_staged = source[write_start:write_end]\n        self.assertNotIn("_unlink_owned_inode_if_named", write_staged)\n        self.assertNotIn("_unlink_owned_relative_inode_if_named", write_staged)\n        self.assertIn("_sanitize_held_private_descriptor", write_staged)\n'''
    regression = replace_once(regression, old_source_guard, new_source_guard, "regression source guard")
    REGRESSION.write_text(regression, encoding="utf-8")

    digest = hashlib.sha256(writer.encode("utf-8")).hexdigest()
    shell = SHELL.read_text(encoding="utf-8")
    require(shell.count(OLD_DIGEST) == 1, "shell writer digest pin changed")
    SHELL.write_text(shell.replace(OLD_DIGEST, digest, 1), encoding="utf-8")

    swift = SWIFT.read_text(encoding="utf-8")
    require(OLD_DIGEST in swift, "Swift writer digest source contract changed")
    swift = swift.replace(OLD_DIGEST, digest)
    marker = '        #expect(writer.contains("_require_recovered_stage_binding"))\n'
    require(swift.count(marker) == 1, "Swift recovered-stage contract marker changed")
    swift = swift.replace(
        marker,
        marker + '        #expect(writer.contains("_sanitize_held_private_descriptor"))\n',
        1,
    )
    SWIFT.write_text(swift, encoding="utf-8")
    print(f"materialized cleanup-authority writer sha256={digest}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"::error title=Private cleanup authority materializer::{type(exc).__name__}: {exc}")
        raise
