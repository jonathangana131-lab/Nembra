#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any, Callable

PROC = "ES80-AUTHENTICATED-STATIONARY-v1"
BUNDLE = "com.jonathangana131.nembra.capturelearn"
APP_NAME = "Nembra Capture.app"
IPA_NAME = "NembraAuthenticatedStationaryField.ipa"
MAX_ARCHIVE_BYTES = 1_500_000_000


class SignedArtifactError(RuntimeError):
    pass


def _sha_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _sha_file(path: Path) -> str:
    try:
        fd = os.open(
            path,
            os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0),
        )
    except OSError as error:
        raise SignedArtifactError(f"could not open regular file: {path}") from error
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise SignedArtifactError(f"file is not a single-link regular file: {path}")
        digest = hashlib.sha256()
        while True:
            chunk = os.read(fd, 1 << 20)
            if not chunk:
                break
            digest.update(chunk)
        after = os.fstat(fd)
    finally:
        os.close(fd)
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
        after.st_dev,
        after.st_ino,
        after.st_size,
        after.st_mtime_ns,
        after.st_ctime_ns,
    ):
        raise SignedArtifactError(f"file changed while hashing: {path}")
    return digest.hexdigest()


def _tree_manifest(root: Path) -> tuple[str, list[dict[str, Any]]]:
    root = root.resolve(strict=True)
    entries: list[dict[str, Any]] = []
    for path in sorted(root.rglob("*"), key=lambda value: value.relative_to(root).as_posix()):
        rel = path.relative_to(root).as_posix()
        metadata = path.lstat()
        if stat.S_ISLNK(metadata.st_mode):
            raise SignedArtifactError(f"signed app contains unsupported symlink: {rel}")
        if stat.S_ISDIR(metadata.st_mode):
            entries.append(
                {"path": rel + "/", "mode": stat.S_IMODE(metadata.st_mode), "type": "directory"}
            )
            continue
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise SignedArtifactError(
                f"signed app entry is not a single-link regular file: {rel}"
            )
        entries.append(
            {
                "path": rel,
                "mode": stat.S_IMODE(metadata.st_mode),
                "type": "file",
                "size": metadata.st_size,
                "sha256": _sha_file(path),
            }
        )
    raw = (
        "\n".join(
            f"{entry['type']}\t{entry['mode']:04o}\t{entry['path']}\t"
            f"{entry.get('size', '')}\t{entry.get('sha256', '')}"
            for entry in entries
        )
        + "\n"
    ).encode()
    return _sha_bytes(raw), entries


def _run(cmd: list[str]) -> subprocess.CompletedProcess[bytes]:
    try:
        result = subprocess.run(
            cmd,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={"PATH": "/usr/bin:/bin"},
        )
    except OSError as error:
        raise SignedArtifactError(f"could not execute trusted tool: {cmd[0]}") from error
    if result.returncode != 0:
        raise SignedArtifactError(f"trusted tool failed: {Path(cmd[0]).name}")
    return result


def _codesign_identity(
    app: Path,
    runner: Callable[[list[str]], subprocess.CompletedProcess[bytes]] = _run,
) -> tuple[str, str]:
    runner(["/usr/bin/codesign", "--verify", "--strict", "--deep", str(app)])
    details = runner(["/usr/bin/codesign", "-d", "--verbose=4", str(app)])
    text = (details.stdout + b"\n" + details.stderr).decode("utf-8", errors="replace")
    identifier = ""
    team = ""
    for line in text.splitlines():
        if line.startswith("Identifier="):
            identifier = line.split("=", 1)[1].strip()
        elif line.startswith("TeamIdentifier="):
            team = line.split("=", 1)[1].strip()
    if identifier != BUNDLE or not team:
        raise SignedArtifactError(
            "codesign identifier/team does not match current Capture authority"
        )
    return team, identifier


def _signed_entitlements(
    app: Path,
    runner: Callable[[list[str]], subprocess.CompletedProcess[bytes]] = _run,
) -> dict[str, Any]:
    payload = runner(["/usr/bin/codesign", "-d", "--entitlements", ":-", "--xml", str(app)])
    raw = payload.stdout + b"\n" + payload.stderr
    start = raw.find(b"<?xml")
    end = raw.rfind(b"</plist>")
    if start < 0 or end < start:
        raise SignedArtifactError("signed Capture entitlements are not a plist")
    try:
        value = plistlib.loads(raw[start : end + len(b"</plist>")])
    except Exception as error:
        raise SignedArtifactError("signed Capture entitlements are invalid") from error
    if not isinstance(value, dict):
        raise SignedArtifactError("signed Capture entitlements are not a dictionary")
    return value


def _profile(
    app: Path,
    intended_device: str,
    runner: Callable[[list[str]], subprocess.CompletedProcess[bytes]] = _run,
) -> tuple[dict[str, Any], str]:
    profile_path = app / "embedded.mobileprovision"
    profile_sha = _sha_file(profile_path)
    decoded = runner(["/usr/bin/security", "cms", "-D", "-i", str(profile_path)]).stdout
    try:
        profile = plistlib.loads(decoded)
    except Exception as error:
        raise SignedArtifactError("embedded provisioning profile is not a plist") from error
    if not isinstance(profile, dict):
        raise SignedArtifactError("embedded provisioning profile is not a dictionary")
    devices = profile.get("ProvisionedDevices")
    if not isinstance(devices, list) or intended_device not in devices:
        raise SignedArtifactError(
            "embedded provisioning profile does not admit intended iPhone"
        )
    return profile, profile_sha


def _app_evidence(
    app: Path,
    *,
    source: str,
    dependency_sha: str,
    intended_device: str,
    runner: Callable[[list[str]], subprocess.CompletedProcess[bytes]] = _run,
) -> dict[str, Any]:
    if not app.is_dir() or app.is_symlink():
        raise SignedArtifactError("signed Capture app is not a regular directory")
    info_path = app / "Info.plist"
    try:
        info = plistlib.loads(info_path.read_bytes())
    except Exception as error:
        raise SignedArtifactError("signed Capture Info.plist is invalid") from error
    expected = {
        "CFBundleIdentifier": BUNDLE,
        "NembraCaptureBuildIdentifier": f"capture-v14-{source[:12]}",
        "NembraCaptureSourceCommitSHA": source,
        "NembraCaptureTuyaDependencyLockSHA256": dependency_sha,
        "NembraCaptureProcedureIdentifier": PROC,
    }
    if any(info.get(key) != value for key, value in expected.items()):
        raise SignedArtifactError("signed Capture Info.plist provenance mismatch")

    team, identifier = _codesign_identity(app, runner)
    signed_entitlements = _signed_entitlements(app, runner)
    if signed_entitlements.get("com.apple.developer.applesignin") != ["Default"] or signed_entitlements.get("application-identifier") != f"{team}.{BUNDLE}" or signed_entitlements.get("com.apple.developer.team-identifier") != team:
        raise SignedArtifactError("effective signed Capture entitlements do not match current application authority")
    profile, profile_sha = _profile(app, intended_device, runner)
    team_ids = profile.get("TeamIdentifier")
    entitlements = profile.get("Entitlements")
    if not isinstance(team_ids, list) or team not in team_ids or not isinstance(entitlements, dict):
        raise SignedArtifactError("provisioning team does not match code signature")
    app_identifier = entitlements.get("application-identifier")
    profile_team = entitlements.get("com.apple.developer.team-identifier")
    if app_identifier != f"{team}.{BUNDLE}" or profile_team != team:
        raise SignedArtifactError(
            "provisioning application identity does not match signed Capture"
        )

    tree_sha, _ = _tree_manifest(app)
    return {
        "treeSHA256": tree_sha,
        "embeddedProvisioningProfileSHA256": profile_sha,
        "signingTeamIdentifier": team,
        "applicationIdentifier": app_identifier,
        "codesignVerified": True,
        "intendedDeviceIncluded": True,
    }


def _safe_zip_members(ipa: Path) -> list[zipfile.ZipInfo]:
    try:
        archive = zipfile.ZipFile(ipa)
    except zipfile.BadZipFile as error:
        raise SignedArtifactError("retained IPA is not a valid ZIP archive") from error
    with archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if len(names) != len(set(names)) or not infos:
            raise SignedArtifactError("retained IPA contains duplicate or no entries")
        total = 0
        for info in infos:
            name = info.filename
            if "\\" in name:
                raise SignedArtifactError("retained IPA contains backslash path")
            pure = PurePosixPath(name)
            if (
                pure.is_absolute()
                or ".." in pure.parts
                or not pure.parts
                or pure.parts[0] != "Payload"
            ):
                raise SignedArtifactError("retained IPA contains unsafe path")
            mode = (info.external_attr >> 16) & 0xFFFF
            kind = stat.S_IFMT(mode)
            if kind not in (0, stat.S_IFREG, stat.S_IFDIR):
                raise SignedArtifactError("retained IPA contains unsupported special entry")
            total += info.file_size
            if total > MAX_ARCHIVE_BYTES:
                raise SignedArtifactError("retained IPA expands beyond safety limit")
        app_roots = {
            "/".join(PurePosixPath(name).parts[:2])
            for name in names
            if len(PurePosixPath(name).parts) >= 2
            and PurePosixPath(name).parts[1].endswith(".app")
        }
        if app_roots != {f"Payload/{APP_NAME}"}:
            raise SignedArtifactError(
                "retained IPA must contain exactly the canonical Capture app"
            )
        return infos


def _write_zip_from_app(app: Path, destination: Path) -> None:
    root_prefix = PurePosixPath("Payload") / APP_NAME
    paths = [app, *app.rglob("*")]
    paths.sort(
        key=lambda path: (
            0 if path == app else 1,
            path.relative_to(app).as_posix() if path != app else "",
        )
    )
    with zipfile.ZipFile(
        destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        for path in paths:
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                raise SignedArtifactError("signed app contains unsupported symlink")
            rel = root_prefix if path == app else root_prefix / path.relative_to(app).as_posix()
            if stat.S_ISDIR(metadata.st_mode):
                info = zipfile.ZipInfo(rel.as_posix().rstrip("/") + "/")
                info.create_system = 3
                info.external_attr = (
                    (stat.S_IFDIR | stat.S_IMODE(metadata.st_mode)) << 16
                ) | 0x10
                archive.writestr(info, b"")
            elif stat.S_ISREG(metadata.st_mode) and metadata.st_nlink == 1:
                info = zipfile.ZipInfo(rel.as_posix())
                info.create_system = 3
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (
                    stat.S_IFREG | stat.S_IMODE(metadata.st_mode)
                ) << 16
                with path.open("rb") as source, archive.open(info, "w") as sink:
                    shutil.copyfileobj(source, sink, length=1 << 20)
            else:
                raise SignedArtifactError(
                    "signed app contains unsupported filesystem entry"
                )


def _extract_safe(ipa: Path, destination: Path) -> Path:
    _safe_zip_members(ipa)
    with zipfile.ZipFile(ipa) as archive:
        for info in archive.infolist():
            pure = PurePosixPath(info.filename)
            target = destination.joinpath(*pure.parts)
            mode = (info.external_attr >> 16) & 0xFFFF
            if info.is_dir() or stat.S_ISDIR(mode):
                target.mkdir(parents=True, exist_ok=True)
                os.chmod(target, stat.S_IMODE(mode) or 0o755)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            fd = os.open(
                target,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                stat.S_IMODE(mode) or 0o600,
            )
            try:
                with os.fdopen(fd, "wb") as sink, archive.open(info, "r") as source:
                    fd = -1
                    shutil.copyfileobj(source, sink, length=1 << 20)
            finally:
                if fd >= 0:
                    os.close(fd)
            os.chmod(target, stat.S_IMODE(mode) or 0o600)
    return destination / "Payload" / APP_NAME


def _publish_no_replace(staging: Path, output: Path) -> None:
    if output.exists() or output.is_symlink():
        raise SignedArtifactError(f"retained IPA output already exists: {output}")
    os.chmod(staging, 0o600)
    with staging.open("rb") as handle:
        os.fsync(handle.fileno())
    try:
        os.link(staging, output, follow_symlinks=False)
    except FileExistsError as error:
        raise SignedArtifactError("retained IPA output appeared during publication") from error
    before = staging.lstat()
    published = output.lstat()
    if (
        (before.st_dev, before.st_ino) != (published.st_dev, published.st_ino)
        or before.st_nlink != 2
        or published.st_nlink != 2
    ):
        output.unlink(missing_ok=True)
        raise SignedArtifactError("retained IPA publication lost inode custody")
    staging.unlink()
    if output.lstat().st_nlink != 1:
        output.unlink(missing_ok=True)
        raise SignedArtifactError("retained IPA has unexpected hard-link alias")
    directory = os.open(output.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def reinspect_retained(
    ipa: Path,
    candidate_repo: Path,
    source: str,
    device_file: Path,
    install: dict[str, Any],
    *,
    runner: Callable[[list[str]], subprocess.CompletedProcess[bytes]] = _run,
) -> dict[str, Any]:
    repository = candidate_repo.expanduser().resolve(strict=True)
    intended_device = _read_intended_device(device_file, repository)
    dependency_sha = _sha_file(repository / "Podfile.lock")
    if install.get("sourceCommitSHA") != source or install.get("bundleIdentifier") != BUNDLE:
        raise SignedArtifactError("private installer subject does not match retained artifact subject")
    ipa = ipa.expanduser().resolve(strict=True)
    metadata=ipa.lstat()
    if ipa.name != IPA_NAME or ipa.is_symlink() or not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600 or metadata.st_uid != os.getuid() or metadata.st_nlink != 1:
        raise SignedArtifactError("retained IPA custody is invalid")
    with tempfile.TemporaryDirectory(prefix="nembra-auth-stationary-reinspect-") as temporary:
        app = _extract_safe(ipa, Path(temporary))
        evidence = _app_evidence(app, source=source, dependency_sha=dependency_sha, intended_device=intended_device, runner=runner)
    return {
        "authority":"nembra-authenticated-stationary-retained-signed-artifact-v1",
        "sourceCommitSHA":source,
        "buildIdentifier":f"capture-v14-{source[:12]}",
        "bundleIdentifier":BUNDLE,
        "procedureIdentifier":PROC,
        "tuyaDependencyLockSHA256":dependency_sha,
        "retainedIPASHA256":_sha_file(ipa),
        "retainedAppTreeSHA256":evidence["treeSHA256"],
        "embeddedProvisioningProfileSHA256":evidence["embeddedProvisioningProfileSHA256"],
        "signingTeamIdentifier":evidence["signingTeamIdentifier"],
        "applicationIdentifier":evidence["applicationIdentifier"],
        "codesignVerified":True,
        "intendedDeviceIncluded":True,
        "physicalAuthorityCreated":False,
    }


def _private_file_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _repository_directory_identity(repository_root: Path) -> tuple[int, int]:
    try:
        repository = repository_root.expanduser().resolve(strict=True)
        metadata = os.stat(repository)
    except OSError as error:
        raise SignedArtifactError("candidate repository privacy boundary is unavailable") from error
    if not stat.S_ISDIR(metadata.st_mode):
        raise SignedArtifactError("candidate repository privacy boundary is not a directory")
    return metadata.st_dev, metadata.st_ino


def _open_private_identifier_without_symlink_components(path: Path, repository_root: Path) -> int:
    if (
        not hasattr(os, "O_NOFOLLOW")
        or not hasattr(os, "O_DIRECTORY")
        or os.open not in os.supports_dir_fd
    ):
        raise SignedArtifactError("platform cannot enforce component-wise private-device custody")

    expanded = path.expanduser()
    if (
        not expanded.is_absolute()
        or expanded.anchor != os.sep
        or not expanded.parts[1:]
        or any(component in ("", ".", "..") for component in expanded.parts[1:])
    ):
        raise SignedArtifactError("private intended-device path must be canonical absolute")

    repository_identity = _repository_directory_identity(repository_root)
    close_on_exec = getattr(os, "O_CLOEXEC", 0)
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | close_on_exec
    file_flags = os.O_RDONLY | os.O_NOFOLLOW | close_on_exec

    try:
        parent_descriptor = os.open(os.sep, directory_flags)
    except OSError as error:
        raise SignedArtifactError("private intended-device path root is unavailable") from error

    try:
        root_metadata = os.fstat(parent_descriptor)
        if (root_metadata.st_dev, root_metadata.st_ino) == repository_identity:
            raise SignedArtifactError("private intended-device identifier must remain outside repository")

        for component in expanded.parts[1:-1]:
            try:
                next_descriptor = os.open(component, directory_flags, dir_fd=parent_descriptor)
            except OSError as error:
                raise SignedArtifactError(
                    "private intended-device path contains an unsafe directory component"
                ) from error
            next_metadata = os.fstat(next_descriptor)
            if (next_metadata.st_dev, next_metadata.st_ino) == repository_identity:
                os.close(next_descriptor)
                raise SignedArtifactError(
                    "private intended-device identifier must remain outside repository"
                )
            os.close(parent_descriptor)
            parent_descriptor = next_descriptor

        try:
            return os.open(expanded.parts[-1], file_flags, dir_fd=parent_descriptor)
        except OSError as error:
            raise SignedArtifactError(
                "private intended-device identifier is not a readable non-symlink file"
            ) from error
    finally:
        os.close(parent_descriptor)


def _read_intended_device(path: Path, repository_root: Path) -> str:
    descriptor = _open_private_identifier_without_symlink_components(path, repository_root)
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or stat.S_IMODE(before.st_mode) != 0o600
            or before.st_uid != os.getuid()
            or before.st_nlink != 1
            or before.st_size < 1
            or before.st_size > 160
        ):
            raise SignedArtifactError("private intended-device identifier custody is invalid")

        chunks: list[bytes] = []
        remaining = 161
        while remaining > 0:
            chunk = os.read(descriptor, remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        after = os.fstat(descriptor)
        if len(raw) != before.st_size or _private_file_identity(after) != _private_file_identity(before):
            raise SignedArtifactError("private intended-device identifier changed while reading")
    finally:
        os.close(descriptor)

    try:
        value = raw.decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise SignedArtifactError(
            "private intended-device identifier is not UTF-8"
        ) from error
    if not value or len(value) > 160 or any(character.isspace() for character in value):
        raise SignedArtifactError("private intended-device identifier is malformed")
    return value


def retain_and_reinspect(
    candidate_repo: Path,
    source: str,
    device_file: Path,
    install: dict[str, Any],
    output_ipa: Path,
    *,
    runner: Callable[[list[str]], subprocess.CompletedProcess[bytes]] = _run,
) -> dict[str, Any]:
    if not re.fullmatch(r"[0-9a-f]{40}", source):
        raise SignedArtifactError("source SHA is not canonical")
    if install.get("sourceCommitSHA") != source or install.get("bundleIdentifier") != BUNDLE:
        raise SignedArtifactError("private installer subject does not match artifact subject")
    repository = candidate_repo.expanduser().resolve(strict=True)
    intended_device = _read_intended_device(device_file, repository)
    dependency_sha = _sha_file(repository / "Podfile.lock")
    built_app = (
        Path(os.environ.get("TMPDIR", "/tmp"))
        / "NembraAuthenticatedCaptureDerived"
        / "Build"
        / "Products"
        / "Debug-iphoneos"
        / APP_NAME
    )
    before = _app_evidence(
        built_app,
        source=source,
        dependency_sha=dependency_sha,
        intended_device=intended_device,
        runner=runner,
    )

    output = output_ipa.expanduser()
    output.parent.mkdir(parents=True, exist_ok=True)
    parent = output.parent.resolve(strict=True)
    output = parent / output.name
    if output.name != IPA_NAME:
        raise SignedArtifactError(f"retained IPA filename must be {IPA_NAME}")

    staging_dir = Path(
        tempfile.mkdtemp(prefix=".nembra-auth-stationary-signed-", dir=parent)
    )
    os.chmod(staging_dir, 0o700)
    staged = staging_dir / IPA_NAME
    try:
        _write_zip_from_app(built_app, staged)
        _safe_zip_members(staged)
        with tempfile.TemporaryDirectory(
            prefix="nembra-auth-stationary-reinspect-"
        ) as temporary:
            extracted_app = _extract_safe(staged, Path(temporary))
            after = _app_evidence(
                extracted_app,
                source=source,
                dependency_sha=dependency_sha,
                intended_device=intended_device,
                runner=runner,
            )
        if before != after:
            raise SignedArtifactError(
                "retained IPA reinspection differs from exact built signed app"
            )
        ipa_sha = _sha_file(staged)
        _publish_no_replace(staged, output)
        if _sha_file(output) != ipa_sha:
            output.unlink(missing_ok=True)
            raise SignedArtifactError("retained IPA changed after publication")
    finally:
        shutil.rmtree(staging_dir, ignore_errors=True)

    return {
        "authority": "nembra-authenticated-stationary-retained-signed-artifact-v1",
        "sourceCommitSHA": source,
        "buildIdentifier": f"capture-v14-{source[:12]}",
        "bundleIdentifier": BUNDLE,
        "procedureIdentifier": PROC,
        "tuyaDependencyLockSHA256": dependency_sha,
        "retainedIPASHA256": ipa_sha,
        "retainedAppTreeSHA256": after["treeSHA256"],
        "embeddedProvisioningProfileSHA256": after[
            "embeddedProvisioningProfileSHA256"
        ],
        "signingTeamIdentifier": after["signingTeamIdentifier"],
        "applicationIdentifier": after["applicationIdentifier"],
        "codesignVerified": True,
        "intendedDeviceIncluded": True,
        "physicalAuthorityCreated": False,
    }
