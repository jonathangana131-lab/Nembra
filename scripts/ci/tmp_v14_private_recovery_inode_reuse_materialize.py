#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib
import sys
import textwrap

WRITER = Path("Scripts/provision_capture_tuya_identity_writer.py")
SHELL = Path("Scripts/provision_capture_tuya_identity.sh")
SWIFT = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift")
REGRESSION = Path("scripts/ci/tests/test_capture_private_identity_recovery_unlink_race.py")
RACES = Path(".github/workflows/capture-private-identity-publication-races-redteam.yml")
OLD_DIGEST = "a49c6fbe38eabe4983875e2291ce97911ba82d4c4ccfe7c8d7b69ade61edeaf1"


def require(condition: bool, label: str) -> None:
    if not condition:
        raise RuntimeError(label)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    require(text.count(old) == 1, f"{label}: expected one match, found {text.count(old)}")
    return text.replace(old, new, 1)


def main() -> None:
    writer = WRITER.read_text(encoding="utf-8")

    recovery_start = writer.index("def _recover_private_stage_residue")
    recovery_end = writer.index("def _ensure_private_directory", recovery_start)
    recovery = textwrap.dedent('''\
    class _RecoveredPrivateStage:
        """Descriptor custody for one exact writer-shaped hard-exit residue."""

        def __init__(self, name: str, descriptor: int, metadata: os.stat_result) -> None:
            self.name = name
            self.descriptor = descriptor
            self.metadata = metadata

        def take_descriptor(self) -> int:
            if self.descriptor < 0:
                raise ProvisionError("recovered private identity staging descriptor was already consumed")
            descriptor = self.descriptor
            self.descriptor = -1
            return descriptor

        def close(self) -> None:
            if self.descriptor >= 0:
                os.close(self.descriptor)
                self.descriptor = -1


    def _recover_private_stage_residue(checkout_fd: int) -> _RecoveredPrivateStage | None:
        """Admit at most one exact crash residue by descriptor; never delete by pathname."""
        try:
            entries = os.listdir(checkout_fd)
        except OSError as exc:
            raise ProvisionError("could not inspect private identity staging namespace") from exc

        reserved = sorted(name for name in entries if name.startswith(_PRIVATE_STAGE_PREFIX))
        for name in reserved:
            if not _is_canonical_private_stage_name(name):
                raise ProvisionError("reserved private identity staging namespace contains a non-writer entry")
        if not reserved:
            return None
        if len(reserved) != 1:
            raise ProvisionError("private identity staging namespace contains multiple ambiguous crash residues")

        name = reserved[0]
        try:
            named = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)
        except OSError as exc:
            raise ProvisionError("could not inspect reserved private identity staging entry") from exc
        if (
            not stat.S_ISREG(named.st_mode)
            or named.st_uid != os.geteuid()
            or named.st_nlink != 1
            or stat.S_IMODE(named.st_mode) != 0o600
            or named.st_size > _PRIVATE_STAGE_MAX_BYTES
        ):
            raise ProvisionError("reserved private identity staging entry is not safe writer-owned crash residue")

        descriptor = -1
        try:
            descriptor = os.open(
                name,
                os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW,
                dir_fd=checkout_fd,
            )
            held = os.fstat(descriptor)
            current = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)
            if (
                not stat.S_ISREG(held.st_mode)
                or held.st_uid != os.geteuid()
                or held.st_nlink != 1
                or stat.S_IMODE(held.st_mode) != 0o600
                or held.st_size > _PRIVATE_STAGE_MAX_BYTES
                or named.st_dev != held.st_dev
                or named.st_ino != held.st_ino
                or named.st_uid != held.st_uid
                or named.st_nlink != held.st_nlink
                or named.st_mode != held.st_mode
                or named.st_size != held.st_size
                or current.st_dev != held.st_dev
                or current.st_ino != held.st_ino
                or current.st_uid != held.st_uid
                or current.st_nlink != held.st_nlink
                or current.st_mode != held.st_mode
                or current.st_size != held.st_size
            ):
                raise ProvisionError("reserved private identity staging entry changed during recovery admission")
            recovered = _RecoveredPrivateStage(name, descriptor, held)
            descriptor = -1
            return recovered
        except ProvisionError:
            raise
        except OSError as exc:
            raise ProvisionError("could not safely admit writer-owned private identity crash residue") from exc
        finally:
            if descriptor >= 0:
                os.close(descriptor)


    def _require_recovered_stage_binding(
        checkout_fd: int,
        recovered: _RecoveredPrivateStage,
        descriptor: int,
    ) -> None:
        """Re-bind the reserved name to the held inode before any recovered-byte mutation."""
        try:
            current = os.stat(recovered.name, dir_fd=checkout_fd, follow_symlinks=False)
        except OSError as exc:
            raise ProvisionError("recovered private identity staging name changed before reuse") from exc
        held = os.fstat(descriptor)
        admitted = recovered.metadata
        if (
            not stat.S_ISREG(held.st_mode)
            or held.st_uid != os.geteuid()
            or held.st_nlink != 1
            or stat.S_IMODE(held.st_mode) != 0o600
            or held.st_size > _PRIVATE_STAGE_MAX_BYTES
            or held.st_dev != admitted.st_dev
            or held.st_ino != admitted.st_ino
            or held.st_uid != admitted.st_uid
            or held.st_nlink != admitted.st_nlink
            or held.st_mode != admitted.st_mode
            or held.st_size != admitted.st_size
            or current.st_dev != held.st_dev
            or current.st_ino != held.st_ino
            or current.st_uid != held.st_uid
            or current.st_nlink != held.st_nlink
            or current.st_mode != held.st_mode
            or current.st_size != held.st_size
        ):
            raise ProvisionError("recovered private identity staging name no longer binds the admitted inode")


    ''')
    writer = writer[:recovery_start] + recovery + writer[recovery_end:]
    print("materializer: recovery block replaced")

    write_start = writer.index("def _write_staged(")
    write_end = writer.index("\ndef _decode_input", write_start)
    write = writer[write_start:write_end]
    write = replace_once(
        write,
        "    payload: bytes,\n) -> None:",
        "    payload: bytes,\n    recovered_stage: _RecoveredPrivateStage | None = None,\n) -> None:",
        "_write_staged signature",
    )
    old_creation = "\n".join([
        '    temporary_name = f"{_PRIVATE_STAGE_PREFIX}{os.getpid()}-{secrets.token_hex(12)}"',
        '    staging_fd = final_fd = -1',
        '    sealed: os.stat_result | None = None',
        '    try:',
        '        staging_fd = os.open(temporary_name, _file_flags(), 0o600, dir_fd=checkout_fd)',
        '        metadata = os.fstat(staging_fd)',
    ]) + "\n"
    new_creation = "\n".join([
        '    temporary_name = (',
        '        recovered_stage.name',
        '        if recovered_stage is not None',
        '        else f"{_PRIVATE_STAGE_PREFIX}{os.getpid()}-{secrets.token_hex(12)}"',
        '    )',
        '    staging_fd = final_fd = -1',
        '    sealed: os.stat_result | None = None',
        '    recovered_mutation_started = False',
        '    try:',
        '        if recovered_stage is not None:',
        '            staging_fd = recovered_stage.take_descriptor()',
        '            _require_recovered_stage_binding(checkout_fd, recovered_stage, staging_fd)',
        '            recovered_mutation_started = True',
        '            os.ftruncate(staging_fd, 0)',
        '            os.lseek(staging_fd, 0, os.SEEK_SET)',
        '        else:',
        '            staging_fd = os.open(temporary_name, _file_flags(), 0o600, dir_fd=checkout_fd)',
        '        metadata = os.fstat(staging_fd)',
    ]) + "\n"
    write = replace_once(write, old_creation, new_creation, "_write_staged creation")
    old_cleanup = "\n".join([
        '    except Exception:',
        '        _unlink_owned_inode_if_named(checkout_fd, temporary_name, sealed)',
        '        raise',
    ]) + "\n"
    new_cleanup = "\n".join([
        '    except Exception:',
        '        if recovered_stage is not None:',
        '            if recovered_mutation_started and staging_fd >= 0:',
        '                try:',
        '                    os.ftruncate(staging_fd, 0)',
        '                    os.fsync(staging_fd)',
        '                except OSError:',
        '                    pass',
        '        else:',
        '            _unlink_owned_inode_if_named(checkout_fd, temporary_name, sealed)',
        '        raise',
    ]) + "\n"
    write = replace_once(write, old_cleanup, new_cleanup, "_write_staged cleanup")
    writer = writer[:write_start] + write + writer[write_end:]
    print("materializer: staged writer reuse wired")

    provision_start = writer.index("def provision(")
    provision_end = writer.index("\ndef _self_test", provision_start)
    provision = writer[provision_start:provision_end]
    provision = replace_once(
        provision,
        "    local_secrets_fd = runtime_fd = sources_fd = module_fd = -1\n    try:\n        _require_checkout_path_identity(checkout_fd, checkout_root)\n        _recover_private_stage_residue(checkout_fd)",
        "    local_secrets_fd = runtime_fd = sources_fd = module_fd = -1\n    recovered_stage: _RecoveredPrivateStage | None = None\n    try:\n        _require_checkout_path_identity(checkout_fd, checkout_root)\n        recovered_stage = _recover_private_stage_residue(checkout_fd)",
        "provision recovery admission",
    )
    old_first_write = "\n".join([
        '        _write_staged(',
        '            checkout_fd,',
        '            runtime_fd,',
        '            "NembraTuyaPrivateConfig.podspec",',
        '            podspec_relative,',
        '            podspec,',
        '        )',
    ]) + "\n"
    new_first_write = "\n".join([
        '        _write_staged(',
        '            checkout_fd,',
        '            runtime_fd,',
        '            "NembraTuyaPrivateConfig.podspec",',
        '            podspec_relative,',
        '            podspec,',
        '            recovered_stage=recovered_stage,',
        '        )',
    ]) + "\n"
    provision = replace_once(provision, old_first_write, new_first_write, "first private output recovery consumption")
    provision = replace_once(
        provision,
        "    finally:\n        for descriptor in (module_fd, sources_fd, runtime_fd, local_secrets_fd):",
        "    finally:\n        if recovered_stage is not None:\n            recovered_stage.close()\n        for descriptor in (module_fd, sources_fd, runtime_fd, local_secrets_fd):",
        "provision recovered descriptor close",
    )
    writer = writer[:provision_start] + provision + writer[provision_end:]
    WRITER.write_text(writer, encoding="utf-8")
    print("materializer: provision recovery lifecycle wired")

    regression = textwrap.dedent('''\
    #!/usr/bin/env python3
    """Crash-residue reuse must never act on a swapped replacement pathname."""
    from __future__ import annotations

    import importlib.util
    import os
    from pathlib import Path
    import tempfile
    import unittest

    ROOT = Path(__file__).resolve().parents[3]
    WRITER_PATH = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
    PREFIX = ".nembra-private-stage-"


    def load_writer():
        spec = importlib.util.spec_from_file_location("nembra_private_identity_recovery_inode_custody", WRITER_PATH)
        if spec is None or spec.loader is None:
            raise RuntimeError("private identity writer import unavailable")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


    class PrivateIdentityRecoveryInodeCustodyTests(unittest.TestCase):
        def test_post_admission_name_swap_preserves_replacement_and_admitted_inode(self) -> None:
            writer = load_writer()
            admitted_payload = b"dummy-admitted-crash-residue"
            replacement_payload = b"attacker-replacement-must-survive"
            new_payload = b"new-private-output"

            with tempfile.TemporaryDirectory(prefix="nembra-private-recovery-inode-custody-") as temporary:
                checkout = Path(temporary) / "repo"
                destination_parent = checkout / "private"
                destination_parent.mkdir(parents=True, mode=0o700)
                stage_name = f"{PREFIX}{os.getpid()}-{'f' * 24}"
                escaped_name = "attacker-renamed-admitted-residue"
                stage = checkout / stage_name
                escaped = checkout / escaped_name
                destination = destination_parent / "identity.swift"
                stage.write_bytes(admitted_payload)
                stage.chmod(0o600)

                checkout_fd = os.open(checkout, writer._directory_flags())
                destination_fd = os.open(destination_parent, writer._directory_flags())
                recovered = None
                try:
                    recovered = writer._recover_private_stage_residue(checkout_fd)
                    self.assertIsNotNone(recovered, "fixture did not admit the writer-shaped crash residue")

                    os.rename(stage_name, escaped_name, src_dir_fd=checkout_fd, dst_dir_fd=checkout_fd)
                    replacement_fd = os.open(
                        stage_name,
                        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
                        0o600,
                        dir_fd=checkout_fd,
                    )
                    try:
                        os.write(replacement_fd, replacement_payload)
                        os.fsync(replacement_fd)
                    finally:
                        os.close(replacement_fd)

                    with self.assertRaises(writer.ProvisionError):
                        writer._write_staged(
                            checkout_fd,
                            destination_fd,
                            "identity.swift",
                            "private/identity.swift",
                            new_payload,
                            recovered_stage=recovered,
                        )
                finally:
                    if recovered is not None:
                        recovered.close()
                    os.close(destination_fd)
                    os.close(checkout_fd)

                self.assertTrue(escaped.is_file(), "admitted inode disappeared after fail-closed name swap")
                self.assertEqual(escaped.read_bytes(), admitted_payload)
                self.assertTrue(stage.is_file(), "recovery deleted the replacement pathname subject")
                self.assertEqual(stage.read_bytes(), replacement_payload)
                self.assertFalse(destination.exists(), "failed recovery published a private output")

        def test_recovery_source_never_pathname_unlinks_admitted_residue(self) -> None:
            source = WRITER_PATH.read_text(encoding="utf-8")
            start = source.index("def _recover_private_stage_residue")
            end = source.index("def _ensure_private_directory", start)
            recovery = source[start:end]
            self.assertNotIn("os.unlink(", recovery)
            self.assertIn("return recovered", recovery)
            self.assertIn("_RecoveredPrivateStage", recovery)


    if __name__ == "__main__":
        unittest.main(verbosity=2)
    ''')
    REGRESSION.write_text(regression, encoding="utf-8")
    print("materializer: permanent unlink-race regression written")

    races = RACES.read_text(encoding="utf-8")
    path_marker = "      - scripts/ci/tests/test_capture_private_identity_crash_residue.py\n"
    require(races.count(path_marker) == 2, "publication-races path filters changed")
    races = races.replace(path_marker, path_marker + "      - scripts/ci/tests/test_capture_private_identity_recovery_unlink_race.py\n")
    compile_marker = "          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_crash_residue.py\n"
    require(races.count(compile_marker) == 1, "publication-races compile step changed")
    races = races.replace(compile_marker, compile_marker + "          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_recovery_unlink_race.py\n", 1)
    run_marker = "          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_crash_residue.py\n"
    require(races.count(run_marker) == 1, "publication-races runtime step changed")
    races = races.replace(run_marker, run_marker + "          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_recovery_unlink_race.py\n", 1)
    races = races.replace(
        "Reject staging substitution, detached ancestry, crash residue, and final-name swaps",
        "Reject publication races, crash-residue swaps, and final-name swaps",
        1,
    )
    RACES.write_text(races, encoding="utf-8")
    print("materializer: canonical publication-races gate extended")

    digest = hashlib.sha256(writer.encode("utf-8")).hexdigest()
    shell = SHELL.read_text(encoding="utf-8")
    require(shell.count(OLD_DIGEST) == 1, "shell writer digest pin changed")
    SHELL.write_text(shell.replace(OLD_DIGEST, digest, 1), encoding="utf-8")

    swift = SWIFT.read_text(encoding="utf-8")
    require(OLD_DIGEST in swift, "Swift writer digest source contract changed")
    swift = swift.replace(OLD_DIGEST, digest)
    marker = '        #expect(writer.contains("_recover_private_stage_residue"))\n'
    require(swift.count(marker) == 1, "Swift recovery contract marker changed")
    swift = swift.replace(
        marker,
        marker
        + '        #expect(writer.contains("_RecoveredPrivateStage"))\n'
        + '        #expect(writer.contains("_require_recovered_stage_binding"))\n',
        1,
    )
    SWIFT.write_text(swift, encoding="utf-8")
    print(f"materializer: writer digest pins updated to {digest}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"::error title=Private recovery materializer::{type(exc).__name__}: {exc}")
        raise
