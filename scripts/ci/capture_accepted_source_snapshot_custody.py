#!/usr/bin/env python3
"""Root-custodied accepted source snapshot for one Capture compiler execution.

This helper replaces live-field-tree ACL mutation. Root first admits exact tracked Git
bytes plus the independently reviewed generated/private input manifest into a private
snapshot. When the accepted build-origin helper exposes the fresh dedicated build GID,
the snapshot is sealed root:<build-gid>, mapped into the guarded command, and used as
the compiler cwd. The field checkout is never granted to the build identity.
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
from typing import Callable, Sequence

EXPECTED_GENERATED_SUBJECTS = (
    "Podfile.lock",
    "NembraCapture.xcworkspace",
    "Pods",
    "LocalSecrets/TuyaSDK",
    "LocalSecrets/TuyaRuntime",
)
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class AcceptedSourceSnapshotCustodyError(RuntimeError):
    pass


def _absolute(path: Path) -> Path:
    if not path.is_absolute():
        raise AcceptedSourceSnapshotCustodyError(f"snapshot authority path is not absolute: {path}")
    if "\n" in str(path) or "\t" in str(path):
        raise AcceptedSourceSnapshotCustodyError("snapshot authority path has invalid separator")
    return Path(os.path.abspath(str(path)))


def _require_private_tmp() -> Path:
    root = Path("/private/tmp")
    metadata = root.lstat()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise AcceptedSourceSnapshotCustodyError("/private/tmp is not one real directory")
    return root


def _require_snapshot_helper(namespace: dict[str, object]) -> tuple[Callable, Callable]:
    if namespace.get("SCHEMA_VERSION") != 1:
        raise AcceptedSourceSnapshotCustodyError("accepted build-input snapshot schema moved")
    subjects = tuple(path.as_posix() for path in namespace.get("GENERATED_SUBJECTS", ()))
    if subjects != EXPECTED_GENERATED_SUBJECTS:
        raise AcceptedSourceSnapshotCustodyError("accepted generated/private subject set moved")
    stage = namespace.get("stage_accepted_build_inputs")
    digest = namespace.get("generated_manifest_sha256")
    if not callable(stage) or not callable(digest):
        raise AcceptedSourceSnapshotCustodyError("accepted snapshot helper exposes no admission authority")
    return stage, digest


def _require_no_acl(root: Path) -> None:
    completed = subprocess.run(
        ["/usr/bin/find", str(root), "-acl", "-print", "-quit"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise AcceptedSourceSnapshotCustodyError(
            "could not inspect accepted source snapshot ACL state"
        )
    found = (completed.stdout or "").strip()
    if found:
        raise AcceptedSourceSnapshotCustodyError(
            f"accepted source snapshot unexpectedly inherited an ACL: {found}"
        )


def _scan_for_live_repo_reference(snapshot: Path, live_repo: Path) -> None:
    marker = str(live_repo).encode("utf-8")
    if not marker:
        raise AcceptedSourceSnapshotCustodyError("live repository marker is empty")
    for current_raw, directory_names, file_names in os.walk(snapshot, followlinks=False):
        current = Path(current_raw)
        directory_names[:] = [name for name in directory_names if not (current / name).is_symlink()]
        for name in file_names:
            path = current / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                continue
            # Compiler metadata is normally small text. For larger binaries, stream
            # chunks with marker overlap instead of loading the whole file.
            overlap = max(0, len(marker) - 1)
            tail = b""
            with path.open("rb", buffering=0) as handle:
                while True:
                    block = handle.read(1024 * 1024)
                    if not block:
                        break
                    combined = tail + block
                    if marker in combined:
                        relative = path.relative_to(snapshot)
                        raise AcceptedSourceSnapshotCustodyError(
                            f"admitted snapshot retained an absolute live-checkout reference: {relative}"
                        )
                    tail = combined[-overlap:] if overlap else b""


def _seal_tree(parent: Path, snapshot: Path, gid: int) -> None:
    if gid <= 0:
        raise AcceptedSourceSnapshotCustodyError("snapshot build GID is invalid")
    parent = _absolute(parent)
    snapshot = _absolute(snapshot)
    if parent.parent != _require_private_tmp() or snapshot.parent != parent:
        raise AcceptedSourceSnapshotCustodyError("snapshot escaped one protected /private/tmp custody parent")
    os.chown(parent, 0, gid)
    os.chmod(parent, 0o710)
    for current_raw, directory_names, file_names in os.walk(snapshot, topdown=False, followlinks=False):
        current = Path(current_raw)
        for name in file_names:
            path = current / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                os.lchown(path, 0, gid)
                continue
            if not stat.S_ISREG(metadata.st_mode):
                raise AcceptedSourceSnapshotCustodyError(f"snapshot contains unsupported file type: {path}")
            executable = bool(metadata.st_mode & 0o111)
            os.chown(path, 0, gid)
            os.chmod(path, 0o750 if executable else 0o640)
        for name in directory_names:
            path = current / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                os.lchown(path, 0, gid)
                continue
            if not stat.S_ISDIR(metadata.st_mode):
                raise AcceptedSourceSnapshotCustodyError(
                    f"snapshot contains unsupported directory type: {path}"
                )
            os.chown(path, 0, gid)
            os.chmod(path, 0o750)
        os.chown(current, 0, gid)
        os.chmod(current, 0o750)
    _require_no_acl(parent)


def _map_argument(argument: str, live_repo: Path, snapshot: Path) -> str:
    live = str(live_repo)
    if argument == live:
        return str(snapshot)
    prefix = live + os.sep
    if argument.startswith(prefix):
        relative = Path(argument[len(prefix) :])
        if any(part in ("", ".", "..") for part in relative.parts):
            raise AcceptedSourceSnapshotCustodyError("guarded command contains unsafe live-source path")
        return str(snapshot / relative)
    if live in argument:
        raise AcceptedSourceSnapshotCustodyError(
            "guarded command embeds the mutable live checkout in a non-canonical argument"
        )
    return argument


def map_guarded_command(command: Sequence[str], live_repo: Path, snapshot: Path) -> list[str]:
    live_repo = _absolute(live_repo)
    snapshot = _absolute(snapshot)
    mapped = [_map_argument(str(argument), live_repo, snapshot) for argument in command]
    if str(live_repo) in "\0".join(mapped):
        raise AcceptedSourceSnapshotCustodyError("mutable live checkout survived command mapping")
    guard = str(snapshot / "Scripts/capture_tuya_private_input_build_guard.py")
    if mapped.count(guard) != 1:
        raise AcceptedSourceSnapshotCustodyError("mapped build does not execute exactly one accepted snapshot guard")
    return mapped


class AcceptedSourceSnapshot:
    def __init__(
        self,
        *,
        live_repo: Path,
        source_sha: str,
        expected_manifest_sha256: str,
        snapshot_helper: dict[str, object],
    ) -> None:
        self.live_repo = _absolute(live_repo)
        if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
            raise AcceptedSourceSnapshotCustodyError("accepted source SHA is malformed")
        if HEX64.fullmatch(expected_manifest_sha256) is None:
            raise AcceptedSourceSnapshotCustodyError("accepted generated/private manifest digest is malformed")
        self.source_sha = source_sha
        self.expected_manifest_sha256 = expected_manifest_sha256
        self._stage, self._digest = _require_snapshot_helper(snapshot_helper)
        self.parent = Path(tempfile.mkdtemp(prefix="nembra-accepted-source.", dir=_require_private_tmp()))
        os.chown(self.parent, 0, 0)
        os.chmod(self.parent, 0o700)
        self.snapshot = self.parent / "source"
        self._sealed_gid: int | None = None
        self._bound = False
        try:
            actual = self._stage(
                self.live_repo,
                self.source_sha,
                self.snapshot,
                self.expected_manifest_sha256,
            )
            if actual != self.expected_manifest_sha256:
                raise AcceptedSourceSnapshotCustodyError("accepted snapshot helper returned the wrong manifest")
            _require_no_acl(self.parent)
            _scan_for_live_repo_reference(self.snapshot, self.live_repo)
        except Exception:
            self.destroy()
            raise

    def seal(self, gid: int) -> None:
        if self._sealed_gid is not None:
            if self._sealed_gid != gid:
                raise AcceptedSourceSnapshotCustodyError("accepted snapshot was rebound to another build GID")
            return
        _seal_tree(self.parent, self.snapshot, gid)
        actual = self._digest(self.snapshot, self.source_sha)
        if actual != self.expected_manifest_sha256:
            raise AcceptedSourceSnapshotCustodyError("sealed snapshot changed the accepted generated/private manifest")
        self._sealed_gid = gid

    def bind_build_origin(self, build_origin: dict[str, object]) -> None:
        if self._bound:
            raise AcceptedSourceSnapshotCustodyError("accepted source snapshot already bound to build origin")
        original = build_origin.get("_run_exec_bound_build")
        if not callable(original):
            raise AcceptedSourceSnapshotCustodyError("accepted build-origin helper exposes no exec seam")
        self._bound = True
        used = False

        def snapshot_exec(
            command: Sequence[str],
            *,
            name: str,
            uid: int,
            gid: int,
            baseline_groups: Sequence[int],
            environment: dict[str, str],
            cwd: Path,
        ):
            nonlocal used
            if used:
                raise AcceptedSourceSnapshotCustodyError("accepted build-origin helper requested more than one compiler exec")
            used = True
            if uid <= 0 or gid <= 0 or uid != gid:
                raise AcceptedSourceSnapshotCustodyError("accepted build identity is not one dedicated UID/GID")
            self.seal(gid)
            mapped = map_guarded_command(command, self.live_repo, self.snapshot)
            return original(
                mapped,
                name=name,
                uid=uid,
                gid=gid,
                baseline_groups=baseline_groups,
                environment=environment,
                cwd=self.snapshot,
            )

        build_origin["_run_exec_bound_build"] = snapshot_exec

    def destroy(self) -> None:
        if not self.parent.exists():
            return
        try:
            os.chmod(self.parent, 0o700)
        except OSError:
            pass
        shutil.rmtree(self.parent, ignore_errors=True)


def create(
    *,
    live_repo: Path,
    source_sha: str,
    expected_manifest_sha256: str,
    snapshot_helper: dict[str, object],
) -> AcceptedSourceSnapshot:
    return AcceptedSourceSnapshot(
        live_repo=live_repo,
        source_sha=source_sha,
        expected_manifest_sha256=expected_manifest_sha256,
        snapshot_helper=snapshot_helper,
    )
