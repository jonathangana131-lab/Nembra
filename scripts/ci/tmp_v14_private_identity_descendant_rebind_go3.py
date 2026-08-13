#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "Scripts/provision_capture_tuya_identity_writer.py"
SHELL = ROOT / "Scripts/provision_capture_tuya_identity.sh"
SWIFT_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift"
REDTEAM = ROOT / "scripts/ci/tests/test_capture_private_identity_descendant_rebind_redteam.py"


def replace_between(text: str, start: str, end: str, replacement: str) -> str:
    begin = text.index(start)
    finish = text.index(end, begin)
    return text[:begin] + replacement + text[finish:]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one replacement subject, found {count}")
    return text.replace(old, new, 1)


writer = WRITER.read_text(encoding="utf-8")
writer = replace_once(
    writer,
    "Credential-bearing staging files are created directly under the admitted root,\n"
    "not under long-lived descendant directory descriptors. On Darwin, publication\n"
    "uses renameatx_np with no-follow-any + resolve-beneath semantics so every path\n"
    "component is resolved beneath that admitted root in the publication syscall.\n"
    "The sealed staging descriptor remains open through publication and the final\n"
    "named inode must match it exactly before success.\n",
    "Credential-bearing staging files are created directly under the admitted root,\n"
    "then published into the already-held admitted destination-parent descriptor.\n"
    "On Darwin, renameatx_np keeps the source root and held destination parent as the\n"
    "actual syscall authorities, so a swapped descendant pathname cannot receive the\n"
    "credential inode. The sealed inode remains open through payload validation, the\n"
    "held ancestry is re-proved, and the canonical final name must still bind to that\n"
    "same inode immediately before success. Rejection scrubs every exact link to the\n"
    "sealed inode that remains in the held private parent.\n",
    "writer docstring",
)

writer = replace_between(
    writer,
    "def _open_relative_regular_file(checkout_fd: int, relative_path: str) -> int:\n",
    "def _require_staging_name_matches_fd(\n",
    '''def _open_held_regular_file(parent_fd: int, name: str) -> int:\n    if not name or name in (".", "..") or "/" in name:\n        raise ProvisionError("private identity output name is not one canonical component")\n    try:\n        return os.open(\n            name,\n            os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW,\n            dir_fd=parent_fd,\n        )\n    except OSError as exc:\n        raise ProvisionError("published private identity output is unavailable in the admitted parent") from exc\n\n\n''',
)

writer = replace_between(
    writer,
    "def _remove_final_if_same_inode_beneath(\n",
    "def _publication_metadata_signature(metadata: os.stat_result) -> tuple[int, ...]:\n",
    '''def _remove_exact_inode_links(\n    parent_fd: int,\n    expected_dev: int,\n    expected_ino: int,\n) -> None:\n    try:\n        names = os.listdir(parent_fd)\n    except OSError:\n        return\n    removed = False\n    for name in names:\n        try:\n            named = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)\n        except OSError:\n            continue\n        if (\n            stat.S_ISREG(named.st_mode)\n            and named.st_uid == os.geteuid()\n            and named.st_dev == expected_dev\n            and named.st_ino == expected_ino\n        ):\n            try:\n                os.unlink(name, dir_fd=parent_fd)\n                removed = True\n            except OSError:\n                pass\n    if removed:\n        try:\n            os.fsync(parent_fd)\n        except OSError:\n            pass\n\n\ndef _remove_replacement_name_if_safe(\n    parent_fd: int,\n    name: str,\n    protected_dev: int,\n    protected_ino: int,\n) -> None:\n    try:\n        named = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)\n    except OSError:\n        return\n    if named.st_dev == protected_dev and named.st_ino == protected_ino:\n        return\n    if (\n        stat.S_ISREG(named.st_mode)\n        and named.st_uid == os.geteuid()\n        and named.st_nlink == 1\n    ):\n        try:\n            os.unlink(name, dir_fd=parent_fd)\n            os.fsync(parent_fd)\n        except OSError:\n            pass\n\n\ndef _require_named_file_matches_fd(parent_fd: int, name: str, descriptor: int) -> None:\n    try:\n        named = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)\n    except OSError as exc:\n        raise ProvisionError("private identity final name disappeared before success") from exc\n    held = os.fstat(descriptor)\n    if (\n        not stat.S_ISREG(named.st_mode)\n        or not stat.S_ISREG(held.st_mode)\n        or named.st_uid != os.geteuid()\n        or held.st_uid != os.geteuid()\n        or named.st_nlink != 1\n        or held.st_nlink != 1\n        or named.st_dev != held.st_dev\n        or named.st_ino != held.st_ino\n    ):\n        raise ProvisionError("private identity final name no longer binds the accepted sealed inode")\n\n\n''',
)

writer = replace_between(
    writer,
    "def _secure_replace_beneath(checkout_fd: int, source_name: str, destination_relative: str) -> None:\n",
    "def _write_staged(\n",
    '''def _secure_replace_into_held_parent(\n    checkout_fd: int,\n    source_name: str,\n    destination_parent_fd: int,\n    final_name: str,\n) -> None:\n    source_components = _relative_components(source_name)\n    if len(source_components) != 1:\n        raise ProvisionError("private identity staging source must be one checkout-root component")\n    if not final_name or final_name in (".", "..") or "/" in final_name:\n        raise ProvisionError("private identity destination must be one held-parent component")\n    if sys.platform == "darwin":\n        libc = ctypes.CDLL(None, use_errno=True)\n        try:\n            renameatx_np = libc.renameatx_np\n        except AttributeError as exc:\n            raise ProvisionError("Darwin cannot provide renameatx_np publication custody") from exc\n        renameatx_np.argtypes = (\n            ctypes.c_int,\n            ctypes.c_char_p,\n            ctypes.c_int,\n            ctypes.c_char_p,\n            ctypes.c_uint,\n        )\n        renameatx_np.restype = ctypes.c_int\n        flags = _DARWIN_RENAME_NOFOLLOW_ANY | _DARWIN_RENAME_RESOLVE_BENEATH\n        result = renameatx_np(\n            checkout_fd,\n            os.fsencode(source_name),\n            destination_parent_fd,\n            os.fsencode(final_name),\n            flags,\n        )\n        if result != 0:\n            error = ctypes.get_errno()\n            raise ProvisionError("Darwin rejected private identity publication into admitted parent") from OSError(\n                error,\n                os.strerror(error),\n            )\n        return\n\n    # Linux CI fallback exercises the same held-parent custody shape. Physical\n    # field publication is macOS-only and is required to take the Darwin path.\n    os.replace(\n        source_name,\n        final_name,\n        src_dir_fd=checkout_fd,\n        dst_dir_fd=destination_parent_fd,\n    )\n\n\n''',
)

writer = replace_between(
    writer,
    "def _write_staged(\n",
    "def _decode_input() -> tuple[str, str]:\n",
    '''def _write_staged(\n    checkout_fd: int,\n    destination_parent_fd: int,\n    final_name: str,\n    destination_relative: str,\n    payload: bytes,\n    post_publish_validator,\n) -> None:\n    components = _relative_components(destination_relative)\n    if components[-1] != final_name:\n        raise ProvisionError("private identity final name does not match its admitted relative path")\n    _validate_existing_output(destination_parent_fd, final_name)\n\n    temporary_name = f".nembra-private-stage-{os.getpid()}-{secrets.token_hex(12)}"\n    staging_fd = final_fd = -1\n    sealed: os.stat_result | None = None\n    published = False\n    try:\n        staging_fd = os.open(temporary_name, _file_flags(), 0o600, dir_fd=checkout_fd)\n        metadata = os.fstat(staging_fd)\n        if (\n            not stat.S_ISREG(metadata.st_mode)\n            or metadata.st_uid != os.geteuid()\n            or metadata.st_nlink != 1\n        ):\n            raise ProvisionError("new private identity staging file failed ownership custody")\n\n        view = memoryview(payload)\n        offset = 0\n        while offset < len(view):\n            written = os.write(staging_fd, view[offset:])\n            if written <= 0:\n                raise ProvisionError("could not write complete private identity output")\n            offset += written\n        os.fchmod(staging_fd, 0o600)\n        os.fsync(staging_fd)\n        sealed = os.fstat(staging_fd)\n        if sealed.st_size != len(payload) or sealed.st_nlink != 1:\n            raise ProvisionError("private identity staging file changed before publication")\n\n        _require_staging_name_matches_fd(checkout_fd, temporary_name, sealed)\n        _secure_replace_into_held_parent(\n            checkout_fd,\n            temporary_name,\n            destination_parent_fd,\n            final_name,\n        )\n        published = True\n\n        final_fd = _open_held_regular_file(destination_parent_fd, final_name)\n        final = os.fstat(final_fd)\n        if (\n            not stat.S_ISREG(final.st_mode)\n            or final.st_uid != os.geteuid()\n            or final.st_nlink != 1\n            or final.st_size != len(payload)\n            or final.st_dev != sealed.st_dev\n            or final.st_ino != sealed.st_ino\n        ):\n            raise ProvisionError("published private identity output is not the sealed staging inode")\n\n        before_read = _publication_metadata_signature(final)\n        published_payload = _read_exact_fd_payload(final_fd, len(payload))\n        after_read_metadata = os.fstat(final_fd)\n        after_read = _publication_metadata_signature(after_read_metadata)\n        if before_read != after_read or published_payload != payload:\n            raise ProvisionError("published private identity output changed or does not match accepted bytes")\n\n        os.fchmod(final_fd, 0o600)\n        os.fsync(final_fd)\n        post_publish_validator()\n        _require_named_file_matches_fd(destination_parent_fd, final_name, final_fd)\n        os.fsync(destination_parent_fd)\n        os.fsync(checkout_fd)\n    except Exception:\n        if published and sealed is not None:\n            _remove_replacement_name_if_safe(\n                destination_parent_fd,\n                final_name,\n                sealed.st_dev,\n                sealed.st_ino,\n            )\n            _remove_exact_inode_links(\n                destination_parent_fd,\n                sealed.st_dev,\n                sealed.st_ino,\n            )\n        try:\n            os.unlink(temporary_name, dir_fd=checkout_fd)\n        except FileNotFoundError:\n            pass\n        except OSError:\n            pass\n        raise\n    finally:\n        if final_fd >= 0:\n            os.close(final_fd)\n        if staging_fd >= 0:\n            os.close(staging_fd)\n\n\n''',
)

podspec_old = '''        _write_staged(\n            checkout_fd,\n            runtime_fd,\n            "NembraTuyaPrivateConfig.podspec",\n            podspec_relative,\n            podspec,\n        )\n'''
podspec_new = '''        _write_staged(\n            checkout_fd,\n            runtime_fd,\n            "NembraTuyaPrivateConfig.podspec",\n            podspec_relative,\n            podspec,\n            lambda: _require_private_chain(\n                checkout_fd, local_secrets_fd, runtime_fd, sources_fd, module_fd\n            ),\n        )\n'''
writer = replace_once(writer, podspec_old, podspec_new, "podspec held-parent validator")
identity_old = '''        _write_staged(\n            checkout_fd,\n            module_fd,\n            "NembraTuyaPrivateIdentity.swift",\n            identity_relative,\n            swift,\n        )\n'''
identity_new = '''        _write_staged(\n            checkout_fd,\n            module_fd,\n            "NembraTuyaPrivateIdentity.swift",\n            identity_relative,\n            swift,\n            lambda: _require_private_chain(\n                checkout_fd, local_secrets_fd, runtime_fd, sources_fd, module_fd\n            ),\n        )\n'''
writer = replace_once(writer, identity_old, identity_new, "identity held-parent validator")

for retired in ("_secure_replace_beneath", "_open_relative_regular_file", "_remove_final_if_same_inode_beneath"):
    if retired in writer:
        raise SystemExit(f"retired re-resolving publication primitive survived: {retired}")
for required in (
    "_secure_replace_into_held_parent",
    "dst_dir_fd=destination_parent_fd",
    "_open_held_regular_file",
    "_require_named_file_matches_fd",
    "_remove_exact_inode_links",
    "post_publish_validator()",
):
    if required not in writer:
        raise SystemExit(f"missing descendant-rebind repair marker: {required}")
WRITER.write_text(writer, encoding="utf-8")

redteam = REDTEAM.read_text(encoding="utf-8")
redteam = replace_once(redteam, "original_publish = writer._secure_replace_beneath", "original_publish = writer._secure_replace_into_held_parent", "redteam publisher hook")
redteam = replace_once(
    redteam,
    "def adversarial_publish(root_fd: int, src: str, dst: str) -> None:",
    "def adversarial_publish(root_fd: int, src: str, destination_parent_fd: int, final_name: str) -> None:",
    "redteam publisher signature",
)
redteam = replace_once(redteam, "if not attacked and dst.endswith(\"NembraTuyaPrivateIdentity.swift\"):", "if not attacked and final_name == \"NembraTuyaPrivateIdentity.swift\":", "redteam publisher trigger")
redteam = replace_once(redteam, "original_publish(root_fd, src, dst)", "original_publish(root_fd, src, destination_parent_fd, final_name)", "redteam publisher call")
redteam = replace_once(redteam, "writer._secure_replace_beneath = adversarial_publish", "writer._secure_replace_into_held_parent = adversarial_publish", "redteam publisher install")
redteam = replace_once(redteam, "writer._secure_replace_beneath = original_publish", "writer._secure_replace_into_held_parent = original_publish", "redteam publisher restore")
redteam = replace_once(redteam, "original_open = writer._open_relative_regular_file", "original_open = writer._open_held_regular_file", "redteam open hook")
redteam = replace_once(
    redteam,
    "def adversarial_open(root_fd: int, relative_path: str) -> int:\n                nonlocal attacked, displaced_identity\n                descriptor = original_open(root_fd, relative_path)\n                if not attacked and relative_path.endswith(\"NembraTuyaPrivateIdentity.swift\"):\n                    canonical = checkout / relative_path",
    "def adversarial_open(parent_fd: int, name: str) -> int:\n                nonlocal attacked, displaced_identity\n                descriptor = original_open(parent_fd, name)\n                if not attacked and name == \"NembraTuyaPrivateIdentity.swift\":\n                    canonical = (\n                        checkout\n                        / \"LocalSecrets\"\n                        / \"TuyaRuntime\"\n                        / \"Sources\"\n                        / \"NembraTuyaPrivateConfig\"\n                        / name\n                    )",
    "redteam final-open hook",
)
redteam = replace_once(redteam, "writer._open_relative_regular_file = adversarial_open", "writer._open_held_regular_file = adversarial_open", "redteam open install")
redteam = replace_once(redteam, "writer._open_relative_regular_file = original_open", "writer._open_held_regular_file = original_open", "redteam open restore")
redteam = replace_once(
    redteam,
    '''            self.assertNotEqual(\n                canonical_bytes,\n                attacker_payload,\n                "writer returned/rejected without removing attacker bytes from the canonical identity path",\n            )\n            if not rejected:\n                self.assertIsNotNone(canonical_bytes)\n                assert canonical_bytes is not None\n                self.assertIn(\n                    key_b64.encode("ascii"),\n                    canonical_bytes,\n                    "successful provision no longer names the accepted credential identity bytes",\n                )\n                self.assertIn(secret_b64.encode("ascii"), canonical_bytes)\n\n            self.assertIsNotNone(\n                displaced_identity,\n                "diagnostic did not retain the held sealed inode under a displaced test name",\n            )\n''',
    '''            self.assertTrue(\n                rejected,\n                "writer accepted a provision after the canonical credential name was rebound",\n            )\n            self.assertNotEqual(\n                canonical_bytes,\n                attacker_payload,\n                "rejected provision left attacker bytes at the canonical identity path",\n            )\n            self.assertIsNotNone(\n                displaced_identity,\n                "diagnostic did not move the sealed inode through the attack seam",\n            )\n            assert displaced_identity is not None\n            self.assertFalse(\n                displaced_identity.exists(),\n                "rejected provision left the credential-bearing sealed inode under its displaced name",\n            )\n''',
    "redteam final-name acceptance invariant",
)
REDTEAM.write_text(redteam, encoding="utf-8")

old_digest_match = re.search(r'WRITER_SHA256="([0-9a-f]{64})"', SHELL.read_text(encoding="utf-8"))
if old_digest_match is None:
    raise SystemExit("shell writer digest fence missing")
old_digest = old_digest_match.group(1)
new_digest = hashlib.sha256(WRITER.read_bytes()).hexdigest()
shell = SHELL.read_text(encoding="utf-8")
shell = replace_once(shell, old_digest, new_digest, "shell writer digest")
SHELL.write_text(shell, encoding="utf-8")

swift = SWIFT_TEST.read_text(encoding="utf-8")
swift = replace_once(swift, old_digest, new_digest, "Swift writer digest")
swift = replace_once(
    swift,
    '''        #expect(writer.contains("dir_fd=parent_fd"))\n        #expect(writer.contains("src_dir_fd=parent_fd"))\n        #expect(writer.contains("dst_dir_fd=parent_fd"))\n''',
    '''        #expect(writer.contains("dir_fd=parent_fd"))\n        #expect(writer.contains("_secure_replace_into_held_parent"))\n        #expect(writer.contains("src_dir_fd=checkout_fd"))\n        #expect(writer.contains("dst_dir_fd=destination_parent_fd"))\n        #expect(writer.contains("_open_held_regular_file"))\n        #expect(writer.contains("_require_named_file_matches_fd"))\n        #expect(writer.contains("_remove_exact_inode_links"))\n        #expect(!writer.contains("_secure_replace_beneath"))\n        #expect(!writer.contains("_open_relative_regular_file"))\n''',
    "Swift held-parent source contract",
)
SWIFT_TEST.write_text(swift, encoding="utf-8")

print(new_digest)
