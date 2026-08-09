#!/usr/bin/env python3
"""Independently re-inspect the exact retained ES80 field IPA for Final GO.

The retained signed-artifact inspection JSON is useful evidence, but it is still caller-supplied
bytes. Final GO therefore repeats the signing/provisioning inspection from the retained IPA itself
with absolute Apple tool paths and compares every signing field it promotes to the retained record.

This module proves software/installable authenticity only. It does not authorize Bluetooth writes,
prove ES80 identity/protocol semantics, collect physical telemetry, or itself authorize Experiment
One.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
from typing import Any, Callable, Final
import zipfile

REINSPECTION_AUTHORITY: Final = "independent-native-apple-signed-ipa-reinspection-v1"
INSPECTION_NAME: Final = "NembraCaptureSignedFieldArtifactInspection.json"
IPA_RELATIVE_PATH: Final = Path("build-evidence/NembraField.ipa")
EXPECTED_BUNDLE_ID: Final = "com.jonathangana131.nembra"
MAX_JSON_BYTES: Final = 512 * 1024
MAX_IPA_BYTES: Final = 512 * 1024 * 1024

_HEX40_64 = re.compile(r"^[0-9a-f]{40,64}$")
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_TEAM = re.compile(r"^[A-Z0-9]{10}$")


class SignedCandidateReinspectionError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise SignedCandidateReinspectionError(message)


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _read_regular(path: Path, label: str, *, max_bytes: int) -> bytes:
    candidate = path.expanduser()
    if not hasattr(os, "O_NOFOLLOW"):
        raise SignedCandidateReinspectionError(
            "descriptor-bound signed-candidate reinspection requires O_NOFOLLOW support"
        )
    flags = os.O_RDONLY | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    try:
        before_path = candidate.lstat()
    except OSError as error:
        raise SignedCandidateReinspectionError(f"{label} is unavailable: {candidate}") from error
    if stat.S_ISLNK(before_path.st_mode) or not stat.S_ISREG(before_path.st_mode):
        raise SignedCandidateReinspectionError(f"{label} must be one regular non-symlink file")
    if before_path.st_size <= 0 or before_path.st_size > max_bytes:
        raise SignedCandidateReinspectionError(f"{label} byte count is outside the accepted bound")

    try:
        descriptor = os.open(candidate, flags)
    except OSError as error:
        raise SignedCandidateReinspectionError(f"{label} could not be opened safely") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise SignedCandidateReinspectionError(f"{label} descriptor is not a regular file")
        if before.st_size <= 0 or before.st_size > max_bytes:
            raise SignedCandidateReinspectionError(f"{label} descriptor byte count is outside the accepted bound")
        chunks: list[bytes] = []
        remaining = before.st_size
        while remaining:
            chunk = os.read(descriptor, min(1024 * 1024, remaining))
            if not chunk:
                raise SignedCandidateReinspectionError(f"{label} changed during descriptor read")
            chunks.append(chunk)
            remaining -= len(chunk)
        if os.read(descriptor, 1):
            raise SignedCandidateReinspectionError(f"{label} grew during descriptor read")
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)

    identity_before = (
        before.st_dev,
        before.st_ino,
        before.st_mode,
        before.st_uid,
        before.st_gid,
        before.st_size,
        before.st_mtime_ns,
        before.st_ctime_ns,
    )
    identity_after = (
        after.st_dev,
        after.st_ino,
        after.st_mode,
        after.st_uid,
        after.st_gid,
        after.st_size,
        after.st_mtime_ns,
        after.st_ctime_ns,
    )
    if identity_before != identity_after:
        raise SignedCandidateReinspectionError(f"{label} identity changed during descriptor read")
    if (before_path.st_dev, before_path.st_ino) != (before.st_dev, before.st_ino):
        raise SignedCandidateReinspectionError(f"{label} pathname changed before descriptor admission")
    try:
        after_path = candidate.lstat()
    except OSError as error:
        raise SignedCandidateReinspectionError(f"{label} pathname changed after descriptor read") from error
    if stat.S_ISLNK(after_path.st_mode) or (after_path.st_dev, after_path.st_ino) != (after.st_dev, after.st_ino):
        raise SignedCandidateReinspectionError(f"{label} pathname identity changed during descriptor read")

    raw = b"".join(chunks)
    _require(len(raw) == before.st_size, f"{label} byte count changed during descriptor read")
    return raw


def _json_object(raw: bytes, label: str) -> dict[str, Any]:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise SignedCandidateReinspectionError(f"{label} contains duplicate JSON key: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(raw, object_pairs_hook=reject_duplicates)
    except SignedCandidateReinspectionError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SignedCandidateReinspectionError(f"{label} is not valid UTF-8 JSON") from error
    _require(isinstance(value, dict), f"{label} root must be one JSON object")
    return value


def _closed_env() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
    }


def _run_tool(arguments: list[str]) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            arguments,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_closed_env(),
            check=False,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SignedCandidateReinspectionError(
            f"Apple signing reinspection tool failed to execute: {arguments[0]}"
        ) from error


def _require_tool_success(
    runner: Callable[[list[str]], subprocess.CompletedProcess[bytes]],
    arguments: list[str],
    label: str,
) -> subprocess.CompletedProcess[bytes]:
    result = runner(arguments)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        suffix = f": {detail[:512]}" if detail else ""
        raise SignedCandidateReinspectionError(f"{label} failed{suffix}")
    return result


def _validate_ipa_members(raw: bytes) -> str:
    try:
        with zipfile.ZipFile(Path(os.devnull), "r"):
            pass
    except Exception:
        # The dummy branch only keeps static analyzers from treating ZipFile as path-only; the
        # actual archive is opened below from a seekable temporary file by `_extract_ipa`.
        pass
    # Cheap preflight for the caller-provided bytes before Apple `ditto` touches them.
    try:
        import io
        archive = zipfile.ZipFile(io.BytesIO(raw), "r")
    except zipfile.BadZipFile as error:
        raise SignedCandidateReinspectionError("retained IPA is not a readable ZIP") from error
    with archive:
        roots: set[str] = set()
        seen: set[str] = set()
        for info in archive.infolist():
            name = info.filename
            _require("\x00" not in name and "\\" not in name, "retained IPA contains unsafe member name")
            pure = PurePosixPath(name)
            _require(not pure.is_absolute() and ".." not in pure.parts, "retained IPA contains path traversal")
            normalized = pure.as_posix()
            folded = normalized.casefold()
            _require(folded not in seen, "retained IPA contains duplicate/case-colliding member")
            seen.add(folded)
            mode = (info.external_attr >> 16) & 0xFFFF
            _require(not stat.S_ISLNK(mode), "retained IPA contains symlink member")
            parts = pure.parts
            if len(parts) >= 2 and parts[0] == "Payload" and parts[1].endswith(".app"):
                roots.add(parts[1])
        _require(len(roots) == 1, "retained IPA must contain exactly one top-level Payload app")
        return next(iter(roots))


def _extract_ipa(
    ipa_path: Path,
    ipa_raw: bytes,
    destination: Path,
    runner: Callable[[list[str]], subprocess.CompletedProcess[bytes]],
) -> Path:
    app_name = _validate_ipa_members(ipa_raw)
    _require_tool_success(
        runner,
        ["/usr/bin/ditto", "-x", "-k", str(ipa_path), str(destination)],
        "retained IPA extraction",
    )
    app = destination / "Payload" / app_name
    try:
        metadata = app.lstat()
    except OSError as error:
        raise SignedCandidateReinspectionError("retained IPA extraction did not produce the expected app") from error
    _require(not app.is_symlink() and stat.S_ISDIR(metadata.st_mode), "extracted app is not one real directory")
    return app


def _parse_codesign_details(raw: bytes) -> tuple[list[str], str, str]:
    text = raw.decode("utf-8", errors="replace")
    authorities: list[str] = []
    team = ""
    cdhash = ""
    for line in text.splitlines():
        if line.startswith("Authority="):
            value = line.split("=", 1)[1].strip()
            if value:
                authorities.append(value)
        elif line.startswith("TeamIdentifier="):
            team = line.split("=", 1)[1].strip()
        elif line.startswith("CDHash="):
            cdhash = line.split("=", 1)[1].strip().lower()
    _require(authorities, "fresh codesign inspection lacks signing authorities")
    _require(_TEAM.fullmatch(team) is not None, "fresh codesign inspection lacks canonical TeamIdentifier")
    _require(_HEX40_64.fullmatch(cdhash) is not None, "fresh codesign inspection lacks canonical CDHash")
    return authorities, team, cdhash


def _normalized_utc(value: Any, label: str) -> str:
    _require(isinstance(value, datetime), f"{label} is not a provisioning-profile datetime")
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    value = value.astimezone(timezone.utc).replace(microsecond=0)
    return value.isoformat().replace("+00:00", "Z")


def verify_signed_candidate_reinspection(
    *,
    candidate_root: Path,
    runner: Callable[[list[str]], subprocess.CompletedProcess[bytes]] = _run_tool,
) -> dict[str, Any]:
    """Return independently recomputed signing facts or fail closed on any retained-record drift."""
    inspection_root = candidate_root.expanduser().absolute() / "inspection"
    inspection_path = inspection_root / INSPECTION_NAME
    ipa_path = inspection_root / IPA_RELATIVE_PATH
    inspection_raw = _read_regular(inspection_path, "signed artifact inspection", max_bytes=MAX_JSON_BYTES)
    inspection = _json_object(inspection_raw, "signed artifact inspection")
    ipa_raw = _read_regular(ipa_path, "retained signed IPA", max_bytes=MAX_IPA_BYTES)
    ipa_sha = _sha256(ipa_raw)

    _require(inspection.get("signedInstallableKind") == "ipa", "retained inspection installable kind is not ipa")
    _require(inspection.get("signedInstallableSHA256") == ipa_sha, "retained inspection IPA digest does not match exact IPA bytes")
    _require(inspection.get("ipaByteCount") == len(ipa_raw), "retained inspection IPA byte count does not match exact IPA bytes")

    with tempfile.TemporaryDirectory(prefix="nembra-final-go-reinspect-") as temporary:
        extracted = Path(temporary)
        app = _extract_ipa(ipa_path, ipa_raw, extracted, runner)
        _require_tool_success(
            runner,
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=4", str(app)],
            "fresh strict codesign verification",
        )
        details = _require_tool_success(
            runner,
            ["/usr/bin/codesign", "-d", "--verbose=4", str(app)],
            "fresh codesign metadata inspection",
        )
        authorities, codesign_team, cdhash = _parse_codesign_details(details.stderr + b"\n" + details.stdout)

        info_path = app / "Info.plist"
        info_raw = _read_regular(info_path, "extracted signed app Info.plist", max_bytes=8 * 1024 * 1024)
        try:
            info = plistlib.loads(info_raw)
        except Exception as error:
            raise SignedCandidateReinspectionError("extracted signed app Info.plist is not a valid plist") from error
        _require(isinstance(info, dict), "extracted signed app Info.plist root is not a dictionary")
        bundle_id = info.get("CFBundleIdentifier")
        executable_name = info.get("CFBundleExecutable")
        platform_name = info.get("DTPlatformName")
        supported = info.get("CFBundleSupportedPlatforms")
        _require(bundle_id == EXPECTED_BUNDLE_ID, "fresh signed app bundle identifier is not canonical Nembra")
        _require(isinstance(executable_name, str) and executable_name, "fresh signed app lacks CFBundleExecutable")
        _require(isinstance(platform_name, str) and platform_name, "fresh signed app lacks DTPlatformName")
        _require(isinstance(supported, list) and all(isinstance(item, str) for item in supported), "fresh signed app lacks supported-platform evidence")
        executable_path = app / executable_name
        executable_raw = _read_regular(executable_path, "extracted signed app executable", max_bytes=256 * 1024 * 1024)

        profile_path = app / "embedded.mobileprovision"
        profile_raw = _read_regular(profile_path, "embedded provisioning profile", max_bytes=16 * 1024 * 1024)
        decoded_profile = _require_tool_success(
            runner,
            ["/usr/bin/security", "cms", "-D", "-i", str(profile_path)],
            "fresh provisioning-profile CMS decode",
        )
        try:
            profile = plistlib.loads(decoded_profile.stdout)
        except Exception as error:
            raise SignedCandidateReinspectionError("fresh decoded provisioning profile is not a valid plist") from error
        _require(isinstance(profile, dict), "fresh decoded provisioning profile root is not a dictionary")
        teams = profile.get("TeamIdentifier")
        _require(isinstance(teams, list) and len(teams) == 1 and isinstance(teams[0], str), "fresh provisioning profile lacks one TeamIdentifier")
        profile_team = teams[0]
        _require(profile_team == codesign_team, "fresh codesign TeamIdentifier diverges from provisioning profile")
        entitlements = profile.get("Entitlements")
        _require(isinstance(entitlements, dict), "fresh provisioning profile lacks Entitlements")
        application_identifier = entitlements.get("application-identifier")
        _require(application_identifier == f"{profile_team}.{bundle_id}", "fresh provisioning application identifier is not exact team.bundle")
        profile_uuid = profile.get("UUID")
        _require(isinstance(profile_uuid, str) and profile_uuid.strip(), "fresh provisioning profile lacks UUID")
        profile_expiration = _normalized_utc(profile.get("ExpirationDate"), "fresh provisioning expiration")

        fresh = {
            "authority": REINSPECTION_AUTHORITY,
            "inspectionRecordSHA256": _sha256(inspection_raw),
            "signedInstallableSHA256": ipa_sha,
            "ipaByteCount": len(ipa_raw),
            "bundleIdentifier": bundle_id,
            "platformName": platform_name,
            "supportedPlatforms": supported,
            "teamIdentifier": profile_team,
            "signingAuthorities": authorities,
            "codeDirectoryHash": cdhash,
            "provisioningProfileSHA256": _sha256(profile_raw),
            "provisioningProfileUUID": profile_uuid.strip(),
            "provisioningProfileExpirationUTC": profile_expiration,
            "provisioningApplicationIdentifier": application_identifier,
            "executableSHA256": _sha256(executable_raw),
            "infoPlistSHA256": _sha256(info_raw),
        }

    compared = (
        "signedInstallableSHA256",
        "ipaByteCount",
        "bundleIdentifier",
        "platformName",
        "supportedPlatforms",
        "teamIdentifier",
        "signingAuthorities",
        "codeDirectoryHash",
        "provisioningProfileSHA256",
        "provisioningProfileUUID",
        "provisioningProfileExpirationUTC",
        "provisioningApplicationIdentifier",
        "executableSHA256",
        "infoPlistSHA256",
    )
    for key in compared:
        _require(
            inspection.get(key) == fresh[key],
            f"retained signing inspection diverges from fresh independent IPA reinspection: {key}",
        )
    return fresh
