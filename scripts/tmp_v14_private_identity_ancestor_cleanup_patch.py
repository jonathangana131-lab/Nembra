from pathlib import Path
import hashlib
import re

writer = Path("Scripts/provision_capture_tuya_identity_writer.py")
text = writer.read_text(encoding="utf-8")
anchor = "\n\nclass _SealedStaging:\n"
helper = '''

def _unlink_owned_relative_inode_if_named(
    checkout_fd: int,
    relative_path: str,
    sealed: os.stat_result | None,
) -> None:
    if sealed is None:
        return
    try:
        components = _relative_components(relative_path)
        parent_fd = os.dup(checkout_fd)
        try:
            for component in components[:-1]:
                next_fd = os.open(component, _directory_flags(), dir_fd=parent_fd)
                os.close(parent_fd)
                parent_fd = next_fd
            _unlink_owned_inode_if_named(parent_fd, components[-1], sealed)
        finally:
            os.close(parent_fd)
    except OSError:
        return
'''
if "_unlink_owned_relative_inode_if_named(" not in text:
    if text.count(anchor) != 1:
        raise SystemExit(f"cleanup helper anchor changed: {text.count(anchor)} matches")
    text = text.replace(anchor, helper + anchor, 1)

old_mismatch = '            _unlink_owned_inode_if_named(destination_parent_fd, final_name, final)\n            raise ProvisionError("published private identity output is not the sealed staging inode")\n'
new_mismatch = '            _unlink_owned_relative_inode_if_named(checkout_fd, destination_relative, final)\n            raise ProvisionError("published private identity output is not the sealed staging inode")\n'
if old_mismatch in text:
    text = text.replace(old_mismatch, new_mismatch, 1)
elif new_mismatch not in text:
    raise SystemExit("final mismatch cleanup anchor changed")

old_failure = '            compromised = os.fstat(final_fd)\n            _unlink_owned_inode_if_named(destination_parent_fd, final_name, compromised)\n            raise\n'
new_failure = '            compromised = os.fstat(final_fd)\n            _unlink_owned_relative_inode_if_named(checkout_fd, destination_relative, compromised)\n            raise\n'
if old_failure in text:
    text = text.replace(old_failure, new_failure, 1)
elif new_failure not in text:
    raise SystemExit("final payload failure cleanup anchor changed")
writer.write_text(text, encoding="utf-8")

digest = hashlib.sha256(writer.read_bytes()).hexdigest()
shell = Path("Scripts/provision_capture_tuya_identity.sh")
shell_text = shell.read_text(encoding="utf-8")
shell_text, count = re.subn(r'WRITER_SHA256="[0-9a-f]{64}"', f'WRITER_SHA256="{digest}"', shell_text, count=1)
if count != 1:
    raise SystemExit("writer digest shell anchor changed")
shell.write_text(shell_text, encoding="utf-8")

contract = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift")
source = contract.read_text(encoding="utf-8")
source, count = re.subn(r'WRITER_SHA256=\\"[0-9a-f]{64}\\"', f'WRITER_SHA256=\\"{digest}\\"', source, count=1)
if count != 1:
    raise SystemExit("writer digest package anchor changed")
if '_unlink_owned_relative_inode_if_named' not in source:
    marker = '#expect(writer.contains("_require_descriptor_payload"))'
    if source.count(marker) != 1:
        raise SystemExit("package cleanup contract insertion anchor changed")
    source = source.replace(marker, marker + '\n        #expect(writer.contains("_unlink_owned_relative_inode_if_named"))', 1)
contract.write_text(source, encoding="utf-8")
print(digest)
