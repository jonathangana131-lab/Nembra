#!/usr/bin/env python3
"""Real-macOS feasibility witness for a root-custodied accepted source snapshot.

Validation only. The fixture uses synthetic public source bytes. It proves that a
field-owned source tree can be accepted, copied into a root-custodied read-only
snapshot, mutated/replaced afterward by the real field identity, while the current
#3142 dedicated-build exec primitive still consumes only the accepted snapshot.
No LocalSecrets, signing identity, Xcode build, device, Bluetooth, or scooter is used.
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
from types import ModuleType
from typing import Iterable, Sequence


class ValidationError(RuntimeError):
    pass


ACCEPTED_TEXT = "accepted-source-v1\n"
MUTATED_TEXT = "field-replaced-source-v2\n"


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
        detail = (completed.stderr or "") if isinstance(completed.stderr, str) else ""
        raise ValidationError(
            f"command failed ({completed.returncode}): {list(argv)!r}"
            + (f" stderr={detail[-800:]!r}" if detail else "")
        )
    return completed


def _fingerprint_tree(root: Path) -> str:
    records: list[tuple[str, str, str]] = []
    if not root.is_dir() or root.is_symlink():
        raise ValidationError("tree fingerprint root is not one real directory")
    for current_raw, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_raw)
        relative_current = current.relative_to(root)
        for name in sorted(list(directory_names)):
            candidate = current / name
            relative = str((relative_current / name).as_posix())
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                directory_names.remove(name)
                target = os.readlink(candidate)
                records.append((relative, "L", target))
            elif stat.S_ISDIR(metadata.st_mode):
                records.append((relative, "D", ""))
            else:
                raise ValidationError(f"tree contains invalid directory entry: {candidate}")
        for name in sorted(file_names):
            candidate = current / name
            relative = str((relative_current / name).as_posix())
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                records.append((relative, "L", os.readlink(candidate)))
            elif stat.S_ISREG(metadata.st_mode):
                digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
                records.append((relative, "F", digest))
            else:
                raise ValidationError(f"tree contains invalid file entry: {candidate}")
    canonical = json.dumps(records, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def _assert_internal_relative_symlink(root: Path, link: Path) -> None:
    if not link.is_symlink():
        raise ValidationError(f"expected symlink is missing: {link}")
    raw_target = os.readlink(link)
    target_path = Path(raw_target)
    if target_path.is_absolute():
        raise ValidationError("snapshot symlink became absolute")
    lexical = Path(os.path.normpath(str(link.parent.relative_to(root) / target_path)))
    if lexical.parts and lexical.parts[0] == "..":
        raise ValidationError("snapshot symlink escapes the accepted source root")
    resolved = (link.parent / target_path).resolve(strict=True)
    resolved.relative_to(root.resolve(strict=True))


def _make_field_source(root: Path, *, uid: int, gid: int) -> tuple[Path, Path]:
    source = root / "field-source"
    package = source / "Sources" / "CaptureFixture"
    package.mkdir(parents=True)
    primary = package / "Accepted.swift"
    primary.write_text(ACCEPTED_TEXT, encoding="utf-8")
    alias = package / "Alias.swift"
    alias.symlink_to("Accepted.swift")
    (source / "Package.swift").write_text("// synthetic validation package\n", encoding="utf-8")

    directories: list[Path] = []
    regular_files: list[Path] = []
    symlinks: list[Path] = []
    for current_raw, directory_names, file_names in os.walk(source, topdown=True, followlinks=False):
        current = Path(current_raw)
        directories.append(current)
        for name in list(directory_names):
            candidate = current / name
            if candidate.is_symlink():
                directory_names.remove(name)
                symlinks.append(candidate)
        for name in file_names:
            candidate = current / name
            if candidate.is_symlink():
                symlinks.append(candidate)
            else:
                regular_files.append(candidate)
    for path in directories:
        os.chown(path, uid, gid)
        os.chmod(path, 0o755)
        _run(["/bin/chmod", "-N", str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for path in regular_files:
        os.chown(path, uid, gid)
        os.chmod(path, 0o644)
        _run(["/bin/chmod", "-N", str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for path in symlinks:
        os.lchown(path, uid, gid)
    return source, primary


def _seal_snapshot(source: Path, snapshot: Path) -> None:
    if snapshot.exists() or snapshot.is_symlink():
        raise ValidationError("snapshot destination already exists")
    _run(
        ["/usr/bin/ditto", "--noacl", str(source), str(snapshot)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    directories: list[Path] = []
    regular_files: list[Path] = []
    symlinks: list[Path] = []
    for current_raw, directory_names, file_names in os.walk(snapshot, topdown=True, followlinks=False):
        current = Path(current_raw)
        metadata = current.lstat()
        if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise ValidationError(f"snapshot contains non-real directory ancestry: {current}")
        directories.append(current)
        for name in list(directory_names):
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                directory_names.remove(name)
                symlinks.append(candidate)
            elif not stat.S_ISDIR(metadata.st_mode):
                raise ValidationError(f"snapshot directory entry changed type: {candidate}")
        for name in file_names:
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                symlinks.append(candidate)
            elif stat.S_ISREG(metadata.st_mode):
                regular_files.append(candidate)
            else:
                raise ValidationError(f"snapshot contains unsupported file type: {candidate}")

    for path in regular_files:
        os.chown(path, 0, 0)
        _run(["/bin/chmod", "-N", str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        os.chmod(path, 0o444)
    for path in symlinks:
        os.lchown(path, 0, 0)
    for path in sorted(directories, key=lambda item: len(item.parts), reverse=True):
        os.chown(path, 0, 0)
        _run(["/bin/chmod", "-N", str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        os.chmod(path, 0o555)


def _assert_snapshot_custody(snapshot: Path) -> None:
    for current_raw, directory_names, file_names in os.walk(snapshot, topdown=True, followlinks=False):
        current = Path(current_raw)
        metadata = current.lstat()
        if metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o555:
            raise ValidationError(f"snapshot directory custody is not root:0555: {current}")
        acl = _run(
            ["/bin/ls", "-lde", str(current)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        ).stdout.splitlines()
        if len(acl) != 1:
            raise ValidationError(f"snapshot directory carries extended ACL authority: {current}")
        for name in list(directory_names):
            candidate = current / name
            if candidate.is_symlink():
                directory_names.remove(name)
        for name in file_names:
            candidate = current / name
            metadata = candidate.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                if metadata.st_uid != 0:
                    raise ValidationError(f"snapshot symlink is not root-owned: {candidate}")
                continue
            if metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o444:
                raise ValidationError(f"snapshot file custody is not root:0444: {candidate}")
            acl = _run(
                ["/bin/ls", "-le", str(candidate)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            ).stdout.splitlines()
            if len(acl) != 1:
                raise ValidationError(f"snapshot file carries extended ACL authority: {candidate}")


def _field_replace_source(helper: ModuleType, field: pwd.struct_passwd, groups: Sequence[int], path: Path) -> None:
    source = (
        "import os,sys; from pathlib import Path; "
        "p=Path(sys.argv[1]); q=p.with_name('field-replacement.tmp'); "
        f"q.write_text({MUTATED_TEXT!r}, encoding='utf-8'); os.replace(q,p)"
    )
    completed = subprocess.run(
        ["/usr/bin/python3", "-I", "-c", source, str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        **helper._structured_credentials(field.pw_uid, field.pw_gid, groups),
    )
    if completed.returncode != 0:
        raise ValidationError(f"field identity could not exercise accepted-source replacement gap: {completed.stderr[-800:]!r}")


def _run_field_attack(
    helper: ModuleType,
    field: pwd.struct_passwd,
    groups: Sequence[int],
    *,
    source: str,
    argv: Iterable[Path],
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["/usr/bin/python3", "-I", "-c", source, *[str(value) for value in argv]],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        **helper._structured_credentials(field.pw_uid, field.pw_gid, groups),
    )


def _require_permission_denied(completed: subprocess.CompletedProcess[str], label: str) -> None:
    if completed.returncode == 0:
        raise ValidationError(f"{label} unexpectedly succeeded")
    detail = (completed.stderr or "")[-1000:]
    if "PermissionError" not in detail and "Permission denied" not in detail:
        raise ValidationError(f"{label} failed for a non-permission reason: {detail!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--field-user", required=True)
    parser.add_argument("--production-helper", required=True, type=Path)
    parser.add_argument("--production-parent", required=True)
    args = parser.parse_args()

    if sys.platform != "darwin" or os.geteuid() != 0:
        raise ValidationError("source snapshot validation requires root on real macOS")
    field = pwd.getpwnam(args.field_user)
    if field.pw_uid <= 0 or field.pw_gid <= 0:
        raise ValidationError("field identity must be one non-root local account")
    field_groups = tuple(sorted(set(os.getgrouplist(field.pw_name, field.pw_gid))))
    if any(value <= 0 for value in field_groups):
        raise ValidationError("field group vector contains root or invalid authority")

    helper = _load(args.production_helper, "nembra_source_snapshot_current_production_helper")
    required = (
        "_structured_credentials",
        "_choose_ephemeral_id",
        "_create_local_build_identity",
        "_attest_build_identity_groups",
        "_run_exec_bound_build",
        "_build_environment",
        "_remove_local_build_identity",
    )
    missing = [name for name in required if not callable(getattr(helper, name, None))]
    if missing:
        raise ValidationError(f"current production helper is missing snapshot-consumer primitives: {missing!r}")

    test_root = Path(tempfile.mkdtemp(prefix="nembra-source-snapshot.", dir="/private/tmp"))
    os.chown(test_root, 0, 0)
    os.chmod(test_root, 0o711)
    build_uid: int | None = None
    build_name = f"nembrasource{os.getpid()}"
    build_home: Path | None = None
    result: dict[str, object] = {}
    try:
        field_source, field_primary = _make_field_source(
            test_root, uid=field.pw_uid, gid=field.pw_gid
        )
        accepted_tree = _fingerprint_tree(field_source)

        snapshot = test_root / "accepted-source-snapshot"
        _seal_snapshot(field_source, snapshot)
        _assert_snapshot_custody(snapshot)
        snapshot_primary = snapshot / "Sources" / "CaptureFixture" / "Accepted.swift"
        snapshot_alias = snapshot_primary.with_name("Alias.swift")
        _assert_internal_relative_symlink(snapshot, snapshot_alias)
        snapshot_tree = _fingerprint_tree(snapshot)
        if snapshot_tree != accepted_tree:
            raise ValidationError("root-custodied snapshot does not equal the accepted source subject")
        if snapshot_primary.read_text(encoding="utf-8") != ACCEPTED_TEXT:
            raise ValidationError("accepted snapshot primary bytes are wrong before attack")
        if snapshot_alias.read_text(encoding="utf-8") != ACCEPTED_TEXT:
            raise ValidationError("accepted snapshot internal symlink does not resolve accepted bytes")

        # Attack after acceptance: the real field identity replaces the live source.
        _field_replace_source(helper, field, field_groups, field_primary)
        live_after_attack = _fingerprint_tree(field_source)
        if live_after_attack == accepted_tree:
            raise ValidationError("field replacement did not change the live accepted-source fingerprint")
        if field_primary.read_text(encoding="utf-8") != MUTATED_TEXT:
            raise ValidationError("field replacement did not materialize the intended attack bytes")
        if _fingerprint_tree(snapshot) != accepted_tree:
            raise ValidationError("accepted snapshot changed after live field-source replacement")
        if snapshot_primary.read_text(encoding="utf-8") != ACCEPTED_TEXT:
            raise ValidationError("accepted snapshot content followed the mutable live source")

        field_append = _run_field_attack(
            helper,
            field,
            field_groups,
            source="from pathlib import Path; import sys; Path(sys.argv[1]).open('a').write('attack')",
            argv=[snapshot_primary],
        )
        _require_permission_denied(field_append, "field append against root-custodied source snapshot")
        field_rename = _run_field_attack(
            helper,
            field,
            field_groups,
            source="from pathlib import Path; import sys; p=Path(sys.argv[1]); p.rename(p.with_name('Replaced.swift'))",
            argv=[snapshot_primary],
        )
        _require_permission_denied(field_rename, "field rename against root-custodied source snapshot")
        if _fingerprint_tree(snapshot) != accepted_tree:
            raise ValidationError("field mutation attacks changed the accepted snapshot")

        build_uid = int(helper._choose_ephemeral_id())
        if build_uid == field.pw_uid or build_uid in field_groups:
            raise ValidationError("ephemeral build UID collides with field identity authority")
        build_home = Path(f"/private/tmp/nembra-source-snapshot-home.{build_uid}.{os.getpid()}")
        build_home.mkdir(mode=0o700)
        helper._create_local_build_identity(build_name, build_uid, build_uid, build_home)
        os.chown(build_home, build_uid, build_uid)
        os.chmod(build_home, 0o700)
        environment = helper._build_environment(build_name, build_home)
        temp = build_home / "tmp"
        os.chown(temp, build_uid, build_uid)
        os.chmod(temp, 0o700)
        baseline = helper._attest_build_identity_groups(
            build_name,
            build_uid,
            build_uid,
            field_groups,
            environment,
            snapshot,
        )

        consumer_source = (
            "from pathlib import Path; import sys; "
            "primary=Path(sys.argv[1]); alias=Path(sys.argv[2]); expected=sys.argv[3]; "
            "assert primary.read_text(encoding='utf-8') == expected; "
            "assert alias.read_text(encoding='utf-8') == expected"
        )
        consumer = helper._run_exec_bound_build(
            [
                "/usr/bin/python3",
                "-I",
                "-c",
                consumer_source,
                str(snapshot_primary),
                str(snapshot_alias),
                ACCEPTED_TEXT,
            ],
            name=build_name,
            uid=build_uid,
            gid=build_uid,
            baseline_groups=baseline,
            environment=environment,
            cwd=snapshot,
        )
        if consumer.returncode != 0:
            raise ValidationError(
                f"current dedicated-build exec primitive could not consume accepted root snapshot: rc={consumer.returncode}"
            )

        build_write = helper._run_exec_bound_build(
            [
                "/usr/bin/python3",
                "-I",
                "-c",
                "from pathlib import Path; import sys; Path(sys.argv[1]).open('a').write('build-attack')",
                str(snapshot_primary),
            ],
            name=build_name,
            uid=build_uid,
            gid=build_uid,
            baseline_groups=baseline,
            environment=environment,
            cwd=snapshot,
        )
        if build_write.returncode == 0:
            raise ValidationError("dedicated build identity retained write authority over accepted source snapshot")
        if _fingerprint_tree(snapshot) != accepted_tree:
            raise ValidationError("dedicated build write attack changed the accepted source snapshot")

        result = {
            "schema": 1,
            "productionParent": args.production_parent,
            "acceptedSourceTreeSHA256": accepted_tree,
            "snapshotTreeSHA256": _fingerprint_tree(snapshot),
            "liveSourceAfterAttackSHA256": live_after_attack,
            "fieldSourceReplacementSucceeded": True,
            "fieldSnapshotAppendDenied": True,
            "fieldSnapshotRenameDenied": True,
            "dedicatedConsumerReadAcceptedSnapshot": True,
            "dedicatedConsumerReadInternalSymlink": True,
            "dedicatedSnapshotWriteDenied": True,
            "snapshotRootOwnedReadOnly": True,
            "publicSyntheticSourceOnly": True,
            "privateTuyaInputsUsed": False,
            "appleSigningIdentityUsed": False,
            "xcodeBuildUsed": False,
            "deviceUsed": False,
            "bluetoothUsed": False,
            "physicalAuthorityCreated": False,
        }
    finally:
        if build_uid is not None:
            try:
                helper._remove_local_build_identity(build_name, build_uid, require_absent=True)
            finally:
                if build_home is not None:
                    shutil.rmtree(build_home, ignore_errors=True)
        shutil.rmtree(test_root, ignore_errors=True)

    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
