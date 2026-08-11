#!/usr/bin/env python3
from pathlib import Path
import hashlib

writer_path = Path('Scripts/provision_capture_tuya_identity_writer.py')
shell_path = Path('Scripts/provision_capture_tuya_identity.sh')
swift_test_path = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift')
race_test_path = Path('scripts/ci/tests/test_capture_private_identity_publication_races.py')

writer = writer_path.read_text(encoding='utf-8')
helper_anchor = '\ndef _secure_replace_beneath(\n'
if writer.count(helper_anchor) != 1:
    raise SystemExit(f'expected one secure-replace anchor, found {writer.count(helper_anchor)}')
helpers = r'''

def _unlink_owned_relative_inode_if_named(
    checkout_fd: int,
    relative_path: str,
    expected: os.stat_result,
) -> None:
    components = _relative_components(relative_path)
    parent_fd = os.dup(checkout_fd)
    try:
        for component in components[:-1]:
            try:
                next_fd = os.open(component, _directory_flags(), dir_fd=parent_fd)
            except OSError:
                return
            os.close(parent_fd)
            parent_fd = next_fd
        try:
            current = os.stat(components[-1], dir_fd=parent_fd, follow_symlinks=False)
        except OSError:
            return
        if (
            stat.S_ISREG(current.st_mode)
            and current.st_uid == os.geteuid()
            and current.st_nlink == 1
            and current.st_dev == expected.st_dev
            and current.st_ino == expected.st_ino
        ):
            try:
                os.unlink(components[-1], dir_fd=parent_fd)
            except OSError:
                pass
    finally:
        os.close(parent_fd)


def _require_exact_payload_bytes(
    descriptor: int,
    payload: bytes,
    sealed: os.stat_result,
) -> None:
    before = os.fstat(descriptor)
    if (
        not stat.S_ISREG(before.st_mode)
        or before.st_uid != os.geteuid()
        or before.st_nlink != 1
        or before.st_size != len(payload)
        or before.st_dev != sealed.st_dev
        or before.st_ino != sealed.st_ino
        or stat.S_IMODE(before.st_mode) != 0o600
    ):
        raise ProvisionError("published private identity payload lost sealed inode custody")

    os.lseek(descriptor, 0, os.SEEK_SET)
    observed = bytearray()
    limit = len(payload) + 1
    while len(observed) < limit:
        chunk = os.read(descriptor, min(65536, limit - len(observed)))
        if not chunk:
            break
        observed.extend(chunk)

    after = os.fstat(descriptor)
    stable_fields = (
        "st_dev",
        "st_ino",
        "st_uid",
        "st_nlink",
        "st_size",
        "st_mode",
        "st_mtime_ns",
        "st_ctime_ns",
    )
    if any(getattr(before, field) != getattr(after, field) for field in stable_fields):
        raise ProvisionError("published private identity payload changed while being verified")
    if bytes(observed) != payload:
        raise ProvisionError("published private identity payload bytes differ from accepted payload")
'''
writer = writer.replace(helper_anchor, helpers + helper_anchor, 1)

declaration_old = '    staging_fd = final_fd = -1\n    sealed: os.stat_result | None = None\n'
declaration_new = '    staging_fd = final_fd = -1\n    sealed: os.stat_result | None = None\n    published: os.stat_result | None = None\n'
if writer.count(declaration_old) != 1:
    raise SystemExit('staging declaration contract drifted')
writer = writer.replace(declaration_old, declaration_new, 1)

final_old = '''        final_fd = _open_relative_regular_file(checkout_fd, destination_relative)\n        final = os.fstat(final_fd)\n        if (\n            not stat.S_ISREG(final.st_mode)\n            or final.st_uid != os.geteuid()\n            or final.st_nlink != 1\n            or final.st_size != len(payload)\n            or final.st_dev != sealed.st_dev\n            or final.st_ino != sealed.st_ino\n        ):\n            raise ProvisionError("published private identity output is not the sealed staging inode")\n        os.fchmod(final_fd, 0o600)\n        os.fsync(final_fd)\n        os.fsync(checkout_fd)\n    except Exception:\n        _unlink_owned_inode_if_named(checkout_fd, temporary_name, sealed)\n        raise\n'''
final_new = '''        final_fd = _open_relative_regular_file(checkout_fd, destination_relative)\n        published = os.fstat(final_fd)\n        if (\n            not stat.S_ISREG(published.st_mode)\n            or published.st_uid != os.geteuid()\n            or published.st_nlink != 1\n            or published.st_size != len(payload)\n            or published.st_dev != sealed.st_dev\n            or published.st_ino != sealed.st_ino\n            or stat.S_IMODE(published.st_mode) != 0o600\n        ):\n            raise ProvisionError("published private identity output is not the sealed staging inode")\n        _require_exact_payload_bytes(final_fd, payload, sealed)\n        os.fsync(final_fd)\n        os.fsync(checkout_fd)\n        _require_exact_payload_bytes(final_fd, payload, sealed)\n    except Exception:\n        if published is not None:\n            _unlink_owned_relative_inode_if_named(checkout_fd, destination_relative, published)\n        _unlink_owned_inode_if_named(checkout_fd, temporary_name, sealed)\n        raise\n'''
if writer.count(final_old) != 1:
    raise SystemExit('final publication block contract drifted')
writer = writer.replace(final_old, final_new, 1)
writer_path.write_text(writer, encoding='utf-8')

races = race_test_path.read_text(encoding='utf-8')
test_anchor = '    def test_detached_private_directory_cannot_receive_or_stage_credential_identity(self) -> None:\n'
if races.count(test_anchor) != 1:
    raise SystemExit('publication-race test anchor drifted')
if 'test_same_staging_inode_payload_mutation_cannot_be_accepted' in races:
    raise SystemExit('same-inode regression already present unexpectedly')
if 'test_staging_substitution_after_name_check_cannot_be_left_at_destination' in races:
    raise SystemExit('post-check regression already present unexpectedly')
tests = r'''    def test_same_staging_inode_payload_mutation_cannot_be_accepted(self) -> None:
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

            def adversarial_publish(root_fd: int, src: str, dst: str, sealed) -> None:
                nonlocal attacked
                if not attacked:
                    attacked = True
                    mutation_fd = os.open(src, os.O_WRONLY | os.O_CLOEXEC | os.O_NOFOLLOW, dir_fd=root_fd)
                    try:
                        mutated = os.fstat(mutation_fd)
                        self.assertEqual((mutated.st_dev, mutated.st_ino), (sealed.st_dev, sealed.st_ino))
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
                original_publish(root_fd, src, dst, sealed)

            writer._secure_replace_beneath = adversarial_publish
            rejected = False
            try:
                try:
                    writer._write_staged(checkout_fd, parent_fd, "identity.swift", "private/identity.swift", payload)
                except (writer.ProvisionError, OSError):
                    rejected = True
            finally:
                writer._secure_replace_beneath = original_publish
                os.close(parent_fd)
                os.close(checkout_fd)

            final = parent / "identity.swift"
            final_bytes = final.read_bytes() if final.is_file() else None
            self.assertTrue(attacked, "diagnostic never reached the sealed-inode publication boundary")
            self.assertTrue(rejected or final_bytes == payload, "writer reported success after the sealed staging inode payload changed in place")
            self.assertNotEqual(final_bytes, attacker_payload, "same-inode attacker bytes were accepted as the published private identity")

    def test_staging_substitution_after_name_check_cannot_be_left_at_destination(self) -> None:
        writer = load_writer()
        payload = b"accepted-private-identity-payload"
        attacker_payload = b"Z" * len(payload)

        with tempfile.TemporaryDirectory(prefix="nembra-private-post-check-race-") as temporary:
            checkout = Path(temporary) / "repo"
            parent = checkout / "private"
            parent.mkdir(parents=True, mode=0o700)
            checkout_fd = os.open(checkout, writer._directory_flags())
            parent_fd = os.open(parent, writer._directory_flags())
            original_require = writer._require_sealed_staging_name
            attacked = False

            def adversarial_require(root_fd: int, src: str, sealed) -> None:
                nonlocal attacked
                original_require(root_fd, src, sealed)
                if attacked:
                    return
                attacked = True
                stolen = f"{src}.sealed-owner"
                os.rename(src, stolen, src_dir_fd=root_fd, dst_dir_fd=root_fd)
                replacement_fd = os.open(src, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=root_fd)
                try:
                    os.write(replacement_fd, attacker_payload)
                    os.fchmod(replacement_fd, 0o600)
                    os.fsync(replacement_fd)
                finally:
                    os.close(replacement_fd)

            writer._require_sealed_staging_name = adversarial_require
            rejected = False
            try:
                try:
                    writer._write_staged(checkout_fd, parent_fd, "identity.swift", "private/identity.swift", payload)
                except (writer.ProvisionError, OSError):
                    rejected = True
            finally:
                writer._require_sealed_staging_name = original_require
                os.close(parent_fd)
                os.close(checkout_fd)

            final = parent / "identity.swift"
            final_bytes = final.read_bytes() if final.is_file() else None
            self.assertTrue(attacked, "diagnostic never reached the post-name-check publication gap")
            self.assertTrue(rejected, "writer accepted the post-check staging substitution")
            self.assertNotEqual(final_bytes, attacker_payload, "post-check attacker replacement was published and left at the credential destination")

'''
races = races.replace(test_anchor, tests + test_anchor, 1)
race_test_path.write_text(races, encoding='utf-8')

digest = hashlib.sha256(writer_path.read_bytes()).hexdigest()
shell = shell_path.read_text(encoding='utf-8')
old_shell_digest = 'e6240cade1db7fd26a9be231d946ca7f580c1554007e196802dfef677075e399'
if shell.count(old_shell_digest) != 1:
    raise SystemExit(f'expected one current #2858 shell digest, found {shell.count(old_shell_digest)}')
shell_path.write_text(shell.replace(old_shell_digest, digest, 1), encoding='utf-8')

swift = swift_test_path.read_text(encoding='utf-8')
old_test_digest = '920e4c416fdf71909bdafecf6e69ed8b76986b87462efee979fc1fe01106be34'
if swift.count(old_test_digest) != 1:
    raise SystemExit(f'expected one stale #2719 package digest, found {swift.count(old_test_digest)}')
swift = swift.replace(old_test_digest, digest, 1)
old_contract = '''        #expect(writer.contains("dir_fd=parent_fd"))\n        #expect(writer.contains("src_dir_fd=parent_fd"))\n        #expect(writer.contains("dst_dir_fd=parent_fd"))\n'''
new_contract = '''        #expect(writer.contains("staging_fd = os.open(temporary_name, _file_flags(), 0o600, dir_fd=checkout_fd)"))\n        #expect(writer.contains("_secure_replace_beneath(checkout_fd, temporary_name, destination_relative, sealed)"))\n        #expect(writer.contains("_require_exact_payload_bytes(final_fd, payload, sealed)"))\n        #expect(writer.contains("_unlink_owned_relative_inode_if_named(checkout_fd, destination_relative, published)"))\n        #expect(writer.contains("renameatx_np("))\n'''
if swift.count(old_contract) != 1:
    raise SystemExit('stale package publication source contract drifted')
swift_test_path.write_text(swift.replace(old_contract, new_contract, 1), encoding='utf-8')
print(f'writer_sha256={digest}')
