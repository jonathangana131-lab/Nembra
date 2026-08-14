#!/usr/bin/env python3
"""Create one root-custodied frozen Xcode execution subject for Capture field work.

The helper is designed to run once through sudo before the field installer revokes
its own elevation authority. It validates a COW clone of the system-selected Xcode,
returns exact frozen tool paths to the invoking field shell, and leaves a tiny root
janitor that deletes only that admitted freeze namespace after that exact field shell
exits. No device discovery, installation, Bluetooth, Tuya, telemetry, or scooter action
occurs here.
"""

from __future__ import annotations

import argparse
import grp
import os
from pathlib import Path
import pwd
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from typing import Iterable, Sequence

FREEZE_PREFIX = "NembraSelectedXcodeFreeze."
XCODE_REQUIREMENT = '=anchor apple generic and identifier "com.apple.dt.Xcode"'
CLOSED_ENV = {
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": "/tmp",
    "LANG": "C",
    "LC_ALL": "C",
}
TOOLS = ("xcodebuild", "xctrace", "devicectl")


class SelectedXcodeFreezeError(RuntimeError):
    pass


def _run(
    argv: Sequence[str],
    *,
    env: dict[str, str] | None = None,
    check: bool = True,
    text: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(argv),
        env=CLOSED_ENV if env is None else env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=text,
        check=check,
    )


def _require_root_darwin() -> None:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise SelectedXcodeFreezeError("selected-Xcode freeze requires root on macOS")


def _invoking_field_identity() -> tuple[str, int, int, tuple[int, ...]]:
    raw_uid = os.environ.get("SUDO_UID", "")
    raw_gid = os.environ.get("SUDO_GID", "")
    raw_user = os.environ.get("SUDO_USER", "")
    if not re.fullmatch(r"[0-9]+", raw_uid) or not re.fullmatch(r"[0-9]+", raw_gid):
        raise SelectedXcodeFreezeError("sudo did not expose the invoking field UID/GID")
    uid = int(raw_uid)
    gid = int(raw_gid)
    if uid <= 0 or gid <= 0 or not raw_user or raw_user == "root":
        raise SelectedXcodeFreezeError("selected-Xcode freeze requires one non-root invoking field identity")
    account = pwd.getpwnam(raw_user)
    if account.pw_uid != uid or account.pw_gid != gid:
        raise SelectedXcodeFreezeError("sudo invoking identity disagrees with Directory Services")
    groups = tuple(sorted({int(value) for value in os.getgrouplist(raw_user, gid)}))
    if gid not in groups or any(value <= 0 for value in groups):
        raise SelectedXcodeFreezeError("invoking field group baseline is invalid")
    return raw_user, uid, gid, groups


def _ps_value(pid: int, key: str) -> str:
    if pid <= 1:
        raise SelectedXcodeFreezeError("field shell PID is invalid")
    completed = _run(["/bin/ps", "-o", f"{key}=", "-p", str(pid)], check=False)
    if completed.returncode != 0:
        raise SelectedXcodeFreezeError("field shell process could not be inspected")
    value = completed.stdout.strip()
    if not value:
        raise SelectedXcodeFreezeError("field shell process inspection was empty")
    return value


def _process_parent(pid: int) -> int:
    value = _ps_value(pid, "ppid")
    if not re.fullmatch(r"[0-9]+", value):
        raise SelectedXcodeFreezeError("field process ancestry is malformed")
    return int(value)


def _require_field_shell_ancestor(field_pid: int, field_uid: int) -> str:
    uid_text = _ps_value(field_pid, "uid")
    if not re.fullmatch(r"[0-9]+", uid_text) or int(uid_text) != field_uid:
        raise SelectedXcodeFreezeError("claimed field shell PID is not owned by the invoking field UID")
    start_identity = _ps_value(field_pid, "lstart")

    current = os.getpid()
    visited: set[int] = set()
    for _ in range(32):
        if current == field_pid:
            return start_identity
        if current in visited or current <= 1:
            break
        visited.add(current)
        current = _process_parent(current)
    raise SelectedXcodeFreezeError("claimed field shell PID is not an ancestor of the root freeze helper")


def _selected_source() -> tuple[Path, Path]:
    completed = _run(["/usr/bin/xcode-select", "-p"])
    developer = Path(completed.stdout.strip())
    if not developer.is_absolute():
        raise SelectedXcodeFreezeError("xcode-select returned a non-absolute developer path")
    match = re.fullmatch(r"(/Applications/[^/]+[.]app)/Contents/Developer", str(developer))
    if match is None:
        raise SelectedXcodeFreezeError("selected Xcode is outside the admitted /Applications bundle shape")
    app = Path(match.group(1))
    for subject, label in ((app, "selected Xcode app"), (developer, "selected developer directory")):
        metadata = os.lstat(subject)
        if stat.S_ISLNK(metadata.st_mode):
            raise SelectedXcodeFreezeError(f"{label} is a symlink")
        if not stat.S_ISDIR(metadata.st_mode):
            raise SelectedXcodeFreezeError(f"{label} is not a directory")
    if os.stat(app).st_dev != os.stat("/Library").st_dev:
        raise SelectedXcodeFreezeError("selected Xcode and /Library are not on one COW-capable filesystem")
    return app, developer


def _require_no_acl(root: Path) -> None:
    completed = _run(["/usr/bin/find", str(root), "-acl", "-print", "-quit"], check=False)
    if completed.returncode != 0:
        detail = completed.stderr.strip()
        raise SelectedXcodeFreezeError(
            "frozen Xcode ACL oracle failed" + (f": {detail}" if detail else "")
        )
    subject = completed.stdout.strip()
    if subject:
        raise SelectedXcodeFreezeError(f"frozen Xcode retained extended ACL authority: {subject}")


def _inside(root: Path, candidate: Path) -> bool:
    return candidate == root or root in candidate.parents


def _validate_frozen_tree(namespace: Path, root: Path) -> None:
    if not namespace.is_absolute() or namespace.is_symlink():
        raise SelectedXcodeFreezeError("frozen namespace is not one real absolute directory")
    if not root.is_absolute() or root.is_symlink() or root.parent != namespace:
        raise SelectedXcodeFreezeError("frozen Xcode root is not one direct namespace child")

    for subject in (namespace, root):
        metadata = os.lstat(subject)
        if not stat.S_ISDIR(metadata.st_mode):
            raise SelectedXcodeFreezeError(f"frozen authority subject is not a directory: {subject}")
        if metadata.st_uid != 0 or metadata.st_mode & 0o022:
            raise SelectedXcodeFreezeError(f"frozen authority subject is not root/no-write custodied: {subject}")

    subjects = 1
    for current, directories, files in os.walk(root, followlinks=False):
        for name in [*directories, *files]:
            path = Path(current) / name
            metadata = os.lstat(path)
            subjects += 1
            if metadata.st_uid != 0:
                raise SelectedXcodeFreezeError(f"frozen Xcode subject is not root-owned: {path}")
            if stat.S_ISLNK(metadata.st_mode):
                raw_target = os.readlink(path)
                if os.path.isabs(raw_target):
                    raise SelectedXcodeFreezeError(f"frozen Xcode contains absolute symlink authority: {path}")
                try:
                    resolved = path.resolve(strict=False)
                except (OSError, RuntimeError) as error:
                    raise SelectedXcodeFreezeError(f"frozen Xcode symlink cannot be normalized: {path}") from error
                if not _inside(root, resolved):
                    raise SelectedXcodeFreezeError(f"frozen Xcode symlink escapes clone authority: {path}")
                try:
                    strict_resolved = path.resolve(strict=True)
                except FileNotFoundError:
                    continue
                except (OSError, RuntimeError) as error:
                    raise SelectedXcodeFreezeError(f"frozen Xcode symlink resolution failed: {path}") from error
                if not _inside(root, strict_resolved):
                    raise SelectedXcodeFreezeError(f"frozen Xcode symlink resolves outside clone: {path}")
                continue
            if metadata.st_mode & 0o022:
                raise SelectedXcodeFreezeError(f"frozen Xcode subject remains group/world writable: {path}")
    if subjects < 1000:
        raise SelectedXcodeFreezeError("frozen Xcode tree is unexpectedly small")


def _codesign_verify(app: Path) -> None:
    completed = _run(
        [
            "/usr/bin/codesign",
            "--verify",
            "--deep",
            "--strict",
            "--verbose=4",
            "-R",
            XCODE_REQUIREMENT,
            str(app),
        ],
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip()
        raise SelectedXcodeFreezeError(
            "frozen Xcode failed Apple-anchored strict/deep signature verification"
            + (f": {detail}" if detail else "")
        )


def _acl_clean_path_component(path: Path) -> None:
    completed = _run(["/bin/ls", "-lde", str(path)], check=False)
    if completed.returncode != 0:
        raise SelectedXcodeFreezeError(f"ACL inspection failed for frozen selected path: {path}")
    lines = completed.stdout.splitlines()
    if not lines:
        raise SelectedXcodeFreezeError(f"ACL inspection was empty for frozen selected path: {path}")
    mode_field = lines[0].split(None, 1)[0]
    if mode_field.endswith("+") or len(lines) != 1:
        raise SelectedXcodeFreezeError(f"frozen selected path retains extended ACL authority: {path}")


def _validate_selected_path(path: Path, *, kind: str, frozen_developer: Path) -> None:
    try:
        resolved = path.resolve(strict=True)
    except OSError as error:
        raise SelectedXcodeFreezeError(f"frozen selected {path.name} is unavailable") from error
    if resolved != path:
        raise SelectedXcodeFreezeError(f"frozen selected path contains symlink/alias ancestry: {path} -> {resolved}")
    if path != frozen_developer and not _inside(frozen_developer, path):
        raise SelectedXcodeFreezeError(f"frozen selected tool escaped admitted developer tree: {path}")

    current = Path(path.anchor)
    for component in path.parts[1:]:
        current = current / component
        metadata = os.lstat(current)
        leaf = current == path
        if stat.S_ISLNK(metadata.st_mode):
            raise SelectedXcodeFreezeError(f"frozen selected path contains symlink ancestry: {current}")
        if leaf and kind == "file":
            if not stat.S_ISREG(metadata.st_mode):
                raise SelectedXcodeFreezeError(f"frozen selected tool is not a regular file: {path}")
        elif not stat.S_ISDIR(metadata.st_mode):
            raise SelectedXcodeFreezeError(f"frozen selected ancestry is not a directory: {current}")
        if metadata.st_uid != 0 or metadata.st_mode & 0o022:
            raise SelectedXcodeFreezeError(f"frozen selected ancestry is not root/no-write custodied: {current}")
        _acl_clean_path_component(current)


def _resolve_tools(frozen_developer: Path) -> dict[str, Path]:
    environment = dict(CLOSED_ENV)
    environment["DEVELOPER_DIR"] = str(frozen_developer)
    tools: dict[str, Path] = {}
    for name in TOOLS:
        completed = _run(["/usr/bin/xcrun", "--find", name], env=environment)
        path = Path(completed.stdout.strip())
        if not path.is_absolute() or not _inside(frozen_developer, path):
            raise SelectedXcodeFreezeError(f"frozen selected {name} escaped admitted developer tree")
        _validate_selected_path(path, kind="file", frozen_developer=frozen_developer)
        tools[name] = path
    _validate_selected_path(frozen_developer, kind="directory", frozen_developer=frozen_developer)
    version = _run([str(tools["xcodebuild"]), "-version"], env=environment).stdout
    first = version.splitlines()[0] if version.splitlines() else ""
    if first != "Xcode 27" and not first.startswith("Xcode 27."):
        raise SelectedXcodeFreezeError(f"frozen selected toolchain is not Xcode 27: {first or '<empty>'}")
    return tools


def _field_run(argv: Sequence[str], *, uid: int, gid: int, groups: Iterable[int]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(argv),
        env=CLOSED_ENV,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        user=uid,
        group=gid,
        extra_groups=list(groups),
    )


def _prove_field_cannot_mutate(
    frozen_developer: Path,
    xcodebuild: Path,
    *,
    uid: int,
    gid: int,
    groups: tuple[int, ...],
) -> None:
    before = _run(["/usr/bin/shasum", "-a", "256", str(xcodebuild)]).stdout.split()[0]
    leaf = _field_run(
        ["/bin/sh", "-c", 'printf attack >> "$1"', "nembra-cow-attack", str(xcodebuild)],
        uid=uid,
        gid=gid,
        groups=groups,
    )
    probe = frozen_developer / "usr/bin/nembra-field-replacement-probe"
    parent = _field_run(["/usr/bin/touch", str(probe)], uid=uid, gid=gid, groups=groups)
    if leaf.returncode == 0 or parent.returncode == 0 or probe.exists():
        raise SelectedXcodeFreezeError("field identity retained mutation/replacement authority over frozen Xcode")
    after = _run(["/usr/bin/shasum", "-a", "256", str(xcodebuild)]).stdout.split()[0]
    if before != after:
        raise SelectedXcodeFreezeError("frozen selected xcodebuild bytes changed during field mutation probe")


def _safe_cleanup(namespace: Path) -> None:
    try:
        metadata = os.lstat(namespace)
    except FileNotFoundError:
        return
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        return
    if metadata.st_uid != 0 or namespace.parent != Path("/Library") or not namespace.name.startswith(FREEZE_PREFIX):
        return
    shutil.rmtree(namespace)


def _field_process_is_same(pid: int, uid: int, start_identity: str) -> bool:
    try:
        current_uid = _ps_value(pid, "uid")
        current_start = _ps_value(pid, "lstart")
    except SelectedXcodeFreezeError:
        return False
    return current_uid.isdigit() and int(current_uid) == uid and current_start == start_identity


def _start_cleanup_janitor(namespace: Path, *, field_pid: int, field_uid: int, start_identity: str) -> int:
    child = os.fork()
    if child != 0:
        return child
    try:
        os.setsid()
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        devnull = os.open("/dev/null", os.O_RDWR)
        try:
            for descriptor in (0, 1, 2):
                os.dup2(devnull, descriptor)
        finally:
            if devnull > 2:
                os.close(devnull)
        # The namespace is already root-owned and field-nonwritable. The janitor
        # has no command channel and can only wait for the exact field process
        # identity to disappear before deleting this exact admitted namespace.
        while _field_process_is_same(field_pid, field_uid, start_identity):
            time.sleep(0.5)
        _safe_cleanup(namespace)
    finally:
        os._exit(0)


def freeze_selected_xcode(field_pid: int) -> tuple[Path, Path, dict[str, Path], int]:
    _require_root_darwin()
    _, field_uid, field_gid, field_groups = _invoking_field_identity()
    start_identity = _require_field_shell_ancestor(field_pid, field_uid)
    source_app, _ = _selected_source()

    namespace = Path(tempfile.mkdtemp(prefix=FREEZE_PREFIX, dir="/Library"))
    cleanup_needed = True
    try:
        os.chown(namespace, 0, 0)
        os.chmod(namespace, 0o700)
        _run(["/bin/chmod", "-N", str(namespace)])
        frozen_app = namespace / "Xcode.app"
        _run(["/bin/cp", "-cR", str(source_app), str(frozen_app)])
        if not (frozen_app / "Contents/Developer").is_dir():
            raise SelectedXcodeFreezeError("COW clone did not produce the expected Xcode Developer tree")
        _run(["/usr/sbin/chown", "-Rh", "root:wheel", str(frozen_app)])
        _require_no_acl(frozen_app)
        _validate_frozen_tree(namespace, frozen_app)
        _codesign_verify(frozen_app)
        os.chmod(namespace, 0o755)

        frozen_developer = frozen_app / "Contents/Developer"
        tools = _resolve_tools(frozen_developer)
        _prove_field_cannot_mutate(
            frozen_developer,
            tools["xcodebuild"],
            uid=field_uid,
            gid=field_gid,
            groups=field_groups,
        )
        _codesign_verify(frozen_app)
        janitor_pid = _start_cleanup_janitor(
            namespace,
            field_pid=field_pid,
            field_uid=field_uid,
            start_identity=start_identity,
        )
        cleanup_needed = False
        return namespace, frozen_developer, tools, janitor_pid
    finally:
        if cleanup_needed:
            _safe_cleanup(namespace)


def _parse(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Freeze the selected Xcode into one root-custodied COW execution subject")
    parser.add_argument("--field-pid", required=True, type=int)
    return parser.parse_args(list(argv))


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = _parse(sys.argv[1:] if argv is None else argv)
        namespace, developer, tools, janitor_pid = freeze_selected_xcode(args.field_pid)
        values = [
            str(namespace),
            str(developer),
            str(tools["xcodebuild"]),
            str(tools["xctrace"]),
            str(tools["devicectl"]),
            str(janitor_pid),
        ]
        if any("\t" in value or "\n" in value for value in values):
            raise SelectedXcodeFreezeError("frozen selected-Xcode result contains malformed separators")
        sys.stdout.write("\t".join(values) + "\n")
        return 0
    except (OSError, subprocess.CalledProcessError, SelectedXcodeFreezeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
