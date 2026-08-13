#!/usr/bin/env python3
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
RACES = ROOT / "scripts/ci/tests/test_capture_private_identity_publication_races.py"
SHELL = ROOT / "Scripts/provision_capture_tuya_identity.sh"
SWIFT = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift"


def replace_count(text: str, old: str, new: str, expected: int, label: str) -> str:
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{label}: expected {expected}, found {count}")
    return text.replace(old, new)


writer = WRITER.read_text(encoding="utf-8")
old_cleanup = '''            _remove_exact_inode_links(\n                destination_parent_fd,\n                sealed.st_dev,\n                sealed.st_ino,\n            )\n'''
new_cleanup = '''            _remove_exact_inode_links(\n                destination_parent_fd,\n                sealed.st_dev,\n                sealed.st_ino,\n            )\n            # The sealed credential inode originated under the admitted checkout\n            # root. If a publication-race adversary displaced that exact inode\n            # before the rename, scrub any surviving root link as well.\n            _remove_exact_inode_links(\n                checkout_fd,\n                sealed.st_dev,\n                sealed.st_ino,\n            )\n'''
writer = replace_count(writer, old_cleanup, new_cleanup, 1, "sealed root-link cleanup")
WRITER.write_text(writer, encoding="utf-8")

races = RACES.read_text(encoding="utf-8")
races = replace_count(
    races,
    "writer._secure_replace_beneath",
    "writer._secure_replace_into_held_parent",
    9,
    "publication hook symbol",
)
races = replace_count(
    races,
    "def adversarial_publish(root_fd: int, src: str, dst: str) -> None:",
    "def adversarial_publish(root_fd: int, src: str, destination_parent_fd: int, final_name: str) -> None:",
    3,
    "publication hook signature",
)
races = replace_count(
    races,
    "original_publish(root_fd, src, dst)",
    "original_publish(root_fd, src, destination_parent_fd, final_name)",
    3,
    "publication hook call",
)
races = replace_count(
    races,
    'if not attacked and dst.endswith("NembraTuyaPrivateIdentity.swift"):',
    'if not attacked and final_name == "NembraTuyaPrivateIdentity.swift":',
    1,
    "detached ancestry publication trigger",
)
races = replace_count(
    races,
    '''                    writer._write_staged(\n                        checkout_fd,\n                        parent_fd,\n                        "identity.swift",\n                        "private/identity.swift",\n                        payload,\n                    )\n''',
    '''                    writer._write_staged(\n                        checkout_fd,\n                        parent_fd,\n                        "identity.swift",\n                        "private/identity.swift",\n                        payload,\n                        lambda: None,\n                    )\n''',
    2,
    "isolated publication-race validator",
)
races = races.replace(
    "The attacks are injected at the writer's secure-publication seam so the same\ncontract exercises Linux CI fallback and Darwin renameatx_np publication.\n",
    "The attacks are injected at the writer's held-parent publication seam so the same\ncontract exercises Linux CI fallback and Darwin renameatx_np publication.\n",
    1,
)
RACES.write_text(races, encoding="utf-8")

for path in (WRITER, RACES):
    text = path.read_text(encoding="utf-8")
    if "_secure_replace_beneath" in text:
        raise SystemExit(f"retired root-relative publication seam survived in {path}")

shell = SHELL.read_text(encoding="utf-8")
match = re.search(r'WRITER_SHA256="([0-9a-f]{64})"', shell)
if match is None:
    raise SystemExit("shell writer digest fence missing")
old_digest = match.group(1)
new_digest = hashlib.sha256(WRITER.read_bytes()).hexdigest()
shell = replace_count(shell, old_digest, new_digest, 1, "shell writer digest repin")
SHELL.write_text(shell, encoding="utf-8")

swift = SWIFT.read_text(encoding="utf-8")
swift = replace_count(swift, old_digest, new_digest, 1, "Swift writer digest repin")
SWIFT.write_text(swift, encoding="utf-8")

print(new_digest)
