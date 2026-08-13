#!/usr/bin/env python3
"""Real-macOS feasibility witness for a reversible private-Tuya read lease.

This is validation-only. It uses synthetic private bytes and one fresh local build
identity. It never touches LocalSecrets, Apple signing, devices, Bluetooth, or a
real Tuya credential.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from types import ModuleType
from typing import Iterable, Sequence


class ValidationError(RuntimeError):
    pass


DIRECTORY_RIGHTS = "list,search,readattr,readextattr,readsecurity"
FILE_RIGHTS = "read,readattr,readextattr,readsecurity"


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValidationError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _run(argv: Sequence[str], *, check: bool = True, **kwargs) -> subprocess.CompletedProcess:
    completed = subprocess.run(list(argv), **kwargs)
    if check and completed.returncode != 0:
        raise ValidationError(f"command failed ({completed.returncode}): {list(argv)!r}")
    return completed


def _acl_listing(path: Path) -> str:
    return _run(
        ["/bin/ls", "-lde", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ).stdout


def _chmod_acl(flag: str, ace: str, path: Path) -> None:
    _run(
        ["/bin/chmod", flag, ace, str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def _real_tree_paths(root: Path) -> tuple[tuple[Path, ...], tuple[Path, ...]]:
    directories: list[Path] = []
    files: list[Path] = []
    for current_raw, names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_raw)
        metadata = current.lstat()
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise ValidationError(f"synthetic private root contains non-real directory: {current}")
        directories.append(current)
        for name in list(names):
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                names.remove(name)
                continue
            if not stat.S_ISDIR(metadata.st_mode):
                raise ValidationError(f"synthetic private directory changed type: {candidate}")
        for name in file_names:
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                continue
            if not stat.S_ISREG(metadata.st_mode):
                raise ValidationError(f"synthetic private file changed type: {candidate}")
            files.append(candidate)
    return tuple(sorted(directories, key=str)), tuple(sorted(files, key=str))


def _set_field_custody(root: Path, *, uid: int, gid: int) -> None:
    directories, files = _real_tree_paths(root)
    symlinks: list[Path] = []
    for current_raw, _, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_raw)
        for name in file_names:
            candidate = current / name
            if candidate.is_symlink():
                symlinks.append(candidate)
    for path in directories:
        os.chown(path, uid, gid)
        os.chmod(path, 0o700)
        _run(["/bin/chmod", "-N", str(path)])
    for path in files:
        os.chown(path, uid, gid)
        os.chmod(path, 0o600)
        _run(["/bin/chmod", "-N", str(path)])
    for path in symlinks:
        os.lchown(path, uid, gid)


def _build_credentials(helper: ModuleType, uid: int, gid: int) -> dict[str, object]:
    credentials = helper._structured_credentials(uid, gid, ())
    if not isinstance(credentials, dict):
        raise ValidationError("production structured credentials helper returned no mapping")
    return credentials


def _run_as_build(
    helper: ModuleType,
    *,
    uid: int,
    gid: int,
    source: str,
    argv: Sequence[str],
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["/usr/bin/python3", "-I", "-c", source, *[str(value) for value in argv]],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C"},
        **_build_credentials(helper, uid, gid),
    )


def _require_denied(completed: subprocess.CompletedProcess[str], label: str) -> None:
    if completed.returncode == 0:
        raise ValidationError(f"build identity unexpectedly gained {label} authority")
    if "PermissionError" not in completed.stderr and "Permission denied" not in completed.stderr:
        raise ValidationError(
            f"{label} probe failed for an unexpected reason: rc={completed.returncode} stderr={completed.stderr[-600:]!r}"
        )


def _make_synthetic_private_tree(root: Path) -> tuple[Path, Path, Path]:
    sdk = root / "LocalSecrets" / "TuyaSDK"
    runtime_sources = (
        root
        / "LocalSecrets"
        / "TuyaRuntime"
        / "Sources"
        / "NembraTuyaPrivateConfig"
    )
    build = sdk / "Build" / "ThingSmartCryption.framework"
    build.mkdir(parents=True)
    runtime_sources.mkdir(parents=True)

    (sdk / "ThingSmartCryption.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
    (build / "ThingSmartCryption").write_bytes(b"synthetic-private-sdk\n")
    runtime = root / "LocalSecrets" / "TuyaRuntime"
    (runtime / "NembraTuyaPrivateConfig.podspec").write_text("Pod::Spec.new do |s|\nend\n", encoding="utf-8")
    secret = runtime_sources / "NembraTuyaPrivateConfig.swift"
    secret.write_text('let syntheticAppKey = "VALIDATION_ONLY_SENTINEL"\n', encoding="utf-8")
    alias = runtime_sources / "Alias.swift"
    alias.symlink_to("NembraTuyaPrivateConfig.swift")
    return sdk, runtime, secret


def _lease_entries(build_name: str, root: Path) -> tuple[tuple[Path, str], ...]:
    directories, files = _real_tree_paths(root)
    entries: list[tuple[Path, str]] = []
    for path in directories:
        entries.append((path, f"{build_name} allow {DIRECTORY_RIGHTS}"))
    for path in files:
        entries.append((path, f"{build_name} allow {FILE_RIGHTS}"))
    return tuple(entries)


def _read_probe_source() -> str:
    return (
        "from pathlib import Path; import sys; "
        "p=Path(sys.argv[1]); data=p.read_text(encoding='utf-8'); "
        "assert 'VALIDATION_ONLY_SENTINEL' in data; sys.stdout.write(str(len(data)))"
    )


def _mutation_probe_source(kind: str) -> str:
    if kind == "append":
        return "from pathlib import Path; import sys; Path(sys.argv[1]).open('a').write('x')"
    if kind == "create":
        return "from pathlib import Path; import sys; (Path(sys.argv[1])/'Injected.swift').write_text('x')"
    if kind == "unlink":
        return "from pathlib import Path; import sys; Path(sys.argv[1]).unlink()"
    if kind == "rename":
        return "from pathlib import Path; import sys; Path(sys.argv[1]).rename(Path(sys.argv[1]).with_name('Renamed.swift'))"
    if kind == "chmod":
        return "import os,sys; os.chmod(sys.argv[1],0o644)"
    raise AssertionError(kind)


def _prove_attrib_delivery(
    accepted_guard: ModuleType,
    *,
    target: Path,
    build_ace: str,
) -> int:
    select_module = accepted_guard.select
    if not hasattr(select_module, "KQ_NOTE_ATTRIB"):
        raise ValidationError("accepted vnode primitive exposes no KQ_NOTE_ATTRIB")
    descriptor = os.open(
        target,
        os.O_RDONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0),
    )
    backend = accepted_guard.KqueueVnodeBackend()
    try:
        backend.register(descriptor)
        if backend.events(0):
            raise ValidationError("accepted vnode watcher had stale events before ACL mutation")
        _chmod_acl("-a", build_ace, target)
        deadline = time.monotonic() + 4.0
        observed = 0
        while time.monotonic() < deadline and not observed:
            for event in backend.events(0.10):
                observed |= int(getattr(event, "fflags", 0))
        if not (observed & int(select_module.KQ_NOTE_ATTRIB)):
            raise ValidationError(f"ACL removal produced no KQ_NOTE_ATTRIB evidence: flags=0x{observed:x}")
        _chmod_acl("+a", build_ace, target)
        # The re-add is another authority-relevant metadata mutation. Drain it so
        # the later lease semantics are tested from a clean watcher boundary.
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline:
            if backend.events(0.05):
                break
        return observed
    finally:
        backend.close()
        os.close(descriptor)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--field-user", required=True)
    parser.add_argument("--production-helper", required=True, type=Path)
    parser.add_argument("--accepted-attrib-guard", required=True, type=Path)
    parser.add_argument("--accepted-vnode-head", required=True)
    args = parser.parse_args()

    if sys.platform != "darwin" or os.geteuid() != 0:
        raise ValidationError("real read-lease validation requires root on macOS")
    field = pwd.getpwnam(args.field_user)
    if field.pw_uid <= 0:
        raise ValidationError("field owner must be one non-root account")

    helper = _load(args.production_helper, "nembra_read_lease_production_identity")
    accepted_guard = _load(args.accepted_attrib_guard, "nembra_read_lease_accepted_attrib_guard")
    guard_source = args.accepted_attrib_guard.read_text(encoding="utf-8")
    if guard_source.count('"KQ_NOTE_ATTRIB"') < 1 or "select.KQ_NOTE_ATTRIB" not in guard_source:
        raise ValidationError("accepted vnode source does not carry KQ_NOTE_ATTRIB capability/subscription")

    test_root = Path(tempfile.mkdtemp(prefix="nembra-private-read-lease.", dir="/private/tmp"))
    build_name = f"nembralease{os.getpid()}"
    build_uid: int | None = None
    lease: tuple[tuple[Path, str], ...] = ()
    before_acl: dict[str, str] = {}
    result: dict[str, object] = {}
    try:
        sdk, runtime, secret = _make_synthetic_private_tree(test_root)
        _set_field_custody(test_root, uid=field.pw_uid, gid=field.pw_gid)
        alias = secret.with_name("Alias.swift")
        runtime_sources = secret.parent

        build_uid = int(helper._choose_ephemeral_id())
        build_home = Path(f"/private/tmp/nembra-read-lease-home.{build_uid}")
        build_home.mkdir(mode=0o700)
        try:
            helper._create_local_build_identity(build_name, build_uid, build_uid, build_home)

            denied_before = _run_as_build(
                helper,
                uid=build_uid,
                gid=build_uid,
                source=_read_probe_source(),
                argv=[secret],
            )
            _require_denied(denied_before, "pre-lease private read")

            lease = _lease_entries(build_name, test_root)
            before_acl = {str(path): _acl_listing(path) for path, _ in lease}
            for path, ace in lease:
                _chmod_acl("+a", ace, path)

            read_secret = _run_as_build(
                helper, uid=build_uid, gid=build_uid, source=_read_probe_source(), argv=[secret]
            )
            if read_secret.returncode != 0:
                raise ValidationError(f"leased build identity could not read secret file: {read_secret.stderr[-600:]!r}")
            read_alias = _run_as_build(
                helper, uid=build_uid, gid=build_uid, source=_read_probe_source(), argv=[alias]
            )
            if read_alias.returncode != 0:
                raise ValidationError(f"leased build identity could not read internal symlink target: {read_alias.stderr[-600:]!r}")

            mutation_cases = (
                ("append", secret),
                ("create", runtime_sources),
                ("unlink", secret),
                ("rename", secret),
                ("chmod", secret),
            )
            denied_mutations: list[str] = []
            for kind, subject in mutation_cases:
                completed = _run_as_build(
                    helper,
                    uid=build_uid,
                    gid=build_uid,
                    source=_mutation_probe_source(kind),
                    argv=[subject],
                )
                _require_denied(completed, kind)
                denied_mutations.append(kind)

            secret_ace = next(ace for path, ace in lease if path == secret)
            attrib_flags = _prove_attrib_delivery(
                accepted_guard, target=secret, build_ace=secret_ace
            )

            # Content and ownership must remain field-authoritative after the ACL
            # metadata attack/re-add used for KQ_NOTE_ATTRIB evidence.
            if secret.read_text(encoding="utf-8") != 'let syntheticAppKey = "VALIDATION_ONLY_SENTINEL"\n':
                raise ValidationError("synthetic private content changed during read-lease validation")
            if secret.stat().st_uid != field.pw_uid:
                raise ValidationError("read lease changed private-input ownership")

            for path, ace in reversed(lease):
                _chmod_acl("-a", ace, path)
            for path, _ in lease:
                after = _acl_listing(path)
                if after != before_acl[str(path)]:
                    raise ValidationError(f"ACL lease did not restore exact pre-lease listing: {path}")
            lease = ()

            denied_after = _run_as_build(
                helper,
                uid=build_uid,
                gid=build_uid,
                source=_read_probe_source(),
                argv=[secret],
            )
            _require_denied(denied_after, "post-revoke private read")

            result = {
                "schema": 1,
                "acceptedVnodeHead": args.accepted_vnode_head,
                "fieldUID": field.pw_uid,
                "buildUID": build_uid,
                "preLeaseReadDenied": True,
                "leaseReadSucceeded": True,
                "internalSymlinkReadSucceeded": True,
                "deniedMutations": denied_mutations,
                "attribMutationObserved": True,
                "attribFlagsHex": f"0x{attrib_flags:x}",
                "postRevokeReadDenied": True,
                "exactAclListingRestored": True,
                "syntheticPrivateTreeSHA256": hashlib.sha256(
                    b"synthetic-private-sdk\nlet syntheticAppKey = VALIDATION_ONLY_SENTINEL"
                ).hexdigest(),
                "physicalTuyaSecretsUsed": False,
                "xcodeUsed": False,
                "deviceUsed": False,
            }
        finally:
            if lease:
                for path, ace in reversed(lease):
                    try:
                        _chmod_acl("-a", ace, path)
                    except Exception:
                        pass
            if build_uid is not None:
                helper._remove_local_build_identity(build_name, build_uid, require_absent=True)
            shutil.rmtree(build_home, ignore_errors=True)
    finally:
        shutil.rmtree(test_root, ignore_errors=True)

    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
