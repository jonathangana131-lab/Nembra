#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import plistlib
import re
import select
import stat
import subprocess
import sys
from pathlib import Path
from typing import Callable, Iterable, Protocol, Sequence

SCHEMA = b"nembra-capture-signed-app-install-subject-v1\0"


class InstallCustodyError(RuntimeError):
    pass


def _identity(metadata: os.stat_result) -> tuple[int, ...]:
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


def _feed(digest: "hashlib._Hash", payload: bytes) -> None:
    digest.update(len(payload).to_bytes(8, "big"))
    digest.update(payload)


def _safe_root(root: Path) -> tuple[Path, os.stat_result]:
    root = root.absolute()
    try:
        metadata = root.lstat()
    except OSError as error:
        raise InstallCustodyError("signed Capture app is unavailable") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise InstallCustodyError("signed Capture app must be one real directory")
    try:
        resolved = root.resolve(strict=True)
    except OSError as error:
        raise InstallCustodyError("signed Capture app could not be canonicalized") from error
    return resolved, metadata


def _stable_file_digest(path: Path, expected_identity: tuple[int, ...]) -> bytes:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise InstallCustodyError("signed-app custody requires O_NOFOLLOW support")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise InstallCustodyError(f"signed app file could not be opened safely: {path.name}") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or _identity(before) != expected_identity:
            raise InstallCustodyError("signed app changed before a file could be fingerprinted")
        digest = hashlib.sha256()
        count = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            count += len(chunk)
            digest.update(chunk)
        after = os.fstat(descriptor)
        if _identity(after) != expected_identity or count != after.st_size:
            raise InstallCustodyError("signed app file changed while it was fingerprinted")
        current = path.lstat()
        if stat.S_ISLNK(current.st_mode) or _identity(current) != expected_identity:
            raise InstallCustodyError("signed app pathname changed while it was fingerprinted")
        return digest.digest()
    finally:
        os.close(descriptor)


def _assert_entry(path: Path, expected_identity: tuple[int, ...], kind: str, symlink_target: str = "") -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise InstallCustodyError("signed app changed while its install subject was fingerprinted") from error
    if _identity(metadata) != expected_identity:
        raise InstallCustodyError("signed app changed while its install subject was fingerprinted")
    if kind == "D" and not stat.S_ISDIR(metadata.st_mode):
        raise InstallCustodyError("signed app entry changed type during fingerprinting")
    if kind == "F" and not stat.S_ISREG(metadata.st_mode):
        raise InstallCustodyError("signed app entry changed type during fingerprinting")
    if kind == "L":
        if not stat.S_ISLNK(metadata.st_mode):
            raise InstallCustodyError("signed app symlink changed type during fingerprinting")
        try:
            if os.readlink(path) != symlink_target:
                raise InstallCustodyError("signed app symlink target changed during fingerprinting")
        except OSError as error:
            raise InstallCustodyError("signed app symlink changed during fingerprinting") from error


def _directory_members(path: Path) -> tuple[str, ...]:
    try:
        return tuple(sorted(os.listdir(path), key=os.fsencode))
    except OSError as error:
        raise InstallCustodyError("signed app directory changed during fingerprinting") from error


def fingerprint_bundle(root: Path) -> str:
    root, root_metadata = _safe_root(root)
    root_identity = _identity(root_metadata)
    entries: list[tuple[str, str, int, bytes]] = []
    observed: list[tuple[Path, tuple[int, ...], str, str]] = [(root, root_identity, "D", "")]
    members: dict[Path, tuple[str, ...]] = {}

    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        members[current] = tuple(sorted((*directory_names, *file_names), key=os.fsencode))
        retained: list[str] = []
        for name in sorted(directory_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(path)
                try:
                    path.resolve(strict=True).relative_to(root)
                except (OSError, ValueError) as error:
                    raise InstallCustodyError("signed app contains a broken or escaping symlink") from error
                observed.append((path, identity, "L", target))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISDIR(metadata.st_mode):
                observed.append((path, identity, "D", ""))
                entries.append(("D", relative, mode, b""))
                retained.append(name)
            else:
                raise InstallCustodyError("signed app contains an unsupported directory entry")
        directory_names[:] = retained

        for name in sorted(file_names, key=os.fsencode):
            path = current / name
            relative = path.relative_to(root).as_posix()
            metadata = path.lstat()
            identity = _identity(metadata)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(path)
                try:
                    path.resolve(strict=True).relative_to(root)
                except (OSError, ValueError) as error:
                    raise InstallCustodyError("signed app contains a broken or escaping symlink") from error
                observed.append((path, identity, "L", target))
                entries.append(("L", relative, mode, os.fsencode(target)))
            elif stat.S_ISREG(metadata.st_mode):
                content_digest = _stable_file_digest(path, identity)
                observed.append((path, identity, "F", ""))
                entries.append(("F", relative, mode, content_digest))
            else:
                raise InstallCustodyError("signed app contains an unsupported file entry")

    for path, identity, kind, target in observed:
        _assert_entry(path, identity, kind, target)
    for directory, expected in members.items():
        if _directory_members(directory) != expected:
            raise InstallCustodyError("signed app membership changed during fingerprinting")

    digest = hashlib.sha256()
    digest.update(SCHEMA)
    _feed(digest, stat.S_IMODE(root_metadata.st_mode).to_bytes(4, "big"))
    for kind, relative, mode, payload in sorted(entries, key=lambda item: os.fsencode(item[1])):
        _feed(digest, kind.encode("ascii"))
        _feed(digest, os.fsencode(relative))
        _feed(digest, mode.to_bytes(4, "big"))
        _feed(digest, payload)
    return digest.hexdigest()


def _watch_paths(root: Path) -> tuple[Path, ...]:
    root, _ = _safe_root(root)
    paths: set[Path] = {root}
    for current_text, directory_names, file_names in os.walk(root, topdown=True, followlinks=False):
        current = Path(current_text)
        paths.add(current)
        retained: list[str] = []
        for name in directory_names:
            path = current / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                continue
            if not stat.S_ISDIR(metadata.st_mode):
                raise InstallCustodyError("signed app contains an unsupported directory entry")
            paths.add(path)
            retained.append(name)
        directory_names[:] = retained
        for name in file_names:
            path = current / name
            metadata = path.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                continue
            if not stat.S_ISREG(metadata.st_mode):
                raise InstallCustodyError("signed app contains an unsupported file entry")
            paths.add(path)
    return tuple(sorted(paths, key=lambda item: os.fsencode(str(item))))


class EventBackend(Protocol):
    def register(self, descriptor: int) -> None: ...
    def events(self, timeout: float) -> Sequence[object]: ...
    def close(self) -> None: ...


class KqueueVnodeBackend:
    def __init__(self) -> None:
        required = (
            "kqueue", "kevent", "KQ_FILTER_VNODE", "KQ_EV_ADD", "KQ_EV_ENABLE", "KQ_EV_CLEAR",
            "KQ_NOTE_DELETE", "KQ_NOTE_WRITE", "KQ_NOTE_EXTEND", "KQ_NOTE_LINK", "KQ_NOTE_RENAME", "KQ_NOTE_REVOKE",
        )
        missing = [name for name in required if not hasattr(select, name)]
        if missing:
            raise InstallCustodyError("macOS vnode monitoring is unavailable: " + ", ".join(missing))
        self._queue = select.kqueue()
        self._fflags = (
            select.KQ_NOTE_DELETE | select.KQ_NOTE_WRITE | select.KQ_NOTE_EXTEND |
            select.KQ_NOTE_LINK | select.KQ_NOTE_RENAME | select.KQ_NOTE_REVOKE
        )

    def register(self, descriptor: int) -> None:
        event = select.kevent(
            descriptor,
            filter=select.KQ_FILTER_VNODE,
            flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | select.KQ_EV_CLEAR,
            fflags=self._fflags,
        )
        self._queue.control([event], 0, 0)

    def events(self, timeout: float) -> Sequence[object]:
        return self._queue.control(None, 256, timeout)

    def close(self) -> None:
        self._queue.close()


def _open_watched(paths: Iterable[Path], backend: EventBackend) -> tuple[tuple[int, Path], ...]:
    opened: list[tuple[int, Path]] = []
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise InstallCustodyError("signed-app custody requires O_NOFOLLOW support")
    flags = os.O_RDONLY | nofollow | getattr(os, "O_CLOEXEC", 0)
    try:
        for path in paths:
            before = _identity(path.lstat())
            descriptor = os.open(path, flags)
            try:
                after_metadata = os.fstat(descriptor)
                if _identity(after_metadata) != before:
                    raise InstallCustodyError("signed app changed while install custody was armed")
                if not (stat.S_ISDIR(after_metadata.st_mode) or stat.S_ISREG(after_metadata.st_mode)):
                    raise InstallCustodyError("signed app contains an unwatchable install subject")
                backend.register(descriptor)
            except Exception:
                os.close(descriptor)
                raise
            opened.append((descriptor, path))
        return tuple(opened)
    except Exception:
        for descriptor, _ in opened:
            try:
                os.close(descriptor)
            except OSError:
                pass
        raise


def _close_watched(watched: Iterable[tuple[int, Path]]) -> None:
    for descriptor, _ in watched:
        try:
            os.close(descriptor)
        except OSError:
            pass


def _require_quiet(backend: EventBackend, message: str) -> None:
    if backend.events(0):
        raise InstallCustodyError(message)


def _extract_xml_plist(payload: bytes, label: str) -> dict:
    start = payload.find(b"<?xml")
    end = payload.rfind(b"</plist>")
    if start < 0 or end < start:
        raise InstallCustodyError(f"{label} did not contain one XML plist")
    try:
        value = plistlib.loads(payload[start:end + len(b"</plist>")])
    except Exception as error:
        raise InstallCustodyError(f"{label} XML plist could not be decoded") from error
    if not isinstance(value, dict):
        raise InstallCustodyError(f"{label} XML plist root is not a dictionary")
    return value


def _run_authority_command(
    command: Sequence[str],
    backend: EventBackend,
    run_factory: Callable[..., subprocess.CompletedProcess],
    label: str,
) -> subprocess.CompletedProcess:
    result = run_factory(list(command), stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    _require_quiet(backend, f"signed Capture app mutated while {label} was being verified")
    if result.returncode != 0:
        raise InstallCustodyError(f"{label} verification failed")
    return result


def verify_authority_and_seal(
    app: Path,
    *,
    expected_build_identifier: str,
    expected_source_sha: str,
    expected_tuya_lock_sha256: str,
    expected_procedure_id: str,
    expected_bundle_id: str,
    expected_team_id: str,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
    run_factory: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> str:
    if not expected_build_identifier:
        raise InstallCustodyError("expected build identifier is unavailable")
    if re.fullmatch(r"[0-9a-f]{40}", expected_source_sha) is None:
        raise InstallCustodyError("expected source SHA is malformed")
    if re.fullmatch(r"[0-9a-f]{64}", expected_tuya_lock_sha256) is None:
        raise InstallCustodyError("expected Tuya dependency-lock digest is malformed")
    if not expected_procedure_id or not expected_bundle_id:
        raise InstallCustodyError("expected Capture procedure or bundle identity is unavailable")
    if re.fullmatch(r"[A-Z0-9]{10}", expected_team_id) is None:
        raise InstallCustodyError("expected Apple Development team identity is malformed")

    accepted_digest = fingerprint_bundle(app)
    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    try:
        watched = _open_watched(_watch_paths(app), backend)
        if fingerprint_bundle(app) != accepted_digest:
            raise InstallCustodyError("signed Capture app changed while verification custody was armed")
        _require_quiet(backend, "signed Capture app changed before authority verification began")

        info_path = app / "Info.plist"
        try:
            info = plistlib.loads(info_path.read_bytes())
        except Exception as error:
            raise InstallCustodyError("signed Capture app Info.plist could not be decoded") from error
        _require_quiet(backend, "signed Capture app mutated while provenance was being verified")
        expected_info = {
            "NembraCaptureBuildIdentifier": expected_build_identifier,
            "NembraCaptureSourceCommitSHA": expected_source_sha,
            "NembraCaptureTuyaDependencyLockSHA256": expected_tuya_lock_sha256,
            "NembraCaptureProcedureIdentifier": expected_procedure_id,
            "CFBundleIdentifier": expected_bundle_id,
        }
        for key, expected in expected_info.items():
            if info.get(key) != expected:
                raise InstallCustodyError(f"signed Capture app {key} does not match accepted authority")

        closed_prefix = ["/usr/bin/env", "-i", "PATH=/usr/bin:/bin"]
        _run_authority_command(
            [*closed_prefix, "/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
            backend,
            run_factory,
            "recursive strict code signature",
        )
        entitlement_result = _run_authority_command(
            [*closed_prefix, "/usr/bin/codesign", "-d", "--entitlements", ":-", "--xml", str(app)],
            backend,
            run_factory,
            "effective signed entitlements",
        )
        entitlements = _extract_xml_plist(entitlement_result.stdout + entitlement_result.stderr, "signed entitlements")
        apple = entitlements.get("com.apple.developer.applesignin")
        application_identifier = entitlements.get("application-identifier")
        entitlement_team = entitlements.get("com.apple.developer.team-identifier")
        suffix = "." + expected_bundle_id
        if apple != ["Default"]:
            raise InstallCustodyError("signed Capture app is missing exact Sign in with Apple entitlement")
        if not isinstance(application_identifier, str) or not application_identifier.endswith(suffix):
            raise InstallCustodyError("signed Capture app application identifier does not match the Capture bundle")
        if "*" in application_identifier or application_identifier == suffix:
            raise InstallCustodyError("signed Capture app application identifier is wildcard or missing a concrete prefix")
        if entitlement_team != expected_team_id:
            raise InstallCustodyError("signed Capture app team identifier does not match accepted Apple team")

        profile = app / "embedded.mobileprovision"
        try:
            profile_metadata = profile.lstat()
        except OSError as error:
            raise InstallCustodyError("signed Capture app is missing embedded.mobileprovision") from error
        if stat.S_ISLNK(profile_metadata.st_mode) or not stat.S_ISREG(profile_metadata.st_mode):
            raise InstallCustodyError("embedded.mobileprovision must be one real regular file")
        profile_result = _run_authority_command(
            [*closed_prefix, "/usr/bin/security", "cms", "-D", "-i", str(profile)],
            backend,
            run_factory,
            "embedded provisioning profile",
        )
        try:
            profile_plist = plistlib.loads(profile_result.stdout)
        except Exception as error:
            raise InstallCustodyError("embedded provisioning profile plist could not be decoded") from error
        if not isinstance(profile_plist, dict):
            raise InstallCustodyError("embedded provisioning profile plist root is invalid")
        profile_entitlements = profile_plist.get("Entitlements", {})
        team_identifiers = profile_plist.get("TeamIdentifier")
        if not isinstance(profile_entitlements, dict):
            raise InstallCustodyError("embedded provisioning profile entitlements are invalid")
        if profile_entitlements.get("com.apple.developer.applesignin") != ["Default"]:
            raise InstallCustodyError("embedded provisioning profile lacks exact Sign in with Apple authority")
        if profile_entitlements.get("application-identifier") != application_identifier:
            raise InstallCustodyError("embedded provisioning profile application identifier does not match signed app")
        if profile_entitlements.get("com.apple.developer.team-identifier") != expected_team_id:
            raise InstallCustodyError("embedded provisioning profile entitlement team does not match accepted Apple team")
        if team_identifiers != [expected_team_id]:
            raise InstallCustodyError("embedded provisioning profile root TeamIdentifier does not match accepted Apple team")

        if fingerprint_bundle(app) != accepted_digest:
            raise InstallCustodyError("signed Capture app changed across authority verification")
        _require_quiet(backend, "signed Capture app mutated during final authority sealing")
        return accepted_digest
    finally:
        _close_watched(watched)
        backend.close()


def _stop_process(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def run_guarded_install(
    app: Path,
    expected_sha256: str,
    command: Sequence[str],
    *,
    backend_factory: Callable[[], EventBackend] = KqueueVnodeBackend,
    popen_factory: Callable[..., subprocess.Popen] = subprocess.Popen,
    poll_interval: float = 0.05,
) -> int:
    expected = expected_sha256.lower()
    if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
        raise InstallCustodyError("accepted signed-app subject digest is malformed")
    if not command:
        raise InstallCustodyError("no install command was supplied")
    if fingerprint_bundle(app) != expected:
        raise InstallCustodyError("signed Capture app changed after verification and before install custody")

    backend = backend_factory()
    watched: tuple[tuple[int, Path], ...] = ()
    process: subprocess.Popen | None = None
    try:
        watched = _open_watched(_watch_paths(app), backend)
        if fingerprint_bundle(app) != expected:
            raise InstallCustodyError("signed Capture app changed while install custody was armed")
        _require_quiet(backend, "signed Capture app changed before devicectl admission")

        process = popen_factory(list(command))
        while process.poll() is None:
            if backend.events(poll_interval):
                _stop_process(process)
                raise InstallCustodyError("signed Capture app mutated while devicectl was consuming it")

        _require_quiet(backend, "signed Capture app mutated at devicectl completion")
        if fingerprint_bundle(app) != expected:
            raise InstallCustodyError("signed Capture app changed across the devicectl install boundary")
        _require_quiet(backend, "signed Capture app mutated during final install-subject verification")
        return int(process.returncode or 0)
    finally:
        if process is not None and process.poll() is None:
            _stop_process(process)
        _close_watched(watched)
        backend.close()


def _parse(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Bind signed Capture.app authority to the devicectl install side effect.")
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--digest-only", action="store_true")
    parser.add_argument("--verify-authority-only", action="store_true")
    parser.add_argument("--expected-sha256")
    parser.add_argument("--expected-build-identifier")
    parser.add_argument("--expected-source-sha")
    parser.add_argument("--expected-tuya-lock-sha256")
    parser.add_argument("--expected-procedure-id")
    parser.add_argument("--expected-bundle-id")
    parser.add_argument("--expected-team-id")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args(list(argv))
    if arguments.command and arguments.command[0] == "--":
        arguments.command = arguments.command[1:]
    return arguments


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse(sys.argv[1:] if argv is None else argv)
    try:
        if arguments.digest_only:
            if arguments.verify_authority_only or arguments.expected_sha256 is not None or arguments.command:
                raise InstallCustodyError("digest-only mode does not accept verification/install authority arguments")
            print(fingerprint_bundle(arguments.app))
            return 0
        if arguments.verify_authority_only:
            required = {
                "--expected-build-identifier": arguments.expected_build_identifier,
                "--expected-source-sha": arguments.expected_source_sha,
                "--expected-tuya-lock-sha256": arguments.expected_tuya_lock_sha256,
                "--expected-procedure-id": arguments.expected_procedure_id,
                "--expected-bundle-id": arguments.expected_bundle_id,
                "--expected-team-id": arguments.expected_team_id,
            }
            missing = [name for name, value in required.items() if value is None]
            if missing or arguments.expected_sha256 is not None or arguments.command:
                raise InstallCustodyError("verify-authority-only mode requires exact expected authority and no install command")
            print(
                verify_authority_and_seal(
                    arguments.app,
                    expected_build_identifier=arguments.expected_build_identifier,
                    expected_source_sha=arguments.expected_source_sha,
                    expected_tuya_lock_sha256=arguments.expected_tuya_lock_sha256,
                    expected_procedure_id=arguments.expected_procedure_id,
                    expected_bundle_id=arguments.expected_bundle_id,
                    expected_team_id=arguments.expected_team_id,
                )
            )
            return 0
        if arguments.expected_sha256 is None:
            raise InstallCustodyError("--expected-sha256 is required for guarded installation")
        return run_guarded_install(arguments.app, arguments.expected_sha256, arguments.command)
    except InstallCustodyError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    except OSError as error:
        print(f"ERROR: signed-app install custody failed: {error}", file=sys.stderr)
        return 74


if __name__ == "__main__":
    raise SystemExit(main())
