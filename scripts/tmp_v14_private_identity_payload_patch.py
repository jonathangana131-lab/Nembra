from pathlib import Path
import hashlib
import re
import subprocess

writer_path = Path('Scripts/provision_capture_tuya_identity_writer.py')
text = writer_path.read_text(encoding='utf-8')
if 'import hashlib\n' not in text:
    text = text.replace('import ctypes\nimport os\n', 'import ctypes\nimport hashlib\nimport hmac\nimport os\n', 1)
old_flags = '    return os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW\n'
new_flags = '    return os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW\n'
if old_flags in text:
    text = text.replace(old_flags, new_flags, 1)
elif new_flags not in text:
    raise SystemExit('writer staging flags anchor changed')

anchor = '\ndef _secure_replace_beneath(\n'
helper = '''
class _SealedStaging:
    def __init__(self, metadata: os.stat_result, descriptor: int, payload: bytes) -> None:
        self.metadata = metadata
        self.descriptor = descriptor
        self.payload = payload

    def __getattr__(self, name: str):
        return getattr(self.metadata, name)


def _payload_stat_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _require_descriptor_payload(descriptor: int, payload: bytes, label: str) -> None:
    before = os.fstat(descriptor)
    if (
        not stat.S_ISREG(before.st_mode)
        or before.st_uid != os.geteuid()
        or before.st_nlink != 1
        or before.st_size != len(payload)
    ):
        raise ProvisionError(f"{label}: descriptor metadata no longer matches accepted payload custody")

    chunks: list[bytes] = []
    offset = 0
    while offset < before.st_size:
        chunk = os.pread(descriptor, min(65_536, before.st_size - offset), offset)
        if not chunk:
            raise ProvisionError(f"{label}: descriptor bytes changed during accepted payload read")
        chunks.append(chunk)
        offset += len(chunk)
    if os.pread(descriptor, 1, before.st_size):
        raise ProvisionError(f"{label}: descriptor grew during accepted payload read")

    after = os.fstat(descriptor)
    if _payload_stat_identity(before) != _payload_stat_identity(after):
        raise ProvisionError(f"{label}: descriptor metadata changed during accepted payload read")
    actual = hashlib.sha256(b"".join(chunks)).digest()
    expected = hashlib.sha256(payload).digest()
    if not hmac.compare_digest(actual, expected):
        raise ProvisionError(f"{label}: descriptor bytes do not match the accepted payload")


'''
if '_payload_stat_identity(' not in text:
    if text.count(anchor) != 1:
        raise SystemExit(f'writer secure publication anchor changed: {text.count(anchor)} matches')
    text = text.replace(anchor, helper + 'def _secure_replace_beneath(\n', 1)

secure_anchor = '    _require_sealed_staging_name(checkout_fd, source_name, sealed)\n'
secure_payload = '''    _require_sealed_staging_name(checkout_fd, source_name, sealed)
    if isinstance(sealed, _SealedStaging):
        _require_descriptor_payload(
            sealed.descriptor,
            sealed.payload,
            "private identity staging payload changed immediately before publication",
        )
'''
if secure_payload not in text:
    if text.count(secure_anchor) != 1:
        raise SystemExit('writer publication sealed-name anchor changed')
    text = text.replace(secure_anchor, secure_payload, 1)

old_call = '        _secure_replace_beneath(checkout_fd, temporary_name, destination_relative, sealed)\n\n        final_fd = _open_relative_regular_file(checkout_fd, destination_relative)\n'
new_call = '''        _require_descriptor_payload(
            staging_fd,
            payload,
            "private identity staging payload changed before publication",
        )
        sealed_authority = _SealedStaging(sealed, staging_fd, payload)
        _secure_replace_beneath(
            checkout_fd,
            temporary_name,
            destination_relative,
            sealed_authority,
        )

        final_fd = _open_relative_regular_file(checkout_fd, destination_relative)
'''
if old_call in text:
    text = text.replace(old_call, new_call, 1)
elif new_call not in text:
    raise SystemExit('writer publication call anchor changed')

old_final = '''        if (\n            not stat.S_ISREG(final.st_mode)\n            or final.st_uid != os.geteuid()\n            or final.st_nlink != 1\n            or final.st_size != len(payload)\n            or final.st_dev != sealed.st_dev\n            or final.st_ino != sealed.st_ino\n        ):\n            raise ProvisionError("published private identity output is not the sealed staging inode")\n        os.fchmod(final_fd, 0o600)\n        os.fsync(final_fd)\n        os.fsync(checkout_fd)\n'''
new_final = '''        if (\n            not stat.S_ISREG(final.st_mode)\n            or final.st_uid != os.geteuid()\n            or final.st_nlink != 1\n            or final.st_size != len(payload)\n            or final.st_dev != sealed.st_dev\n            or final.st_ino != sealed.st_ino\n        ):\n            _unlink_owned_inode_if_named(destination_parent_fd, final_name, final)\n            raise ProvisionError("published private identity output is not the sealed staging inode")\n        try:\n            _require_descriptor_payload(\n                final_fd,\n                payload,\n                "published private identity payload failed post-publication authority",\n            )\n            os.fchmod(final_fd, 0o600)\n            os.fsync(final_fd)\n            _require_descriptor_payload(\n                final_fd,\n                payload,\n                "published private identity payload changed before durable success",\n            )\n        except Exception:\n            compromised = os.fstat(final_fd)\n            _unlink_owned_inode_if_named(destination_parent_fd, final_name, compromised)\n            raise\n        os.fsync(checkout_fd)\n'''
if old_final in text:
    text = text.replace(old_final, new_final, 1)
elif new_final not in text:
    raise SystemExit('writer final authority anchor changed')
writer_path.write_text(text, encoding='utf-8')

post = 'f8e9c71f0a78484de1fc8a1dacc38c112a7a2a37'
same = 'd29a3dc6e2d1c5db3e0661a415e619134c4a5587'
subprocess.run(['git','fetch','--no-tags','origin',post,same], check=True)
Path('scripts/ci/tests/test_capture_private_identity_publication_races.py').write_bytes(subprocess.check_output(['git','show',f'{post}:scripts/ci/tests/test_capture_private_identity_publication_races.py']))
Path('scripts/ci/tests/test_capture_private_identity_same_inode_payload_current.py').write_bytes(subprocess.check_output(['git','show',f'{same}:scripts/ci/tests/test_capture_private_identity_same_inode_payload_current.py']))

workflow = Path('.github/workflows/capture-private-identity-publication-races-redteam.yml')
w = workflow.read_text(encoding='utf-8')
path_anchor = '      - scripts/ci/tests/test_capture_private_identity_publication_races.py\n'
path_line = '      - scripts/ci/tests/test_capture_private_identity_same_inode_payload_current.py\n'
if path_line not in w:
    w = w.replace(path_anchor, path_anchor + path_line, 1)
compile_anchor = '          python3 -m py_compile scripts/ci/tests/test_capture_private_identity_publication_races.py\n'
compile_line = '          python3 -m py_compile scripts/ci/tests/test_capture_private_identity_same_inode_payload_current.py\n'
if compile_line not in w:
    w = w.replace(compile_anchor, compile_anchor + compile_line, 1)
run_anchor = '          python3 -I scripts/ci/tests/test_capture_private_identity_publication_races.py\n'
run_line = '          python3 -I scripts/ci/tests/test_capture_private_identity_same_inode_payload_current.py\n'
if run_line not in w:
    w = w.replace(run_anchor, run_anchor + run_line, 1)
workflow.write_text(w, encoding='utf-8')

digest = hashlib.sha256(writer_path.read_bytes()).hexdigest()
shell = Path('Scripts/provision_capture_tuya_identity.sh')
s = shell.read_text(encoding='utf-8')
s, count = re.subn(r'WRITER_SHA256="[0-9a-f]{64}"', f'WRITER_SHA256="{digest}"', s, count=1)
if count != 1:
    raise SystemExit('writer digest shell anchor changed')
shell.write_text(s, encoding='utf-8')

test = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift')
src = test.read_text(encoding='utf-8')
src, count = re.subn(r'WRITER_SHA256=\\"[0-9a-f]{64}\\"', f'WRITER_SHA256=\\"{digest}\\"', src, count=1)
if count != 1:
    raise SystemExit('writer digest package anchor changed')
src = src.replace('#expect(writer.contains("src_dir_fd=parent_fd"))', '#expect(writer.contains("src_dir_fd=checkout_fd"))')
src = src.replace('#expect(writer.contains("dst_dir_fd=parent_fd"))', '#expect(writer.contains("dst_dir_fd=checkout_fd"))')
src = src.replace('#expect(writer.contains("dir_fd=parent_fd"))', '#expect(writer.contains("_require_descriptor_payload"))\n        #expect(writer.contains("hashlib.sha256"))\n        #expect(writer.contains("dir_fd=checkout_fd"))', 1)
test.write_text(src, encoding='utf-8')
print(digest)
