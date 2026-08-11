#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
SHELL = ROOT / "Scripts/provision_capture_tuya_identity.sh"
SWIFT = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift"
TEMP_SCRIPT = ROOT / "scripts/ci/tmp_materialize_private_identity_realpath_sol.py"
TEMP_WORKFLOW = ROOT / ".github/workflows/tmp-v14-private-identity-realpath-sol.yml"
OLD_WRITER_SHA256 = "e3a123907373e10d333eb8fafda6ef1e869e1c67494513fa05ef589764f0ae44"
EXPECTED_BLOBS = {
    WRITER: "399413cc72b319750fa8a73682e9b54cb8bc7bb7",
    SHELL: "159ce1a47c867a95a24ea55deb1cf6566bf4faa2",
    SWIFT: "be44e79f2403368af93185b07d168de87306e8ae",
}


def git_blob(path: Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    return source.replace(old, new, 1)


for path, expected in EXPECTED_BLOBS.items():
    actual = git_blob(path)
    if actual != expected:
        raise SystemExit(f"stale materializer for {path.relative_to(ROOT)}: {actual} != {expected}")

writer = WRITER.read_text(encoding="utf-8")
writer = replace_once(
    writer,
    "        root = Path(temporary)\n",
    "        root = Path(os.path.realpath(temporary))\n",
    "macOS physical temporary-root spelling",
)
WRITER.write_text(writer, encoding="utf-8")
new_writer_sha256 = hashlib.sha256(WRITER.read_bytes()).hexdigest()
if new_writer_sha256 == OLD_WRITER_SHA256:
    raise SystemExit("writer digest unexpectedly unchanged")

shell = SHELL.read_text(encoding="utf-8")
shell = replace_once(shell, OLD_WRITER_SHA256, new_writer_sha256, "shell writer digest")
SHELL.write_text(shell, encoding="utf-8")

swift = SWIFT.read_text(encoding="utf-8")
swift = replace_once(swift, OLD_WRITER_SHA256, new_writer_sha256, "Swift writer digest")
swift = replace_once(
    swift,
    '        #expect(writer.contains("_require_final_relative_name_binding"))\n',
    '        #expect(writer.contains("_require_final_relative_name_binding"))\n'
    '        #expect(writer.contains("os.path.realpath(temporary)"))\n',
    "Swift realpath source contract",
)
SWIFT.write_text(swift, encoding="utf-8")

TEMP_SCRIPT.unlink()
TEMP_WORKFLOW.unlink()
print(f"materialized macOS realpath repair; writer digest {new_writer_sha256}")
