#!/usr/bin/env python3
"""Prove a narrow read-only private-input bridge for Capture's dedicated build UID.

Validation only. A synthetic field-owned LocalSecrets tree uses the same privacy shape
as the real Tuya inputs (0700 directories / 0600 files). Root copies that admitted
synthetic generation into a private APFS image, rewrites the copied ownership to
root:<fresh-build-gid> with 0550 directories / 0440 files, detaches it, then mounts it
read-only over the *same* LocalSecrets pathname.

The witness requires:
- the fresh dedicated UID can read exact bytes through the unchanged logical paths;
- neither the dedicated UID nor the ordinary field UID can write/create/chmod in the
  mounted build view;
- root itself receives EROFS when probing the mounted volume for mutation;
- a field-user helper that opened the hidden original secret *before* the overlay can
  mutate that hidden inode while the build view stays byte-identical;
- normal non-forced detach reveals the independently mutated original again;
- fresh local build-principal cleanup is mechanically verified.

No real private Tuya bytes, Xcode build, signing, provisioning, device, Bluetooth,
telemetry, command, or physical authority is exercised.
"""
from __future__ import annotations

import argparse
import errno
import grp
import hashlib
import json
import os
from pathlib import Path
import plistlib
import pwd
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from typing import Iterable

SUCCESS_MARKER = "NEMBRA_PRIVATE_INPUT_APFS_OVERLAY_JSON="
ERROR_MARKER = "NEMBRA_PRIVATE_INPUT_APFS_OVERLAY_ERROR="
VOLUME_NAME = "NembraPrivateInputOverlayWitness"
ORIGINAL_SECRET = b"NEMBRA_SYNTHETIC_PRIVATE_IDENTITY_ORIGINAL_v1\n"
ATTACKER_SECRET = b"NEMBRA_SYNTHETIC_PRIVATE_IDENTITY_ATTACKER_v1\n"


class WitnessError(RuntimeError):
    pass


def run(argv: list[str], *, check: bool = False, **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=check,
        **kwargs,
    )


def emit_error(kind: str, message: str, **extra: object) -> None:
    payload: dict[str, object] = {
        "schemaVersion": 1,
        "kind": kind,
        "message": message,
        "productionBytesChanged": False,
        "productionAcceptanceClaimed": False,
        "physicalAuthorityCreated": False,
    }
    payload.update(extra)
    print(ERROR_MARKER + json.dumps(payload, sort_keys=True), file=sys.stderr)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_digest(root: Path) -> str:
    if not root.is_dir() or root.is_symlink():
        raise WitnessError(f"tree root is not one real directory: {root}")
    digest = hashlib.sha256()
    for current, directories, files in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        directories.sort()
        files.sort()
        relative_dir = current_path.relative_to(root)
        digest.update(b"D\0" + str(relative_dir).encode() + b"\0")
        for name in directories:
            path = current_path / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                raise WitnessError(f"tree contains non-directory ancestry: {path}")
        for name in files:
            path = current_path / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
                raise WitnessError(f"tree contains non-regular input: {path}")
            relative = path.relative_to(root)
            digest.update(b"F\0" + str(relative).encode() + b"\0")
            digest.update(bytes.fromhex(sha256_file(path)))
    return digest.hexdigest()


def _process_state_for_uid(uid: int) -> tuple[list[int], list[int]]:
    completed = run(["/bin/ps", "-axo", "pid=,uid=,state="])
    if completed.returncode != 0:
        raise WitnessError("could not inspect process table")
    live: list[int] = []
    zombies: list[int] = []
    for line in completed.stdout.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            pid = int(parts[0])
            owner = int(parts[1])
        except ValueError:
            continue
        if owner != uid:
            continue
        if parts[2].upper().startswith("Z"):
            zombies.append(pid)
        else:
            live.append(pid)
    return sorted(live), sorted(zombies)


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
        pass
    live, zombies = _process_state_for_uid(candidate)
    return bool(live or zombies)


def choose_ephemeral_id(offset: int = 0) -> int:
    start = 52000 + ((os.getpid() + offset) % 7000)
    for candidate in list(range(start, 62000)) + list(range(52000, start)):
        if candidate > 0 and not _id_in_use(candidate):
            return candidate
    raise WitnessError("could not allocate one isolated ephemeral UID/GID")


def flush_directory_cache() -> None:
    run(["/usr/bin/dscacheutil", "-flushcache"])


def create_identity(name: str, uid: int, home: Path) -> None:
    if os.geteuid() != 0 or sys.platform != "darwin":
        raise WitnessError("identity materialization requires root on macOS")
    if uid <= 0 or _id_in_use(uid):
        raise WitnessError("requested dedicated numeric identity is already in use")
    for kind in ("Users", "Groups"):
        if run(["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"]).returncode == 0:
            raise WitnessError("dedicated identity name already exists")
    commands = (
        ["/usr/bin/dscl", ".", "-create", f"/Groups/{name}"],
        ["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "PrimaryGroupID", str(uid)],
        ["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "RealName", "Nembra Private Input Overlay Witness"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UniqueID", str(uid)],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "PrimaryGroupID", str(uid)],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "NFSHomeDirectory", str(home)],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UserShell", "/usr/bin/false"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "RealName", "Nembra Private Input Overlay Witness"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "IsHidden", "1"],
    )
    try:
        for command in commands:
            completed = run(command)
            if completed.returncode != 0:
                raise WitnessError(f"Directory Services create failed: rc={completed.returncode}")
        flush_directory_cache()
        deadline = time.monotonic() + 4.0
        while time.monotonic() < deadline:
            try:
                account = pwd.getpwnam(name)
                group = grp.getgrnam(name)
            except KeyError:
                flush_directory_cache()
                time.sleep(0.05)
                continue
            if account.pw_uid == uid and account.pw_gid == uid and group.gr_gid == uid:
                return
            raise WitnessError("dedicated identity materialized with the wrong UID/GID")
        raise WitnessError("dedicated identity did not become resolvable")
    except Exception:
        run(["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"])
        run(["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"])
        flush_directory_cache()
        raise


def remove_identity_strict(name: str, uid: int) -> dict[str, object]:
    killed = run(["/usr/bin/pkill", "-9", "-u", str(uid)])
    if killed.returncode not in (0, 1):
        raise WitnessError(f"dedicated UID process cleanup failed: rc={killed.returncode}")
    user_delete = run(["/usr/bin/dscl", ".", "-delete", f"/Users/{name}"])
    group_delete = run(["/usr/bin/dscl", ".", "-delete", f"/Groups/{name}"])
    if user_delete.returncode != 0 or group_delete.returncode != 0:
        raise WitnessError(
            f"dedicated identity delete failed: user_rc={user_delete.returncode} group_rc={group_delete.returncode}"
        )
    flush_directory_cache()
    deadline = time.monotonic() + 8.0
    latest_live: list[int] = []
    latest_zombies: list[int] = []
    latest_lookups: list[str] = []
    while time.monotonic() < deadline:
        latest_live, latest_zombies = _process_state_for_uid(uid)
        latest_lookups = []
        for lookup, key, label in (
            (pwd.getpwnam, name, "user-name"),
            (grp.getgrnam, name, "group-name"),
            (pwd.getpwuid, uid, "uid"),
            (grp.getgrgid, uid, "gid"),
        ):
            try:
                lookup(key)
            except KeyError:
                pass
            else:
                latest_lookups.append(label)
        if not latest_live and not latest_zombies and not latest_lookups:
            return {
                "pkillReturnCode": killed.returncode,
                "userDeleteReturnCode": user_delete.returncode,
                "groupDeleteReturnCode": group_delete.returncode,
                "liveUIDProcesses": [],
                "zombieUIDProcesses": [],
                "identityLookupSurvivors": [],
            }
        flush_directory_cache()
        time.sleep(0.05)
    raise WitnessError(
        "dedicated identity survived cleanup: "
        f"live={latest_live} zombies={latest_zombies} lookups={latest_lookups}"
    )


def create_apfs_image(image: Path) -> None:
    completed = run(
        [
            "/usr/bin/hdiutil",
            "create",
            "-quiet",
            "-size",
            "64m",
            "-type",
            "SPARSE",
            "-fs",
            "APFS",
            "-volname",
            VOLUME_NAME,
            "-ov",
            str(image),
        ]
    )
    if completed.returncode != 0:
        raise WitnessError(f"could not create APFS image: {completed.stderr[-1200:]!r}")


def attach_apfs(image: Path, mountpoint: Path, *, readonly: bool) -> str:
    command = [
        "/usr/bin/hdiutil",
        "attach",
        "-plist",
        "-nobrowse",
        "-owners",
        "on",
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
        detail = completed.stderr.decode("utf-8", errors="replace")[-1600:]
        raise WitnessError(f"could not attach APFS image at exact mountpoint: {detail!r}")
    payload = plistlib.loads(completed.stdout)
    for entity in payload.get("system-entities", []):
        if entity.get("mount-point") == str(mountpoint) and entity.get("dev-entry"):
            return str(entity["dev-entry"])
    raise WitnessError("APFS attach returned no exact mounted device")


def detach_apfs(device: str, *, force: bool = False) -> None:
    command = ["/usr/bin/hdiutil", "detach"]
    if force:
        command.append("-force")
    command.append(device)
    completed = run(command)
    if completed.returncode != 0:
        raise WitnessError(f"APFS detach failed: rc={completed.returncode} {completed.stderr[-1200:]!r}")


def iter_tree(root: Path) -> Iterable[Path]:
    yield root
    for current, directories, files in os.walk(root, topdown=True, followlinks=False):
        directories.sort()
        files.sort()
        current_path = Path(current)
        for name in directories:
            yield current_path / name
        for name in files:
            yield current_path / name


def freeze_tree_permissions(root: Path, build_gid: int) -> None:
    acl_cleanup = run(["/bin/chmod", "-RN", str(root)])
    if acl_cleanup.returncode != 0:
        raise WitnessError("could not strip ACLs from synthetic private-input snapshot")
    for path in iter_tree(root):
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode):
            raise WitnessError(f"snapshot unexpectedly contains symlink: {path}")
        if stat.S_ISDIR(metadata.st_mode):
            mode = 0o550
        elif stat.S_ISREG(metadata.st_mode):
            mode = 0o440
        else:
            raise WitnessError(f"snapshot unexpectedly contains special node: {path}")
        os.chown(path, 0, build_gid)
        os.chmod(path, mode)
        updated = path.lstat()
        if updated.st_uid != 0 or updated.st_gid != build_gid or stat.S_IMODE(updated.st_mode) != mode:
            raise WitnessError(f"snapshot authority materialization failed: {path}")


def build_environment(name: str, home: Path) -> dict[str, str]:
    temp = home / "tmp"
    temp.mkdir(parents=True, exist_ok=True)
    return {
        "HOME": str(home),
        "USER": name,
        "LOGNAME": name,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": str(temp),
        "LANG": "C",
        "LC_ALL": "C",
    }


def credential_probe_script() -> str:
    return r'''
import errno, hashlib, json, os, pathlib, pwd, sys
root = pathlib.Path(sys.argv[1])
expected_uid = int(sys.argv[2])
expected_gid = int(sys.argv[3])
expected_secret_sha = sys.argv[4]
secret = root / "TuyaRuntime" / "Sources" / "NembraTuyaPrivateConfig" / "NembraTuyaPrivateIdentity.swift"
security = root / "TuyaSDK" / "ThingSmartCryption.podspec"
observed = {
    "uid": os.getuid(), "euid": os.geteuid(), "gid": os.getgid(), "egid": os.getegid(),
    "user": pwd.getpwuid(os.geteuid()).pw_name,
}
if observed["uid"] != expected_uid or observed["euid"] != expected_uid or observed["gid"] != expected_gid or observed["egid"] != expected_gid:
    raise SystemExit("dedicated child credential mismatch")
secret_bytes = secret.read_bytes()
security_bytes = security.read_bytes()
if hashlib.sha256(secret_bytes).hexdigest() != expected_secret_sha or not security_bytes:
    raise SystemExit("dedicated child did not read the exact frozen private inputs")
def denied(operation):
    try:
        operation()
    except OSError as error:
        return error.errno in (errno.EACCES, errno.EPERM, errno.EROFS)
    return False
write_denied = denied(lambda: os.open(secret, os.O_WRONLY))
create_denied = denied(lambda: os.open(root / "TuyaRuntime" / "dedicated-write", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600))
chmod_denied = denied(lambda: os.chmod(secret, 0o640))
print(json.dumps({"credentialExact": True, "readExact": True, "writeDenied": write_denied, "createDenied": create_denied, "chmodDenied": chmod_denied}, sort_keys=True))
raise SystemExit(0 if write_denied and create_denied and chmod_denied else 9)
'''


def visible_write_probe(root: Path, uid: int, gid: int, groups: list[int]) -> dict[str, object]:
    script = r'''
import errno, json, os, pathlib, sys
root = pathlib.Path(sys.argv[1])
secret = root / "TuyaRuntime" / "Sources" / "NembraTuyaPrivateConfig" / "NembraTuyaPrivateIdentity.swift"
def denied(operation):
    try:
        operation()
    except OSError as error:
        return error.errno in (errno.EACCES, errno.EPERM, errno.EROFS)
    return False
write_denied = denied(lambda: os.open(secret, os.O_WRONLY))
create_denied = denied(lambda: os.open(root / "TuyaRuntime" / "field-write", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600))
print(json.dumps({"writeDenied": write_denied, "createDenied": create_denied}, sort_keys=True))
raise SystemExit(0 if write_denied and create_denied else 9)
'''
    completed = run(
        ["/usr/bin/python3", "-B", "-I", "-c", script, str(root)],
        env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": pwd.getpwuid(uid).pw_dir, "LANG": "C", "LC_ALL": "C"},
        user=uid,
        group=gid,
        extra_groups=groups,
    )
    if completed.returncode != 0:
        raise WitnessError(f"field-visible snapshot remained writable: {completed.stdout!r} {completed.stderr!r}")
    return json.loads(completed.stdout)


def root_erofs_probe(root: Path) -> bool:
    probe = root / "root-write-probe"
    try:
        descriptor = os.open(probe, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except OSError as error:
        return error.errno == errno.EROFS
    else:
        os.close(descriptor)
        try:
            probe.unlink()
        except OSError:
            pass
        return False


def wait_for_file(path: Path, timeout: float = 4.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return
        time.sleep(0.02)
    raise WitnessError(f"timed out waiting for synthetic attacker handshake: {path}")


def root_probe(field_uid: int, field_gid: int, synthetic_repo: Path, trigger: Path, ack: Path) -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        emit_error("environment", "overlay witness root phase requires root on macOS")
        return 70
    try:
        sudo_uid = int(os.environ["SUDO_UID"])
        sudo_gid = int(os.environ["SUDO_GID"])
        sudo_user = os.environ["SUDO_USER"]
    except (KeyError, ValueError) as error:
        emit_error("identity", f"missing sudo invoking identity: {error}")
        return 71
    if sudo_uid != field_uid or sudo_gid != field_gid or field_uid <= 0 or field_gid <= 0:
        emit_error("identity", "root phase is not bound to the exact pre-sudo field UID/GID")
        return 71
    field_account = pwd.getpwuid(field_uid)
    if field_account.pw_name != sudo_user or field_account.pw_gid != field_gid:
        emit_error("identity", "sudo tuple does not resolve to the exact field account")
        return 71

    local_secrets = synthetic_repo / "LocalSecrets"
    original_secret = local_secrets / "TuyaRuntime" / "Sources" / "NembraTuyaPrivateConfig" / "NembraTuyaPrivateIdentity.swift"
    if original_secret.read_bytes() != ORIGINAL_SECRET:
        emit_error("fixture", "synthetic private input was not exact before root snapshot")
        return 72

    workspace = Path(tempfile.mkdtemp(prefix="nembra-private-overlay-root.", dir="/private/tmp"))
    os.chown(workspace, 0, 0)
    os.chmod(workspace, 0o700)
    image = workspace / "private-input-overlay.sparseimage"
    staging_mount = workspace / "staging-mount"
    staging_mount.mkdir(mode=0o700)
    home = workspace / "build-home"
    home.mkdir(mode=0o700)
    build_uid = choose_ephemeral_id()
    build_name = f"nembraov{os.getpid()}"
    build_created = False
    writable_device: str | None = None
    readonly_device: str | None = None
    cleanup: dict[str, object] | None = None
    try:
        create_identity(build_name, build_uid, home)
        build_created = True
        os.chown(home, build_uid, build_uid)
        os.chmod(home, 0o700)
        environment = build_environment(build_name, home)
        os.chown(home / "tmp", build_uid, build_uid)
        os.chmod(home / "tmp", 0o700)
        build_groups = sorted(group for group in os.getgrouplist(build_name, build_uid) if group != build_uid)

        source_digest = tree_digest(local_secrets)
        original_secret_sha = sha256_file(original_secret)
        create_apfs_image(image)
        writable_device = attach_apfs(image, staging_mount, readonly=False)
        for child in ("TuyaSDK", "TuyaRuntime"):
            completed = run(["/usr/bin/ditto", "--noacl", str(local_secrets / child), str(staging_mount / child)])
            if completed.returncode != 0:
                raise WitnessError(f"could not copy synthetic private input into APFS snapshot: {child}")
        freeze_tree_permissions(staging_mount, build_uid)
        snapshot_digest = tree_digest(staging_mount)
        if snapshot_digest != source_digest:
            raise WitnessError("APFS private-input snapshot is not byte-identical to admitted source generation")
        detach_apfs(writable_device)
        writable_device = None

        # This is the central feasibility question: can macOS mount an APFS volume
        # over the existing non-empty field-owned LocalSecrets directory so generated
        # CocoaPods references keep their exact logical path while the original bytes
        # are hidden from the compiler?
        readonly_device = attach_apfs(image, local_secrets, readonly=True)
        mounted_digest = tree_digest(local_secrets)
        if mounted_digest != source_digest:
            raise WitnessError("read-only overlay changed the admitted private-input generation")
        if not root_erofs_probe(local_secrets):
            raise WitnessError("root mutation probe did not receive kernel EROFS on read-only overlay")

        child = run(
            [
                "/usr/bin/python3",
                "-B",
                "-I",
                "-c",
                credential_probe_script(),
                str(local_secrets),
                str(build_uid),
                str(build_uid),
                original_secret_sha,
            ],
            env=environment,
            user=build_uid,
            group=build_uid,
            extra_groups=[],
        )
        if child.returncode != 0:
            raise WitnessError(f"dedicated UID could not consume immutable private-input overlay: {child.stdout!r} {child.stderr!r}")
        dedicated_evidence = json.loads(child.stdout)
        if not all(dedicated_evidence.get(key) for key in ("credentialExact", "readExact", "writeDenied", "createDenied", "chmodDenied")):
            raise WitnessError(f"dedicated UID overlay predicate failed: {dedicated_evidence}")

        field_groups = sorted(group for group in os.getgrouplist(field_account.pw_name, field_gid) if group != field_gid)
        field_visible_evidence = visible_write_probe(local_secrets, field_uid, field_gid, field_groups)

        # Trigger the field-user process that opened the original 0600 secret before
        # this root phase mounted the snapshot. It can still mutate that hidden inode;
        # the mounted build view must remain frozen because it is a separate APFS copy.
        trigger.write_text("mutate-hidden-original\n", encoding="utf-8")
        os.chown(trigger, field_uid, field_gid)
        wait_for_file(ack)
        if original_secret.read_bytes() != ORIGINAL_SECRET:
            raise WitnessError("pre-open hidden-original mutation leaked through read-only overlay path")
        post_attack_digest = tree_digest(local_secrets)
        if post_attack_digest != source_digest:
            raise WitnessError("pre-open hidden-original mutation changed mounted build-view generation")

        detach_apfs(readonly_device)
        readonly_device = None
        if original_secret.read_bytes() != ATTACKER_SECRET:
            raise WitnessError("hidden-original mutator did not actually change the underlying field-owned inode")

        cleanup = remove_identity_strict(build_name, build_uid)
        build_created = False
        evidence = {
            "schemaVersion": 1,
            "fieldUID": field_uid,
            "buildUID": build_uid,
            "logicalLocalSecretsPathPreserved": True,
            "overlayMountedOverNonEmptyDirectory": True,
            "apfsOwnersEnabled": True,
            "readOnlyOverlayRootEROFS": True,
            "snapshotMatchesAdmittedGeneration": True,
            "dedicatedUIDReadExact": True,
            "dedicatedUIDWriteDenied": True,
            "dedicatedUIDCreateDenied": True,
            "dedicatedUIDChmodDenied": True,
            "fieldUIDVisibleWriteDenied": bool(field_visible_evidence.get("writeDenied")),
            "fieldUIDVisibleCreateDenied": bool(field_visible_evidence.get("createDenied")),
            "preopenedHiddenOriginalMutationOccurred": True,
            "preopenedHiddenOriginalMutationIsolatedFromBuildView": True,
            "normalReadOnlyDetachRequired": True,
            "originalGenerationRevealedAfterDetach": True,
            "buildIdentityCleanup": cleanup,
            "realPrivateTuyaBytesExercised": False,
            "xcodebuildExercised": False,
            "signingExercised": False,
            "automaticProvisioningExercised": False,
            "deviceExercised": False,
            "bluetoothExercised": False,
            "productionBytesChanged": False,
            "productionAcceptanceClaimed": False,
            "physicalAuthorityCreated": False,
        }
        print(SUCCESS_MARKER + json.dumps(evidence, sort_keys=True))
        return 0
    except Exception as error:
        emit_error("overlay", f"private-input APFS overlay witness failed: {type(error).__name__}: {error}")
        return 79
    finally:
        if readonly_device is not None:
            try:
                detach_apfs(readonly_device, force=True)
            except Exception:
                pass
        if writable_device is not None:
            try:
                detach_apfs(writable_device, force=True)
            except Exception:
                pass
        if build_created:
            try:
                remove_identity_strict(build_name, build_uid)
            except Exception:
                pass
        shutil.rmtree(workspace, ignore_errors=True)


def mutator(secret: Path, trigger: Path, ready: Path, ack: Path) -> int:
    descriptor = os.open(secret, os.O_RDWR)
    try:
        ready.write_text("ready\n", encoding="utf-8")
        deadline = time.monotonic() + 20.0
        while time.monotonic() < deadline and not trigger.exists():
            time.sleep(0.02)
        if not trigger.exists():
            return 5
        os.lseek(descriptor, 0, os.SEEK_SET)
        os.write(descriptor, ATTACKER_SECRET)
        os.ftruncate(descriptor, len(ATTACKER_SECRET))
        os.fsync(descriptor)
        ack.write_text("mutated\n", encoding="utf-8")
        return 0
    finally:
        os.close(descriptor)


def create_synthetic_private_tree(repo: Path) -> Path:
    repo.mkdir(mode=0o755)
    local = repo / "LocalSecrets"
    paths = [
        local,
        local / "TuyaSDK",
        local / "TuyaSDK" / "Build",
        local / "TuyaRuntime",
        local / "TuyaRuntime" / "Sources",
        local / "TuyaRuntime" / "Sources" / "NembraTuyaPrivateConfig",
    ]
    for path in paths:
        path.mkdir(mode=0o700)
        os.chmod(path, 0o700)
    files = {
        local / "TuyaSDK" / "ThingSmartCryption.podspec": b"Pod::Spec.new { |s| s.name = 'SyntheticThingSmartCryption' }\n",
        local / "TuyaSDK" / "Build" / "SyntheticSecurityBinary": b"synthetic-security-sdk-bytes\n",
        local / "TuyaRuntime" / "NembraTuyaPrivateConfig.podspec": b"Pod::Spec.new { |s| s.name = 'SyntheticNembraTuyaPrivateConfig' }\n",
        local / "TuyaRuntime" / "Sources" / "NembraTuyaPrivateConfig" / "NembraTuyaPrivateIdentity.swift": ORIGINAL_SECRET,
    }
    for path, payload in files.items():
        path.write_bytes(payload)
        os.chmod(path, 0o600)
    return local / "TuyaRuntime" / "Sources" / "NembraTuyaPrivateConfig" / "NembraTuyaPrivateIdentity.swift"


def parent_probe() -> int:
    if sys.platform != "darwin":
        emit_error("environment", "private-input APFS overlay validation requires macOS")
        return 80
    field_uid = os.getuid()
    field_gid = os.getgid()
    if field_uid <= 0 or field_gid <= 0 or os.geteuid() != field_uid or os.getegid() != field_gid:
        emit_error("identity", "parent requires one stable ordinary non-root field identity")
        return 80
    if run(["/usr/bin/sudo", "-n", "/usr/bin/true"]).returncode != 0:
        emit_error("environment", "runner lacks noninteractive sudo required for synthetic APFS/identity lifecycle")
        return 80

    workspace = Path(tempfile.mkdtemp(prefix="nembra-private-overlay-field.", dir="/private/tmp"))
    os.chmod(workspace, 0o700)
    repo = workspace / "SyntheticNembra"
    secret = create_synthetic_private_tree(repo)
    trigger = workspace / "trigger"
    ready = workspace / "mutator-ready"
    ack = workspace / "mutator-ack"
    mutator_process = subprocess.Popen(
        [
            "/usr/bin/python3",
            "-B",
            "-I",
            str(Path(__file__).resolve()),
            "--mutator",
            str(secret),
            str(trigger),
            str(ready),
            str(ack),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        wait_for_file(ready)
        completed = run(
            [
                "/usr/bin/sudo",
                "-n",
                "/usr/bin/python3",
                "-B",
                "-I",
                str(Path(__file__).resolve()),
                "--root-probe",
                "--field-uid",
                str(field_uid),
                "--field-gid",
                str(field_gid),
                "--synthetic-repo",
                str(repo),
                "--trigger",
                str(trigger),
                "--ack",
                str(ack),
            ]
        )
        sys.stdout.write(completed.stdout)
        sys.stderr.write(completed.stderr)
        try:
            mutator_out, mutator_err = mutator_process.communicate(timeout=3.0)
        except subprocess.TimeoutExpired:
            mutator_process.kill()
            mutator_out, mutator_err = mutator_process.communicate(timeout=2.0)
            emit_error("fixture", "synthetic pre-open mutator did not terminate")
            return 81
        if mutator_process.returncode != 0:
            emit_error("fixture", f"synthetic pre-open mutator failed: {mutator_out!r} {mutator_err!r}")
            return 81
        return completed.returncode
    finally:
        if mutator_process.poll() is None:
            mutator_process.kill()
            try:
                mutator_process.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                pass
        shutil.rmtree(workspace, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--field-uid", type=int)
    parser.add_argument("--field-gid", type=int)
    parser.add_argument("--synthetic-repo", type=Path)
    parser.add_argument("--trigger", type=Path)
    parser.add_argument("--ack", type=Path)
    parser.add_argument("--mutator", action="store_true")
    parser.add_argument("mutator_args", nargs="*")
    args = parser.parse_args()
    if args.mutator:
        if len(args.mutator_args) != 4:
            return 83
        return mutator(*(Path(value) for value in args.mutator_args))
    if args.root_probe:
        required = (args.field_uid, args.field_gid, args.synthetic_repo, args.trigger, args.ack)
        if any(value is None for value in required):
            emit_error("arguments", "root probe requires exact field identity and synthetic fixture paths")
            return 83
        return root_probe(
            int(args.field_uid),
            int(args.field_gid),
            Path(args.synthetic_repo),
            Path(args.trigger),
            Path(args.ack),
        )
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
