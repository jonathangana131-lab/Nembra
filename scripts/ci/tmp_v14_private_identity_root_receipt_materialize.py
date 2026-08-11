#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import hashlib

WRITER = Path("Scripts/provision_capture_tuya_identity_writer.py")
PROVISION = Path("Scripts/provision_capture_tuya_identity.sh")
BOOTSTRAP = Path("Scripts/bootstrap_capture_tuya_sdk.sh")
SWIFT = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateIdentityProvisionerCustodyTests.swift")
AUTHORITY = Path("Scripts/capture_tuya_private_identity_authority.py")
OLD_WRITER_DIGEST = "683865d663d98295a0a60498e42d579cef8b3588aae091bbafe8b4431343badc"
AUTHORITY_DIGEST = "ca8491135545ad97ef4dc8e995f307720f25e3265ded0881fbfdf37ca845e9a1"


def require(condition: bool, label: str) -> None:
    if not condition:
        raise RuntimeError(label)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    require(count == 1, f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def materialize_writer() -> str:
    writer = WRITER.read_text(encoding="utf-8")
    start = writer.index("def _write_staged(")
    end = writer.index("\ndef _decode_input", start)
    block = writer[start:end]
    block = replace_once(block, ") -> None:\n", ") -> str:\n", "_write_staged return type")
    block = replace_once(
        block,
        "        except Exception:\n            raise\n    except Exception:\n",
        "        except Exception:\n            raise\n        return hashlib.sha256(payload).hexdigest()\n    except Exception:\n",
        "_write_staged successful digest return",
    )
    writer = writer[:start] + block + writer[end:]

    writer = replace_once(
        writer,
        "def provision(checkout_fd: int, checkout_root: Path, app_key_b64: str, app_secret_b64: str) -> None:\n",
        "def provision(checkout_fd: int, checkout_root: Path, app_key_b64: str, app_secret_b64: str) -> tuple[str, str]:\n",
        "provision return type",
    )
    provision_start = writer.index("def provision(")
    provision_end = writer.index("\ndef _self_test", provision_start)
    provision = writer[provision_start:provision_end]
    first = "        _write_staged(\n            checkout_fd,\n            runtime_fd,\n            \"NembraTuyaPrivateConfig.podspec\","
    provision = replace_once(
        provision,
        first,
        "        podspec_sha256 = _write_staged(\n            checkout_fd,\n            runtime_fd,\n            \"NembraTuyaPrivateConfig.podspec\",",
        "podspec digest capture",
    )
    second = "        _write_staged(\n            checkout_fd,\n            module_fd,\n            \"NembraTuyaPrivateIdentity.swift\","
    provision = replace_once(
        provision,
        second,
        "        identity_sha256 = _write_staged(\n            checkout_fd,\n            module_fd,\n            \"NembraTuyaPrivateIdentity.swift\",",
        "identity digest capture",
    )
    sync = "        for descriptor in (module_fd, sources_fd, runtime_fd, local_secrets_fd, checkout_fd):\n            os.fsync(descriptor)\n"
    provision = replace_once(
        provision,
        sync,
        sync + "        return podspec_sha256, identity_sha256\n",
        "transaction digest return",
    )
    writer = writer[:provision_start] + provision + writer[provision_end:]

    old_main = "            provision(checkout_fd, Path(sys.argv[2]), app_key_b64, app_secret_b64)\n"
    new_main = (
        "            podspec_sha256, identity_sha256 = provision(\n"
        "                checkout_fd, Path(sys.argv[2]), app_key_b64, app_secret_b64\n"
        "            )\n"
        "            print(\n"
        "                f\"NEMBRA_PRIVATE_IDENTITY_RECEIPT_V1\\t{podspec_sha256}\\t{identity_sha256}\"\n"
        "            )\n"
    )
    writer = replace_once(writer, old_main, new_main, "writer transaction receipt output")
    WRITER.write_text(writer, encoding="utf-8")
    return hashlib.sha256(writer.encode("utf-8")).hexdigest()


def materialize_provision(writer_digest: str) -> None:
    shell = PROVISION.read_text(encoding="utf-8")
    shell = replace_once(shell, OLD_WRITER_DIGEST, writer_digest, "provision writer digest pin")
    constants = f'''WRITER_SHA256="{writer_digest}"\nAUTHORITY_HELPER="$ROOT/Scripts/capture_tuya_private_identity_authority.py"\nAUTHORITY_HELPER_SHA256="{AUTHORITY_DIGEST}"\nROOT_FD=9\n'''
    old_constants = f'''WRITER_SHA256="{writer_digest}"\nROOT_FD=9\n'''
    shell = replace_once(shell, old_constants, constants, "authority constants")

    prereq = '''[[ -f "$WRITER" && ! -L "$WRITER" ]] || {\n  builtin printf '%s\\n' 'ERROR: descriptor-bound private Tuya identity writer is missing or symlinked.' >&2\n  exit 4\n}\n[[ -x /usr/bin/python3 && -x /usr/bin/shasum && -x /usr/bin/awk ]] || {\n  builtin printf '%s\\n' 'ERROR: system Python 3 and SHA-256 tooling are required for private identity publication.' >&2\n  exit 4\n}\n'''
    replacement = prereq + '''[[ -f "$AUTHORITY_HELPER" && ! -L "$AUTHORITY_HELPER" ]] || {\n  builtin printf '%s\\n' 'ERROR: private identity authority helper is missing or symlinked.' >&2\n  exit 4\n}\n[[ -x /usr/bin/sudo ]] || {\n  builtin printf '%s\\n' 'ERROR: system sudo is required to seal private identity transaction authority.' >&2\n  exit 4\n}\n'''
    shell = replace_once(shell, prereq, replacement, "authority prerequisites")

    marker = '''unset CAPTURED_WRITER_SHA256\n\nbuiltin read -r -s -p "Tuya SmartLife SDK AppKey (input hidden): " APP_KEY\n'''
    authority_capture = '''unset CAPTURED_WRITER_SHA256\n\n# Capture and digest-pin the non-secret authority helper before privilege or\n# credential input. Root executes only these captured accepted bytes, never a\n# mutable checkout pathname.\nAUTHORITY_CAPTURE="$({ /bin/cat -- "$AUTHORITY_HELPER"; builtin printf '\\001'; })"\n[[ "$AUTHORITY_CAPTURE" == *$'\\001' ]] || {\n  unset WRITER_SOURCE AUTHORITY_CAPTURE\n  builtin printf '%s\\n' 'ERROR: could not capture private identity authority helper bytes.' >&2\n  exit 4\n}\nAUTHORITY_SOURCE="${AUTHORITY_CAPTURE%$'\\001'}"\nunset AUTHORITY_CAPTURE\nCAPTURED_AUTHORITY_SHA256="$(builtin printf '%s' "$AUTHORITY_SOURCE" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"\n[[ "$CAPTURED_AUTHORITY_SHA256" == "$AUTHORITY_HELPER_SHA256" ]] || {\n  unset WRITER_SOURCE AUTHORITY_SOURCE CAPTURED_AUTHORITY_SHA256\n  builtin printf '%s\\n' 'ERROR: private identity authority helper bytes do not match the accepted digest.' >&2\n  exit 4\n}\nunset CAPTURED_AUTHORITY_SHA256\n\n# A new attempt must revoke any older successful transaction before secrets are\n# requested. If this attempt later fails, bootstrap remains mechanically blocked\n# rather than silently falling back to stale authority.\nif ! /usr/bin/sudo /usr/bin/python3 -I -c "$AUTHORITY_SOURCE" invalidate "$ROOT"; then\n  unset WRITER_SOURCE AUTHORITY_SOURCE\n  builtin printf '%s\\n' 'ERROR: prior private identity transaction authority could not be revoked.' >&2\n  exit 4\nfi\n\nbuiltin read -r -s -p "Tuya SmartLife SDK AppKey (input hidden): " APP_KEY\n'''
    shell = replace_once(shell, marker, authority_capture, "authority capture and pre-secret revoke")

    old_invoke = '''if ! builtin printf '%s\\0%s' "$APP_KEY_B64" "$APP_SECRET_B64" | /usr/bin/python3 -I -c "$WRITER_SOURCE" "$ROOT_FD" "$ROOT"; then\n  unset APP_KEY_B64 APP_SECRET_B64 WRITER_SOURCE\n  builtin printf '%s\\n' 'ERROR: private Tuya identity publication failed closed.' >&2\n  exit 4\nfi\nunset APP_KEY_B64 APP_SECRET_B64 WRITER_SOURCE\n\nclose_root_fd\ntrap - EXIT\n'''
    new_invoke = '''if ! WRITER_RECEIPT="$(builtin printf '%s\\0%s' "$APP_KEY_B64" "$APP_SECRET_B64" | /usr/bin/python3 -I -c "$WRITER_SOURCE" "$ROOT_FD" "$ROOT")"; then\n  unset APP_KEY_B64 APP_SECRET_B64 WRITER_SOURCE AUTHORITY_SOURCE\n  builtin printf '%s\\n' 'ERROR: private Tuya identity publication failed closed; transaction authority remains revoked.' >&2\n  exit 4\nfi\nunset APP_KEY_B64 APP_SECRET_B64 WRITER_SOURCE\n[[ "$WRITER_RECEIPT" != *$'\\n'* ]] || {\n  unset WRITER_RECEIPT AUTHORITY_SOURCE\n  builtin printf '%s\\n' 'ERROR: private identity writer returned a malformed transaction receipt.' >&2\n  exit 4\n}\nIFS=$'\\t' builtin read -r RECEIPT_SCHEMA PODSPEC_SHA256 IDENTITY_SHA256 RECEIPT_EXTRA <<< "$WRITER_RECEIPT"\nunset WRITER_RECEIPT\n[[ "$RECEIPT_SCHEMA" == "NEMBRA_PRIVATE_IDENTITY_RECEIPT_V1" &&\n   "$PODSPEC_SHA256" =~ ^[0-9a-f]{64}$ &&\n   "$IDENTITY_SHA256" =~ ^[0-9a-f]{64}$ &&\n   -z "${RECEIPT_EXTRA:-}" ]] || {\n  unset RECEIPT_SCHEMA PODSPEC_SHA256 IDENTITY_SHA256 RECEIPT_EXTRA AUTHORITY_SOURCE\n  builtin printf '%s\\n' 'ERROR: private identity writer returned an invalid transaction fingerprint.' >&2\n  exit 4\n}\nunset RECEIPT_SCHEMA RECEIPT_EXTRA\n\n# Seal only non-secret hashes of the exact successful held output inodes into a\n# root-owned receipt outside the user-writable checkout. The privileged helper\n# independently re-opens and fingerprints current outputs before sealing.\nif ! /usr/bin/sudo /usr/bin/python3 -I -c "$AUTHORITY_SOURCE" seal "$ROOT" "$WRITER_SHA256" "$PODSPEC_SHA256" "$IDENTITY_SHA256" >/dev/null; then\n  unset PODSPEC_SHA256 IDENTITY_SHA256 AUTHORITY_SOURCE\n  builtin printf '%s\\n' 'ERROR: private identity transaction could not be sealed; bootstrap remains blocked.' >&2\n  exit 4\nfi\nunset PODSPEC_SHA256 IDENTITY_SHA256\nif ! /usr/bin/python3 -I -c "$AUTHORITY_SOURCE" verify "$ROOT" "$WRITER_SHA256" >/dev/null; then\n  unset AUTHORITY_SOURCE\n  builtin printf '%s\\n' 'ERROR: freshly sealed private identity transaction failed local verification.' >&2\n  exit 4\nfi\nunset AUTHORITY_SOURCE\n\nclose_root_fd\ntrap - EXIT\n'''
    shell = replace_once(shell, old_invoke, new_invoke, "writer receipt and root seal lifecycle")
    PROVISION.write_text(shell, encoding="utf-8")


def materialize_bootstrap(writer_digest: str) -> None:
    shell = BOOTSTRAP.read_text(encoding="utf-8")
    old = '''PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"\nREVIEW_ONLY=0\n'''
    new = f'''PROVENANCE_HELPER="$SCRIPT_DIR/capture_tuya_private_input_provenance.py"\nPRIVATE_IDENTITY_AUTHORITY_HELPER="$SCRIPT_DIR/capture_tuya_private_identity_authority.py"\nPRIVATE_IDENTITY_AUTHORITY_HELPER_SHA256="{AUTHORITY_DIGEST}"\nPRIVATE_IDENTITY_WRITER_SHA256="{writer_digest}"\nREVIEW_ONLY=0\n'''
    shell = replace_once(shell, old, new, "bootstrap authority constants")

    marker = '''if ! command -v pod >/dev/null 2>&1; then\n'''
    verify = '''# CocoaPods must never admit LocalSecrets identity bytes solely because they\n# occupy the canonical path. Capture and pin the verifier from accepted source,\n# then require a root-sealed receipt from the last successful transaction before\n# executable discovery or dependency resolution.\n[[ -f "$PRIVATE_IDENTITY_AUTHORITY_HELPER" && ! -L "$PRIVATE_IDENTITY_AUTHORITY_HELPER" ]] || {\n  echo "ERROR: private identity authority helper is missing from accepted source." >&2\n  exit 17\n}\nAUTHORITY_CAPTURE="$({ /bin/cat -- "$PRIVATE_IDENTITY_AUTHORITY_HELPER"; printf '\\001'; })"\n[[ "$AUTHORITY_CAPTURE" == *$'\\001' ]] || {\n  unset AUTHORITY_CAPTURE\n  echo "ERROR: private identity authority helper could not be captured." >&2\n  exit 17\n}\nAUTHORITY_SOURCE="${AUTHORITY_CAPTURE%$'\\001'}"\nunset AUTHORITY_CAPTURE\nCAPTURED_AUTHORITY_SHA256="$(printf '%s' "$AUTHORITY_SOURCE" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"\n[[ "$CAPTURED_AUTHORITY_SHA256" == "$PRIVATE_IDENTITY_AUTHORITY_HELPER_SHA256" ]] || {\n  unset AUTHORITY_SOURCE CAPTURED_AUTHORITY_SHA256\n  echo "ERROR: private identity authority helper bytes do not match accepted source." >&2\n  exit 17\n}\nunset CAPTURED_AUTHORITY_SHA256\nif ! /usr/bin/python3 -I -c "$AUTHORITY_SOURCE" verify "$REPO_ROOT" "$PRIVATE_IDENTITY_WRITER_SHA256" >/dev/null; then\n  unset AUTHORITY_SOURCE\n  echo "ERROR: private app identity is not backed by the root-sealed last successful provisioning transaction. Run Scripts/provision_capture_tuya_identity.sh successfully before bootstrap." >&2\n  exit 17\nfi\nunset AUTHORITY_SOURCE\n\nif ! command -v pod >/dev/null 2>&1; then\n'''
    shell = replace_once(shell, marker, verify, "bootstrap pre-CocoaPods authority verify")
    BOOTSTRAP.write_text(shell, encoding="utf-8")


def materialize_swift(writer_digest: str) -> None:
    swift = SWIFT.read_text(encoding="utf-8")
    swift = swift.replace(OLD_WRITER_DIGEST, writer_digest)
    old = '        #expect(writer.contains("_unlink_owned_relative_inode_if_named"))\n'
    new = '        #expect(!writer.contains("_unlink_owned_relative_inode_if_named"))\n        #expect(!writer.contains("_unlink_owned_inode_if_named"))\n'
    swift = replace_once(swift, old, new, "obsolete pathname helper contract")

    source_marker = '''        let writer = try String(\n            contentsOf: repositoryRoot.appendingPathComponent("Scripts/provision_capture_tuya_identity_writer.py"),\n            encoding: .utf8\n        )\n\n'''
    source_addition = source_marker + '''        let authority = try String(\n            contentsOf: repositoryRoot.appendingPathComponent("Scripts/capture_tuya_private_identity_authority.py"),\n            encoding: .utf8\n        )\n        let bootstrap = try String(\n            contentsOf: repositoryRoot.appendingPathComponent("Scripts/bootstrap_capture_tuya_sdk.sh"),\n            encoding: .utf8\n        )\n\n'''
    swift = replace_once(swift, source_marker, source_addition, "authority source fixtures")
    digest_expect = f'        #expect(shell.contains("WRITER_SHA256=\\"{writer_digest}\\""))\n'
    require(digest_expect in swift, "writer digest expectation missing after repin")
    swift = swift.replace(
        digest_expect,
        digest_expect
        + f'        #expect(shell.contains("AUTHORITY_HELPER_SHA256=\\"{AUTHORITY_DIGEST}\\""))\n'
        + '        #expect(shell.contains("invalidate \\"$ROOT\\""))\n'
        + '        #expect(shell.contains("seal \\"$ROOT\\" \\"$WRITER_SHA256\\" \\"$PODSPEC_SHA256\\" \\"$IDENTITY_SHA256\\""))\n'
        + '        #expect(shell.contains("verify \\"$ROOT\\" \\"$WRITER_SHA256\\""))\n',
        1,
    )
    marker = '        #expect(writer.contains("hashlib.sha256"))\n'
    addition = marker + '''        #expect(writer.contains("NEMBRA_PRIVATE_IDENTITY_RECEIPT_V1"))\n        #expect(authority.contains("nembra-private-identity-authority-v1"))\n        #expect(authority.contains("/private/tmp/nembra-capture-private-identity-authority-v1"))\n        #expect(authority.contains("SUDO_UID"))\n        #expect(authority.contains("_invalidate_current_subject"))\n        #expect(authority.contains("_seal_current_subject"))\n        #expect(authority.contains("_verify_current_subject"))\n        let bootstrapVerify = bootstrap.range(of: "verify \\\"$REPO_ROOT\\\" \\\"$PRIVATE_IDENTITY_WRITER_SHA256\\\"")\n        let podDiscovery = bootstrap.range(of: "command -v pod")\n        #expect(bootstrapVerify != nil)\n        #expect(podDiscovery != nil)\n        if let bootstrapVerify, let podDiscovery {\n            #expect(bootstrapVerify.lowerBound < podDiscovery.lowerBound)\n        }\n'''
    swift = replace_once(swift, marker, addition, "authority source contracts")

    fixture_marker = '''        let sourceWriter = repositoryRoot.appendingPathComponent("Scripts/provision_capture_tuya_identity_writer.py")\n        let targetWriter = scripts.appendingPathComponent("provision_capture_tuya_identity_writer.py")\n        try FileManager.default.copyItem(at: sourceWriter, to: targetWriter)\n        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetWriter.path)\n        return (root, targetScript)\n'''
    fixture_new = '''        let sourceWriter = repositoryRoot.appendingPathComponent("Scripts/provision_capture_tuya_identity_writer.py")\n        let targetWriter = scripts.appendingPathComponent("provision_capture_tuya_identity_writer.py")\n        try FileManager.default.copyItem(at: sourceWriter, to: targetWriter)\n        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetWriter.path)\n\n        let sourceAuthority = repositoryRoot.appendingPathComponent("Scripts/capture_tuya_private_identity_authority.py")\n        let targetAuthority = scripts.appendingPathComponent("capture_tuya_private_identity_authority.py")\n        try FileManager.default.copyItem(at: sourceAuthority, to: targetAuthority)\n        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetAuthority.path)\n\n        // Unit fixtures exercise the unprivileged writer/shell custody paths.\n        // Production source contracts above separately require the real root\n        // revocation/seal/verify commands; only this copied fixture replaces\n        // those three privileged calls so Xcode tests never request sudo.\n        var fixtureShell = try String(contentsOf: targetScript, encoding: .utf8)\n        fixtureShell = fixtureShell.replacingOccurrences(\n            of: "/usr/bin/sudo /usr/bin/python3 -I -c \\\"$AUTHORITY_SOURCE\\\" invalidate \\\"$ROOT\\\"",\n            with: "/usr/bin/true"\n        )\n        fixtureShell = fixtureShell.replacingOccurrences(\n            of: "/usr/bin/sudo /usr/bin/python3 -I -c \\\"$AUTHORITY_SOURCE\\\" seal \\\"$ROOT\\\" \\\"$WRITER_SHA256\\\" \\\"$PODSPEC_SHA256\\\" \\\"$IDENTITY_SHA256\\\" >/dev/null",\n            with: "/usr/bin/true"\n        )\n        fixtureShell = fixtureShell.replacingOccurrences(\n            of: "/usr/bin/python3 -I -c \\\"$AUTHORITY_SOURCE\\\" verify \\\"$ROOT\\\" \\\"$WRITER_SHA256\\\" >/dev/null",\n            with: "/usr/bin/true"\n        )\n        try Data(fixtureShell.utf8).write(to: targetScript)\n        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: targetScript.path)\n        return (root, targetScript)\n'''
    swift = replace_once(swift, fixture_marker, fixture_new, "test fixture authority stubs")
    SWIFT.write_text(swift, encoding="utf-8")


def main() -> None:
    authority_digest = hashlib.sha256(AUTHORITY.read_bytes()).hexdigest()
    require(authority_digest == AUTHORITY_DIGEST, f"authority helper digest drifted: {authority_digest}")
    writer_digest = materialize_writer()
    materialize_provision(writer_digest)
    materialize_bootstrap(writer_digest)
    materialize_swift(writer_digest)
    print(f"writer_sha256={writer_digest}")
    print(f"authority_sha256={authority_digest}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"::error title=Private identity authority materializer::{type(exc).__name__}: {exc}")
        raise
