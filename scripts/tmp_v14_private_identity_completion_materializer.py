#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path
import re

ROOT = Path.cwd()
WRITER = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
SHELL = ROOT / "Scripts/provision_capture_tuya_identity.sh"
SWIFT = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift"
WORKFLOW = ROOT / ".github/workflows/capture-private-identity-publication-races-redteam.yml"
CRASH = ROOT / "scripts/ci/tests/test_capture_private_identity_crash_residue.py"

writer = WRITER.read_text(encoding="utf-8")

constant_anchor = '_DARWIN_RENAME_RESOLVE_BENEATH = 0x00000020\n'
constant_replacement = constant_anchor + '_RESERVED_STAGE_PREFIX = ".nembra-private-stage-"\n'
if '_RESERVED_STAGE_PREFIX = ".nembra-private-stage-"' not in writer:
    if writer.count(constant_anchor) != 1:
        raise SystemExit(f"reserved-prefix anchor changed: {writer.count(constant_anchor)}")
    writer = writer.replace(constant_anchor, constant_replacement, 1)

helper_anchor = '''\n\nclass _SealedStaging:\n'''
helpers = r'''

def _recover_reserved_staging(checkout_fd: int) -> None:
    """Remove only safe writer-shaped crash residue; fail closed on every unsafe reserved entry."""
    try:
        names = sorted(name for name in os.listdir(checkout_fd) if name.startswith(_RESERVED_STAGE_PREFIX))
    except OSError as exc:
        raise ProvisionError("could not inspect reserved private identity staging namespace") from exc

    for name in names:
        try:
            metadata = os.stat(name, dir_fd=checkout_fd, follow_symlinks=False)
        except FileNotFoundError:
            continue
        except OSError as exc:
            raise ProvisionError("could not inspect reserved private identity staging entry") from exc
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_uid != os.geteuid()
            or metadata.st_nlink != 1
        ):
            raise ProvisionError("reserved private identity staging namespace contains an unsafe entry")
        _unlink_owned_inode_if_named(checkout_fd, name, metadata)
        os.fsync(checkout_fd)

    try:
        remaining = sorted(name for name in os.listdir(checkout_fd) if name.startswith(_RESERVED_STAGE_PREFIX))
    except OSError as exc:
        raise ProvisionError("could not re-inspect reserved private identity staging namespace") from exc
    if remaining:
        raise ProvisionError("reserved private identity staging namespace could not be recovered safely")


def _require_relative_name_matches_descriptor(
    checkout_fd: int,
    relative_path: str,
    descriptor: int,
    label: str,
) -> None:
    components = _relative_components(relative_path)
    parent_fd = os.dup(checkout_fd)
    try:
        for component in components[:-1]:
            next_fd = os.open(component, _directory_flags(), dir_fd=parent_fd)
            os.close(parent_fd)
            parent_fd = next_fd
        try:
            named = os.stat(components[-1], dir_fd=parent_fd, follow_symlinks=False)
        except OSError as exc:
            raise ProvisionError(f"{label}: canonical destination is unavailable") from exc
        held = os.fstat(descriptor)
        if (
            not stat.S_ISREG(named.st_mode)
            or not stat.S_ISREG(held.st_mode)
            or named.st_uid != os.geteuid()
            or held.st_uid != os.geteuid()
            or named.st_nlink != 1
            or held.st_nlink != 1
            or named.st_dev != held.st_dev
            or named.st_ino != held.st_ino
        ):
            raise ProvisionError(f"{label}: canonical destination no longer names the accepted published inode")
    finally:
        os.close(parent_fd)
'''
if 'def _recover_reserved_staging(' not in writer:
    if writer.count(helper_anchor) != 1:
        raise SystemExit(f"helper insertion anchor changed: {writer.count(helper_anchor)}")
    writer = writer.replace(helper_anchor, helpers + helper_anchor, 1)
if 'def _require_relative_name_matches_descriptor(' not in writer:
    raise SystemExit("final-name helper insertion failed")

final_anchor = '''            _require_descriptor_payload(\n                final_fd,\n                payload,\n                "published private identity payload changed before durable success",\n            )\n'''
final_replacement = final_anchor + '''            _require_relative_name_matches_descriptor(\n                checkout_fd,\n                destination_relative,\n                final_fd,\n                "published private identity name changed before durable success",\n            )\n'''
if 'published private identity name changed before durable success' not in writer:
    if writer.count(final_anchor) != 1:
        raise SystemExit(f"final-name pre-fsync anchor changed: {writer.count(final_anchor)}")
    writer = writer.replace(final_anchor, final_replacement, 1)

fsync_anchor = '''        os.fsync(checkout_fd)\n    except Exception:\n        _unlink_owned_inode_if_named(checkout_fd, temporary_name, sealed)\n'''
fsync_replacement = '''        os.fsync(checkout_fd)\n        _require_relative_name_matches_descriptor(\n            checkout_fd,\n            destination_relative,\n            final_fd,\n            "published private identity name changed at final success boundary",\n        )\n    except Exception:\n        _unlink_owned_inode_if_named(checkout_fd, temporary_name, sealed)\n'''
if 'published private identity name changed at final success boundary' not in writer:
    if writer.count(fsync_anchor) != 1:
        raise SystemExit(f"final-name success-boundary anchor changed: {writer.count(fsync_anchor)}")
    writer = writer.replace(fsync_anchor, fsync_replacement, 1)

provision_anchor = '''    try:\n        _require_checkout_path_identity(checkout_fd, checkout_root)\n        local_secrets_fd = _ensure_private_directory(checkout_fd, "LocalSecrets")\n'''
provision_replacement = '''    try:\n        _require_checkout_path_identity(checkout_fd, checkout_root)\n        _recover_reserved_staging(checkout_fd)\n        _require_checkout_path_identity(checkout_fd, checkout_root)\n        local_secrets_fd = _ensure_private_directory(checkout_fd, "LocalSecrets")\n'''
if '_recover_reserved_staging(checkout_fd)' not in writer:
    if writer.count(provision_anchor) != 1:
        raise SystemExit(f"crash-recovery admission anchor changed: {writer.count(provision_anchor)}")
    writer = writer.replace(provision_anchor, provision_replacement, 1)

realpath_old = '        root = Path(temporary)\n        checkout = root / "repo"\n'
realpath_new = '        root = Path(os.path.realpath(temporary))\n        checkout = root / "repo"\n'
if realpath_new not in writer:
    if writer.count(realpath_old) != 1:
        raise SystemExit(f"macOS realpath self-test anchor changed: {writer.count(realpath_old)}")
    writer = writer.replace(realpath_old, realpath_new, 1)

WRITER.write_text(writer, encoding="utf-8")

digest = hashlib.sha256(WRITER.read_bytes()).hexdigest()

shell = SHELL.read_text(encoding="utf-8")
shell, count = re.subn(r'WRITER_SHA256="[0-9a-f]{64}"', f'WRITER_SHA256="{digest}"', shell, count=1)
if count != 1:
    raise SystemExit("writer digest shell anchor changed")
SHELL.write_text(shell, encoding="utf-8")

swift = SWIFT.read_text(encoding="utf-8")
swift, count = re.subn(r'WRITER_SHA256=\\"[0-9a-f]{64}\\"', f'WRITER_SHA256=\\"{digest}\\"', swift, count=1)
if count != 1:
    raise SystemExit("writer digest Swift anchor changed")
contract_anchor = '        #expect(writer.contains("_unlink_owned_relative_inode_if_named"))\n'
contract_extra = contract_anchor + '''        #expect(writer.contains("_recover_reserved_staging"))\n        #expect(writer.contains("_require_relative_name_matches_descriptor"))\n        #expect(writer.contains("os.path.realpath(temporary)"))\n'''
if '#expect(writer.contains("_recover_reserved_staging"))' not in swift:
    if swift.count(contract_anchor) != 1:
        raise SystemExit(f"Swift recovery contract anchor changed: {swift.count(contract_anchor)}")
    swift = swift.replace(contract_anchor, contract_extra, 1)
SWIFT.write_text(swift, encoding="utf-8")

workflow = WORKFLOW.read_text(encoding="utf-8")
path_anchor = '      - scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py\n'
path_extra = path_anchor + '      - scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py\n      - scripts/ci/tests/test_capture_private_identity_crash_residue.py\n'
if '      - scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py\n' not in workflow:
    if workflow.count(path_anchor) != 2:
        raise SystemExit(f"workflow path anchor changed: {workflow.count(path_anchor)}")
    workflow = workflow.replace(path_anchor, path_extra)

compile_anchor = '          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py\n'
compile_extra = compile_anchor + '          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py\n          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_crash_residue.py\n'
if '          /usr/bin/python3 -m py_compile scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py\n' not in workflow:
    if workflow.count(compile_anchor) != 1:
        raise SystemExit(f"workflow compile anchor changed: {workflow.count(compile_anchor)}")
    workflow = workflow.replace(compile_anchor, compile_extra, 1)

run_anchor = '          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_destination_ancestor_swap_current.py\n'
run_extra = run_anchor + '          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py\n          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_crash_residue.py\n'
if '          /usr/bin/python3 -I scripts/ci/tests/test_capture_private_identity_final_name_binding_2874.py\n' not in workflow:
    if workflow.count(run_anchor) != 1:
        raise SystemExit(f"workflow run anchor changed: {workflow.count(run_anchor)}")
    workflow = workflow.replace(run_anchor, run_extra, 1)
WORKFLOW.write_text(workflow, encoding="utf-8")

crash = CRASH.read_text(encoding="utf-8")
old_signature = '                    def hard_exit_after_seal(_root_fd: int, _src: str, _dst: str) -> None:\n'
new_signature = '                    def hard_exit_after_seal(_root_fd: int, _src: str, _dst: str, _sealed) -> None:\n'
if new_signature not in crash:
    if crash.count(old_signature) != 1:
        raise SystemExit(f"crash seam signature anchor changed: {crash.count(old_signature)}")
    crash = crash.replace(old_signature, new_signature, 1)
CRASH.write_text(crash, encoding="utf-8")

print(digest)
