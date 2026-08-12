#!/usr/bin/env python3
"""Bind the physical install subject to exact compiler output through an APFS freeze.

This privileged helper owns the compiler-output -> protected-install-stage handoff.
The field user never receives writable compiler-output pathname authority. Root creates
one ephemeral local build identity, mounts a private APFS sparse image writable only by
that identity, runs the guarded build there, removes fresh pathname authority when the
build returns, and requires a normal non-forced detach before any compiler-output
fingerprint can become authoritative. The exact app is then inspected only after a
read-only remount and copied into the canonical root-owned install stage.

The helper is executed from bytes resolved from the exact accepted Git tree by the field
installer. It is not field authorization by itself; downstream provenance, signature,
profile, selected-device, runtime, Final-GO, and physical-evidence gates remain required.
"""

from __future__ import annotations

import argparse
import base64
import grp
import os
from pathlib import Path
import plistlib
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Iterable, Sequence

WORKSPACE_PREFIX = "nembra-authenticated-capture-origin."
STAGE_PREFIX = "nembra-authenticated-capture-install."
IMAGE_NAME = "compiler-output.sparseimage"
MOUNT_NAME = "compiler-output"
APFS_VOLUME_NAME = "NembraCaptureOrigin"
DEFAULT_APP_RELATIVE = Path("Build/Products/Debug-iphoneos/Nembra Capture.app")
DERIVED_PLACEHOLDER = "__NEMBRA_PROTECTED_DERIVED__"


class BuildOriginCustodyError(RuntimeError):
    pass


def _require_real_private_tmp() -> Path:
    root = Path("/private/tmp")
    try:
        metadata = root.lstat()
    except OSError as error:
        raise BuildOriginCustodyError("/private/tmp is unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise BuildOriginCustodyError("/private/tmp is not one real directory")
    return root


def _invoking_identity() -> tuple[str, int, int, str, tuple[int, ...]]:
    if os.geteuid() != 0:
        raise BuildOriginCustodyError("build-origin custody must run as root through sudo")
    raw_uid = os.environ.get("SUDO_UID", "")
    raw_gid = os.environ.get("SUDO_GID", "")
    sudo_user = os.environ.get("SUDO_USER", "")
    if not raw_uid.isdigit() or not raw_gid.isdigit() or not sudo_user:
        raise BuildOriginCustodyError("sudo did not expose one invoking-user identity")
    uid = int(raw_uid)
    gid = int(raw_gid)
    if uid <= 0:
        raise BuildOriginCustodyError("root may not be the field-build invoking identity")
    if gid <= 0:
        raise BuildOriginCustodyError("root group may not be the field-build invoking primary group")
    account = pwd.getpwuid(uid)
    if account.pw_name != sudo_user or account.pw_gid != gid:
        raise BuildOriginCustodyError("sudo invoking identity does not match the local account database")
    groups = tuple(sorted(set(os.getgrouplist(account.pw_name, gid))))
    if any(value <= 0 for value in groups):
        raise BuildOriginCustodyError("invoking-user supplementary groups contain root or invalid authority")
    return account.pw_name, uid, gid, account.pw_dir, groups


def _structured_credentials(
    uid: int,
    gid: int,
    extra_groups: Iterable[int],
) -> dict[str, object]:
    if uid <= 0 or gid <= 0:
        raise BuildOriginCustodyError("structured child credentials require non-root user and group identity")
    normalized = sorted({int(value) for value in extra_groups if int(value) != gid})
    if any(value <= 0 for value in normalized):
        raise BuildOriginCustodyError("structured child supplementary groups contain invalid authority")
    return {"user": uid, "group": gid, "extra_groups": normalized}


def _group_names(groups: Sequence[int]) -> tuple[str, ...]:
    names: list[str] = []
    for gid in sorted(set(int(value) for value in groups)):
        if gid <= 0:
            raise BuildOriginCustodyError("cannot inspect sudo policy for root or invalid group authority")
        try:
            names.append(grp.getgrgid(gid).gr_name)
        except KeyError as error:
            raise BuildOriginCustodyError(
                f"could not resolve invoking group {gid} while inspecting sudo policy"
            ) from error
    return tuple(names)


def _sudo_policy_exposes_passwordless_authority(
    policy_output: str,
    invoking_group_names: Sequence[str],
) -> bool:
    if "NOPASSWD:" in policy_output or "!authenticate" in policy_output:
        return True
    exempt_groups = {
        match.group(1).strip("'\"")
        for match in re.finditer(
            r"(?:^|[\s,])exempt_group\s*=\s*([^\s,]+)",
            policy_output,
            flags=re.MULTILINE,
        )
    }
    return bool(exempt_groups.intersection(invoking_group_names))


def _inspect_invoker_sudo_policy(
    user: str,
    groups: Sequence[int],
    environment: dict[str, str],
) -> None:
    policy_environment = dict(environment)
    policy_environment["LANG"] = "C"
    policy_environment["LC_ALL"] = "C"
    listing = subprocess.run(
        ["/usr/bin/sudo", "-ll", "-U", user],
        env=policy_environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if listing.returncode != 0:
        detail = (listing.stderr or "").strip()
        raise BuildOriginCustodyError(
            "could not inspect invoking-user sudo policy before build custody"
            + (f": {detail}" if detail else "")
        )
    policy_output = (listing.stdout or "") + "\n" + (listing.stderr or "")
    if _sudo_policy_exposes_passwordless_authority(policy_output, _group_names(groups)):
        raise BuildOriginCustodyError(
            "invoking-user sudo policy exposes passwordless privileged authority; "
            "build-origin isolation cannot be established"
        )


def _field_environment(user: str, home: str) -> dict[str, str]:
    environment = {
        "HOME": home,
        "USER": user,
        "LOGNAME": user,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": "/tmp",
    }
    for key in ("LANG", "LC_ALL", "LC_CTYPE", "TERM", "__CF_USER_TEXT_ENCODING"):
        value = os.environ.get(key)
        if value:
            environment[key] = value
    return environment


def _invalidate_invoker_sudo(
    user: str,
    uid: int,
    gid: int,
    groups: Sequence[int],
    environment: dict[str, str],
) -> None:
    _inspect_invoker_sudo_policy(user, groups, environment)
    credentials = _structured_credentials(uid, gid, groups)
    revoke = subprocess.run(
        ["/usr/bin/sudo", "-K"],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        **credentials,
    )
    if revoke.returncode != 0:
        raise BuildOriginCustodyError("could not invalidate invoking-user sudo timestamp before build custody")

    command_probe = subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        **credentials,
    )
    list_probe = subprocess.run(
        ["/usr/bin/sudo", "-n", "-l"],
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        **credentials,
    )
    if command_probe.returncode == 0 or list_probe.returncode == 0:
        raise BuildOriginCustodyError(
            "noninteractive sudo remains available after invalidation; build-origin isolation cannot be established"
        )


def _replace_derived_placeholder(command: Sequence[str], derived_root: Path) -> list[str]:
    if not command:
        raise BuildOriginCustodyError("no guarded build command was supplied")
    matches = sum(argument.count(DERIVED_PLACEHOLDER) for argument in command)
    if matches != 1:
        raise BuildOriginCustodyError(
            "guarded build command must contain exactly one protected DerivedData placeholder"
        )
    return [argument.replace(DERIVED_PLACEHOLDER, str(derived_root)) for argument in command]


def _validate_app_relative(path: Path) -> Path:
    if path.is_absolute() or not path.parts or any(part in ("", ".", "..") for part in path.parts):
        raise BuildOriginCustodyError("app-relative path must remain strictly beneath protected DerivedData")
    return path


def _assert_real_ancestry(root: Path, relative: Path) -> Path:
    current = root
    for component in relative.parts:
        current = current / component
        try:
            metadata = current.lstat()
        except OSError as error:
            raise BuildOriginCustodyError(f"expected build output is missing: {current}") from error
        if stat.S_ISLNK(metadata.st_mode):
            raise BuildOriginCustodyError(f"build-output ancestry contains a symlink: {current}")
    if not current.is_dir():
        raise BuildOriginCustodyError("build output app is not one real directory")
    return current


def _load_fingerprint_helper(encoded: str):
    try:
        source = base64.b64decode(encoded, validate=True)
    except Exception as error:
        raise BuildOriginCustodyError("accepted install-custody helper transport is malformed") from error
    namespace = {
        "__name__": "nembra_signed_app_install_custody",
        "__file__": "<accepted-signed-app-install-custody>",
    }
    try:
        exec(
            compile(source, "<accepted-signed-app-install-custody>", "exec", dont_inherit=True),
            namespace,
        )
    except Exception as error:
        raise BuildOriginCustodyError("accepted install-custody helper could not be loaded") from error
    fingerprint = namespace.get("fingerprint")
    if not callable(fingerprint):
        raise BuildOriginCustodyError("accepted install-custody helper exposes no fingerprint function")
    return fingerprint


def _id_in_use(candidate: int) -> bool:
    try:
        pwd.getpwuid(candidate)
        return True
    except KeyError:
        pass
    try:
        grp.getgrgid(candidate)
        return True
    except KeyError:
        return False


def _choose_ephemeral_id() -> int:
    start = 52000 + (os.getpid() % 7000)
    for candidate in range(start, 62000):
        if candidate > 0 and not _id_in_use(candidate):
            return candidate
    for candidate in range(52000, start):
        if not _id_in_use(candidate):
            return candidate
    raise BuildOriginCustodyError("could not allocate one isolated ephemeral build UID/GID")


def _run_root_checked(argv: Sequence[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(argv),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )


def _create_local_build_identity(name: str, uid: int, gid: int, home: Path) -> None:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise BuildOriginCustodyError("ephemeral build identity creation requires root on macOS")
    if uid <= 0 or gid <= 0 or uid != gid:
        raise BuildOriginCustodyError("ephemeral build identity requires one positive dedicated UID/GID")
    for kind in ("Users", "Groups"):
        existing = subprocess.run(
            ["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if existing.returncode == 0:
            raise BuildOriginCustodyError("ephemeral build identity name already exists")

    try:
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}"])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "PrimaryGroupID", str(gid)])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "RealName", "Nembra Capture Build"])

        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}"])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UniqueID", str(uid)])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "PrimaryGroupID", str(gid)])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "NFSHomeDirectory", str(home)])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UserShell", "/usr/bin/false"])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "RealName", "Nembra Capture Build"])
        _run_root_checked(["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "IsHidden", "1"])
        subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)
        account = pwd.getpwnam(name)
        group = grp.getgrnam(name)
        if account.pw_uid != uid or account.pw_gid != gid or group.gr_gid != gid:
            raise BuildOriginCustodyError("directory services did not materialize the exact build identity")
    except Exception:
        _remove_local_build_identity(name, uid)
        raise


def _remove_local_build_identity(name: str, uid: int | None) -> None:
    if sys.platform != "darwin":
        return
    if uid is not None and uid > 0:
        subprocess.run(
            ["/usr/bin/pkill", "-9", "-u", str(uid)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(["/usr/bin/dscacheutil", "-flushcache"], check=False)


def _create_apfs_image(image: Path) -> None:
    completed = subprocess.run(
        [
            "/usr/bin/hdiutil",
            "create",
            "-quiet",
            "-size",
            "6g",
            "-type",
            "SPARSE",
            "-fs",
            "APFS",
            "-volname",
            APFS_VOLUME_NAME,
            str(image),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or "").strip()
        raise BuildOriginCustodyError(
            "could not create isolated APFS compiler-output image" + (f": {detail}" if detail else "")
        )


def _attach_apfs(image: Path, mountpoint: Path, *, readonly: bool) -> str:
    command = [
        "/usr/bin/hdiutil",
        "attach",
        "-plist",
        "-nobrowse",
        "-mountpoint",
        str(mountpoint),
    ]
    if readonly:
        command.append("-readonly")
    command.append(str(image))
    completed = subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise BuildOriginCustodyError(
            "could not attach isolated APFS compiler-output image" + (f": {detail}" if detail else "")
        )
    try:
        payload = plistlib.loads(completed.stdout)
    except Exception as error:
        raise BuildOriginCustodyError("hdiutil attach returned malformed plist output") from error
    for entity in payload.get("system-entities", []):
        if entity.get("mount-point") == str(mountpoint) and entity.get("dev-entry"):
            return str(entity["dev-entry"])
    raise BuildOriginCustodyError("hdiutil attach returned no exact mounted compiler-output device")


def _detach_apfs(device: str, *, force: bool = False) -> subprocess.CompletedProcess[str]:
    command = ["/usr/bin/hdiutil", "detach"]
    if force:
        command.append("-force")
    command.append(device)
    return subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


def _build_environment(user: str, home: Path) -> dict[str, str]:
    temp = home / "tmp"
    temp.mkdir(parents=True, exist_ok=True)
    environment = {
        "HOME": str(home),
        "USER": user,
        "LOGNAME": user,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": str(temp),
        "LANG": os.environ.get("LANG", "C"),
        "LC_ALL": os.environ.get("LC_ALL", "C"),
    }
    for key in ("DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS", "__CF_USER_TEXT_ENCODING"):
        value = os.environ.get(key)
        if value:
            environment[key] = value
    return environment


def _copy_to_stage(source_app: Path, private_tmp: Path) -> tuple[Path, Path]:
    stage_root = Path(tempfile.mkdtemp(prefix=STAGE_PREFIX, dir=private_tmp))
    os.chown(stage_root, 0, 0)
    os.chmod(stage_root, 0o700)
    stage_app = stage_root / "Nembra Capture.app"
    subprocess.run(
        ["/usr/bin/ditto", "--noacl", str(source_app), str(stage_app)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    acl = subprocess.run(
        ["/usr/bin/find", str(stage_root), "-acl", "-print", "-quit"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    ).stdout.strip()
    if acl:
        raise BuildOriginCustodyError(f"protected stage retained an ACL: {acl}")
    for current_root, directories, files in os.walk(stage_root, topdown=False, followlinks=False):
        current = Path(current_root)
        for name in files:
            os.chown(current / name, 0, 0, follow_symlinks=False)
        for name in directories:
            os.chown(current / name, 0, 0, follow_symlinks=False)
        os.chown(current, 0, 0, follow_symlinks=False)
    os.chmod(stage_root, 0o755)
    return stage_root, stage_app


def _require_readonly_mount(mountpoint: Path) -> None:
    probe = mountpoint / ".nembra-root-readonly-probe"
    try:
        descriptor = os.open(probe, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except OSError:
        return
    else:
        os.close(descriptor)
        try:
            probe.unlink()
        except OSError:
            pass
        raise BuildOriginCustodyError("compiler-output image remained root-writable after read-only remount")


def run_custodied_build(
    command: Sequence[str],
    *,
    app_relative: Path,
    fingerprint_helper_base64: str,
) -> tuple[Path, str]:
    if sys.platform != "darwin":
        raise BuildOriginCustodyError("APFS build-origin custody requires macOS")
    private_tmp = _require_real_private_tmp()
    field_user, field_uid, field_gid, field_home, field_groups = _invoking_identity()
    field_env = _field_environment(field_user, field_home)
    _invalidate_invoker_sudo(field_user, field_uid, field_gid, field_groups, field_env)

    fingerprint = _load_fingerprint_helper(fingerprint_helper_base64)
    workspace = Path(tempfile.mkdtemp(prefix=WORKSPACE_PREFIX, dir=private_tmp))
    image = workspace / IMAGE_NAME
    mountpoint = workspace / MOUNT_NAME
    home = workspace / "home"
    stage_root: Path | None = None
    writable_device: str | None = None
    readonly_device: str | None = None
    build_uid: int | None = None
    build_gid: int | None = None
    build_name = f"nembrabuild{os.getpid()}"
    identity_created = False

    try:
        build_uid = _choose_ephemeral_id()
        build_gid = build_uid
        if build_uid == field_uid or build_gid in field_groups:
            raise BuildOriginCustodyError("ephemeral build identity overlaps field-user authority")

        os.chown(workspace, 0, build_gid)
        os.chmod(workspace, 0o710)
        mountpoint.mkdir()
        home.mkdir()
        os.chown(home, build_uid, build_gid)
        os.chmod(home, 0o700)

        _create_local_build_identity(build_name, build_uid, build_gid, home)
        identity_created = True
        build_env = _build_environment(build_name, home)
        os.chown(home / "tmp", build_uid, build_gid)
        os.chmod(home / "tmp", 0o700)

        _create_apfs_image(image)
        writable_device = _attach_apfs(image, mountpoint, readonly=False)
        os.chown(mountpoint, build_uid, build_gid)
        os.chmod(mountpoint, 0o700)

        derived_root = mountpoint / "DerivedData"
        guarded_command = _replace_derived_placeholder(command, derived_root)
        build = subprocess.run(
            guarded_command,
            cwd=os.getcwd(),
            env=build_env,
            stdin=None,
            stdout=sys.stderr,
            stderr=sys.stderr,
            text=True,
            check=False,
            **_structured_credentials(build_uid, build_gid, ()),
        )

        # Remove fresh pathname authority before interpreting status. The accepted
        # boundary is the following normal non-forced detach, not process ancestry.
        os.chown(mountpoint, 0, 0)
        os.chmod(mountpoint, 0o700)
        detach = _detach_apfs(writable_device)
        detach_detail = ((detach.stdout or "") + "\n" + (detach.stderr or "")).strip()
        if detach.returncode != 0:
            raise BuildOriginCustodyError(
                "compiler-output filesystem did not reach normal non-forced quiescence"
                + (f": {detach_detail}" if detach_detail else "")
            )
        writable_device = None

        if build.returncode != 0:
            raise BuildOriginCustodyError(f"guarded field build failed with exit status {build.returncode}")

        readonly_device = _attach_apfs(image, mountpoint, readonly=True)
        _require_readonly_mount(mountpoint)
        frozen_derived = mountpoint / "DerivedData"
        source_app = _assert_real_ancestry(
            frozen_derived,
            _validate_app_relative(app_relative),
        )
        source_fingerprint = str(fingerprint(source_app))
        if len(source_fingerprint) != 64 or any(
            character not in "0123456789abcdef" for character in source_fingerprint
        ):
            raise BuildOriginCustodyError("build-produced app fingerprint is malformed")

        stage_root, stage_app = _copy_to_stage(source_app, private_tmp)
        staged_fingerprint = str(fingerprint(stage_app))
        if staged_fingerprint != source_fingerprint:
            raise BuildOriginCustodyError(
                "protected stage differs from the read-only compiler-output app"
            )

        frozen_detach = _detach_apfs(readonly_device)
        frozen_detail = ((frozen_detach.stdout or "") + "\n" + (frozen_detach.stderr or "")).strip()
        if frozen_detach.returncode != 0:
            raise BuildOriginCustodyError(
                "read-only compiler-output image could not detach after protected staging"
                + (f": {frozen_detail}" if frozen_detail else "")
            )
        readonly_device = None
        return stage_root, source_fingerprint
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or "").strip()
        raise BuildOriginCustodyError(
            "protected signed-app staging command failed" + (f": {detail}" if detail else "")
        ) from error
    finally:
        # Force is cleanup-only after acceptance has already failed; it is never an
        # authority-producing transition.
        if readonly_device is not None:
            _detach_apfs(readonly_device, force=True)
        if writable_device is not None:
            _detach_apfs(writable_device, force=True)
        if identity_created:
            _remove_local_build_identity(build_name, build_uid)
        shutil.rmtree(workspace, ignore_errors=True)
        if sys.exc_info()[0] is not None and stage_root is not None:
            shutil.rmtree(stage_root, ignore_errors=True)


def _parse_args(argv: Sequence[str]) -> tuple[Path, str, list[str]]:
    parser = argparse.ArgumentParser(
        description=(
            "Build the signed Capture app inside a dedicated-UID APFS output custody life "
            "and return its protected stage."
        )
    )
    parser.add_argument("--app-relative", default=str(DEFAULT_APP_RELATIVE))
    parser.add_argument("--install-custody-helper-base64", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    return Path(args.app_relative), args.install_custody_helper_base64, command


def main(argv: Sequence[str] | None = None) -> int:
    try:
        app_relative, helper_source, command = _parse_args(sys.argv[1:] if argv is None else argv)
        stage_root, fingerprint = run_custodied_build(
            command,
            app_relative=app_relative,
            fingerprint_helper_base64=helper_source,
        )
        sys.stdout.write(f"{stage_root}\t{fingerprint}\n")
        return 0
    except BuildOriginCustodyError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 78


if __name__ == "__main__":
    raise SystemExit(main())
