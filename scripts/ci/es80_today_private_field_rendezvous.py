#!/usr/bin/env python3
"""Private live field rendezvous for V14 ES80 Final GO.

This module is deliberately not a general device-management utility. It binds one already-accepted
signed Nembra field candidate to:
- a private intended-device identifier that never enters the public Final GO record;
- that identifier's membership in the exact retained IPA provisioning profile;
- a live CoreDevice view of the intended iPhone 12 / iOS 27 device;
- the exact Nembra bundle being installed on that device;
- one fresh human-observation record validated by the closed-world foundation; and
- one durable, fail-closed consumption marker so the same observation cannot be replayed normally.

Human observations remain human observations. This module does not turn Stationary, Charger
Disconnected, ResearchAdmission, or coordinator permission into machine telemetry. It only makes
the Final GO path mechanically require live private device/install evidence in addition to those
observations.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import stat
import subprocess
import sys
import tempfile
from typing import Any, Callable
import unicodedata
import zipfile

AUTHORITY = "private-live-field-rendezvous-v1"
BUNDLE_ID = "com.jonathangana131.nembra"
BASELINE_PRODUCT_TYPE = "iPhone13,2"
BASELINE_MARKETING_NAME = "iPhone 12"
BASELINE_OS_MAJOR = "27"
IPA_RELATIVE_PATH = Path("inspection") / "build-evidence" / "NembraField.ipa"
PRIVATE_DEVICE_LABEL = b"nembra-v14-private-device-commitment\0"
HEX64 = re.compile(r"^[0-9a-f]{64}$")
UDID = re.compile(r"^[A-Za-z0-9-]{8,80}$")


class PrivateFieldRendezvousError(RuntimeError):
    pass


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _duplicate_rejector(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise PrivateFieldRendezvousError(f"duplicate object key {key!r}")
        value[key] = item
    return value


def _json_bytes(raw: bytes, label: str) -> dict[str, Any]:
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=_duplicate_rejector)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PrivateFieldRendezvousError(f"{label} is not valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise PrivateFieldRendezvousError(f"{label} must be a JSON object")
    return value


def _regular_private_file(path: Path, label: str, *, max_bytes: int | None = None) -> bytes:
    expanded = path.expanduser()
    try:
        metadata = expanded.lstat()
    except FileNotFoundError as error:
        raise PrivateFieldRendezvousError(f"{label} is missing") from error
    if expanded.is_symlink() or not stat.S_ISREG(metadata.st_mode):
        raise PrivateFieldRendezvousError(f"{label} must be a regular non-symlink file")
    if metadata.st_uid != os.getuid():
        raise PrivateFieldRendezvousError(f"{label} must be owned by the current user")
    if metadata.st_mode & 0o077:
        raise PrivateFieldRendezvousError(f"{label} must not be readable or writable by group/other")
    if max_bytes is not None and metadata.st_size > max_bytes:
        raise PrivateFieldRendezvousError(f"{label} is unexpectedly large")
    return expanded.read_bytes()


def _read_private_udid(path: Path) -> str:
    raw = _regular_private_file(path, "private intended-device identifier", max_bytes=256)
    try:
        value = raw.decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise PrivateFieldRendezvousError("private intended-device identifier is not UTF-8") from error
    if not UDID.fullmatch(value):
        raise PrivateFieldRendezvousError("private intended-device identifier has invalid shape")
    return value


def _device_commitment(udid: str) -> str:
    return _sha(PRIVATE_DEVICE_LABEL + udid.encode("utf-8"))


def _candidate_text(candidate: dict[str, Any], key: str) -> str:
    value = candidate.get(key)
    if not isinstance(value, str) or not value:
        raise PrivateFieldRendezvousError(f"accepted candidate lacks {key}")
    return value


def _candidate_hash(candidate: dict[str, Any], key: str) -> str:
    value = _candidate_text(candidate, key).lower()
    if not HEX64.fullmatch(value):
        raise PrivateFieldRendezvousError(f"accepted candidate {key} has invalid SHA-256 shape")
    return value


def _stable_ipa_and_profile(
    candidate_root: Path,
    candidate: dict[str, Any],
) -> tuple[Path, bytes]:
    expected_ipa_sha = _candidate_hash(candidate, "retainedIPASHA256")
    expected_profile_sha = _candidate_hash(candidate, "provisioningProfileSHA256")
    expected_size = candidate.get("retainedIPAByteCount")
    if not isinstance(expected_size, int) or isinstance(expected_size, bool) or expected_size <= 0:
        raise PrivateFieldRendezvousError("accepted candidate retainedIPAByteCount is invalid")

    ipa = candidate_root.expanduser().resolve(strict=True) / IPA_RELATIVE_PATH
    try:
        resolved_ipa = ipa.resolve(strict=True)
        metadata = ipa.lstat()
    except FileNotFoundError as error:
        raise PrivateFieldRendezvousError("exact retained IPA is missing") from error
    if resolved_ipa != ipa or ipa.is_symlink() or not stat.S_ISREG(metadata.st_mode):
        raise PrivateFieldRendezvousError(
            "exact retained IPA path must contain no symlink substitution"
        )
    if metadata.st_size != expected_size:
        raise PrivateFieldRendezvousError("exact retained IPA byte count changed before rendezvous")

    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(ipa, flags)
    try:
        before = os.fstat(fd)
        digest = hashlib.sha256()
        chunks: list[bytes] = []
        while True:
            chunk = os.read(fd, 1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            chunks.append(chunk)
        after = os.fstat(fd)
    finally:
        os.close(fd)
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
        after.st_dev,
        after.st_ino,
        after.st_size,
        after.st_mtime_ns,
    ):
        raise PrivateFieldRendezvousError("exact retained IPA changed while being read")
    if digest.hexdigest() != expected_ipa_sha:
        raise PrivateFieldRendezvousError("exact retained IPA SHA-256 changed before rendezvous")

    raw_ipa = b"".join(chunks)
    try:
        with zipfile.ZipFile(io.BytesIO(raw_ipa), "r") as archive:
            collision_keys: set[str] = set()
            root_profiles: list[zipfile.ZipInfo] = []
            for info in archive.infolist():
                canonical = unicodedata.normalize("NFC", info.filename).casefold()
                if canonical in collision_keys:
                    raise PrivateFieldRendezvousError(
                        "retained IPA contains duplicate/colliding ZIP member names"
                    )
                collision_keys.add(canonical)
                parts = Path(info.filename).parts
                if (
                    len(parts) == 3
                    and parts[0] == "Payload"
                    and parts[1].endswith(".app")
                    and parts[2] == "embedded.mobileprovision"
                ):
                    root_profiles.append(info)
            if len(root_profiles) != 1:
                raise PrivateFieldRendezvousError(
                    "retained IPA must contain exactly one root app provisioning profile"
                )
            profile = archive.read(root_profiles[0])
    except (zipfile.BadZipFile, RuntimeError, KeyError) as error:
        if isinstance(error, PrivateFieldRendezvousError):
            raise
        raise PrivateFieldRendezvousError("retained IPA ZIP structure is invalid") from error

    if _sha(profile) != expected_profile_sha:
        raise PrivateFieldRendezvousError(
            "retained IPA provisioning profile SHA-256 diverges from accepted candidate"
        )
    if len(raw_ipa) != expected_size:
        raise PrivateFieldRendezvousError("exact retained IPA read length changed before rendezvous")
    return ipa, profile


def _trusted_system_executable(path: Path, label: str) -> Path:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise PrivateFieldRendezvousError(f"{label} is missing at {path}") from error
    if path.is_symlink() or not stat.S_ISREG(metadata.st_mode):
        raise PrivateFieldRendezvousError(f"{label} must be a regular non-symlink executable")
    if metadata.st_uid != 0:
        raise PrivateFieldRendezvousError(f"{label} must be root-owned")
    if metadata.st_mode & 0o022:
        raise PrivateFieldRendezvousError(f"{label} must not be group/world writable")
    if not os.access(path, os.X_OK):
        raise PrivateFieldRendezvousError(f"{label} is not executable")
    return path


def _closed_env() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": "/var/empty",
        "LANG": "C",
        "LC_ALL": "C",
    }


def _run(
    argv: list[str],
    *,
    timeout: int = 30,
) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            argv,
            check=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd="/",
            env=_closed_env(),
            timeout=timeout,
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        stderr = b""
        if isinstance(error, subprocess.CalledProcessError):
            stderr = error.stderr or b""
        detail = stderr.decode("utf-8", errors="replace").strip()
        suffix = f": {detail[:400]}" if detail else ""
        raise PrivateFieldRendezvousError(
            f"trusted command failed: {' '.join(argv[:3])}{suffix}"
        ) from error


def _decode_mobileprovision(profile: bytes) -> dict[str, Any]:
    if sys.platform != "darwin":
        raise PrivateFieldRendezvousError("private provisioning rendezvous requires macOS")
    security = _trusted_system_executable(Path("/usr/bin/security"), "Apple security tool")
    fd, name = tempfile.mkstemp(prefix="nembra-final-go-profile.", suffix=".mobileprovision")
    profile_path = Path(name)
    try:
        os.fchmod(fd, 0o600)
        os.write(fd, profile)
        os.fsync(fd)
        os.close(fd)
        fd = -1
        decoded = _run(
            [str(security), "cms", "-D", "-i", str(profile_path)], timeout=20
        ).stdout
        try:
            value = plistlib.loads(decoded)
        except Exception as error:
            raise PrivateFieldRendezvousError(
                "decoded provisioning profile is not a plist"
            ) from error
        if not isinstance(value, dict):
            raise PrivateFieldRendezvousError(
                "decoded provisioning profile is not a dictionary"
            )
        return value
    finally:
        if fd >= 0:
            os.close(fd)
        try:
            profile_path.unlink(missing_ok=True)
        except OSError:
            pass


def _verify_profile_membership(
    *,
    candidate_root: Path,
    candidate: dict[str, Any],
    intended_device_udid: str,
    now_utc: datetime,
) -> dict[str, Any]:
    _, profile_raw = _stable_ipa_and_profile(candidate_root, candidate)
    profile = _decode_mobileprovision(profile_raw)

    expected_uuid = _candidate_text(candidate, "provisioningProfileUUID")
    if profile.get("UUID") != expected_uuid:
        raise PrivateFieldRendezvousError(
            "live provisioning profile UUID diverges from accepted candidate"
        )

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise PrivateFieldRendezvousError(
            "live provisioning profile lacks ExpirationDate"
        )
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=timezone.utc)
    if expiration.astimezone(timezone.utc) <= now_utc.astimezone(timezone.utc):
        raise PrivateFieldRendezvousError("live provisioning profile is expired")

    team = _candidate_text(candidate, "teamIdentifier")
    teams = profile.get("TeamIdentifier")
    if not isinstance(teams, list) or team not in teams:
        raise PrivateFieldRendezvousError(
            "live provisioning profile team diverges from accepted candidate"
        )

    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        raise PrivateFieldRendezvousError("live provisioning profile lacks Entitlements")
    if entitlements.get("application-identifier") != f"{team}.{BUNDLE_ID}":
        raise PrivateFieldRendezvousError(
            "live provisioning application identifier mismatch"
        )

    all_devices = profile.get("ProvisionsAllDevices") is True
    if all_devices:
        membership_mode = "provisions-all-devices"
    else:
        devices = profile.get("ProvisionedDevices")
        if not isinstance(devices, list) or intended_device_udid not in devices:
            raise PrivateFieldRendezvousError(
                "private intended device is not admitted by the exact retained IPA provisioning profile"
            )
        membership_mode = "explicit-provisioned-device"

    return {
        "provisioningProfileSHA256": _sha(profile_raw),
        "provisioningProfileUUID": expected_uuid,
        "provisioningMembershipMode": membership_mode,
        "intendedDeviceMembershipVerified": True,
    }


def _trusted_xcode_tool(name: str) -> Path:
    if sys.platform != "darwin":
        raise PrivateFieldRendezvousError("private device rendezvous requires macOS")
    xcrun = _trusted_system_executable(Path("/usr/bin/xcrun"), "Apple xcrun")
    resolved_raw = _run([str(xcrun), "--find", name], timeout=10).stdout
    try:
        resolved = Path(resolved_raw.decode("utf-8").strip())
    except UnicodeDecodeError as error:
        raise PrivateFieldRendezvousError(
            f"xcrun returned invalid path for {name}"
        ) from error
    if not resolved.is_absolute():
        raise PrivateFieldRendezvousError(f"xcrun returned non-absolute path for {name}")
    real = resolved.resolve(strict=True)
    try:
        real.relative_to("/Applications")
    except ValueError as error:
        raise PrivateFieldRendezvousError(
            f"trusted Xcode tool {name} must resolve under /Applications"
        ) from error

    _trusted_system_executable(real, f"Xcode {name}")
    current = real.parent
    applications = Path("/Applications")
    while current != applications:
        metadata = current.lstat()
        if current.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
            raise PrivateFieldRendezvousError(
                f"Xcode tool parent is not a real directory: {current}"
            )
        if metadata.st_uid != 0 or metadata.st_mode & 0o022:
            raise PrivateFieldRendezvousError(
                f"Xcode tool parent custody is not root-closed: {current}"
            )
        current = current.parent
    return real


def _devicectl_json(devicectl: Path, args: list[str]) -> dict[str, Any]:
    fd, name = tempfile.mkstemp(prefix="nembra-devicectl.", suffix=".json")
    output = Path(name)
    try:
        os.close(fd)
        fd = -1
        _run([str(devicectl), *args, "--json-output", str(output)], timeout=30)
        try:
            raw = output.read_bytes()
        except OSError as error:
            raise PrivateFieldRendezvousError(
                "devicectl did not produce JSON output"
            ) from error
        return _json_bytes(raw, "devicectl output")
    finally:
        if fd >= 0:
            os.close(fd)
        try:
            output.unlink(missing_ok=True)
        except OSError:
            pass


def _verify_live_device_install(
    intended_device_udid: str,
) -> dict[str, Any]:
    devicectl = _trusted_xcode_tool("devicectl")
    xcodebuild = _trusted_xcode_tool("xcodebuild")
    version_lines = _run([str(xcodebuild), "-version"], timeout=10).stdout.decode(
        "utf-8", errors="strict"
    ).splitlines()
    if len(version_lines) < 2 or not version_lines[0].startswith("Xcode 27"):
        raise PrivateFieldRendezvousError(
            "live field rendezvous requires the accepted Xcode 27 toolchain"
        )
    xcode_version = version_lines[0].strip()
    xcode_build_version = version_lines[1].strip()

    devices_doc = _devicectl_json(
        devicectl,
        ["list", "devices", "--timeout", "10"],
    )
    info = devices_doc.get("info")
    if not isinstance(info, dict) or info.get("outcome") != "success":
        raise PrivateFieldRendezvousError(
            "devicectl device-list outcome is not success"
        )
    result = devices_doc.get("result")
    if not isinstance(result, dict) or not isinstance(result.get("devices"), list):
        raise PrivateFieldRendezvousError(
            "devicectl device-list JSON shape is unsupported"
        )

    matches: list[dict[str, Any]] = []
    for value in result["devices"]:
        if not isinstance(value, dict):
            continue
        hardware = value.get("hardwareProperties")
        if isinstance(hardware, dict) and hardware.get("udid") == intended_device_udid:
            matches.append(value)
    if len(matches) != 1:
        raise PrivateFieldRendezvousError(
            "private intended device is not uniquely live in CoreDevice"
        )

    device = matches[0]
    hardware = device.get("hardwareProperties")
    properties = device.get("deviceProperties")
    connection = device.get("connectionProperties")
    if (
        not isinstance(hardware, dict)
        or not isinstance(properties, dict)
        or not isinstance(connection, dict)
    ):
        raise PrivateFieldRendezvousError(
            "live intended-device CoreDevice record is incomplete"
        )
    if hardware.get("productType") != BASELINE_PRODUCT_TYPE:
        raise PrivateFieldRendezvousError(
            "live intended device is not the V14 iPhone 12 baseline"
        )
    os_version = properties.get("osVersionNumber")
    if (
        not isinstance(os_version, str)
        or os_version.split(".", 1)[0] != BASELINE_OS_MAJOR
    ):
        raise PrivateFieldRendezvousError(
            "live intended device is not on the V14 iOS 27 baseline"
        )
    if properties.get("developerModeStatus") != "enabled":
        raise PrivateFieldRendezvousError(
            "live intended device Developer Mode is not enabled"
        )
    if connection.get("pairingState") != "paired":
        raise PrivateFieldRendezvousError("live intended device is not paired")

    apps_doc = _devicectl_json(
        devicectl,
        [
            "device",
            "info",
            "apps",
            "--device",
            intended_device_udid,
            "--bundle-id",
            BUNDLE_ID,
        ],
    )
    apps_info = apps_doc.get("info")
    if not isinstance(apps_info, dict) or apps_info.get("outcome") != "success":
        raise PrivateFieldRendezvousError(
            "devicectl installed-app outcome is not success"
        )
    apps_result = apps_doc.get("result")
    apps = apps_result.get("apps") if isinstance(apps_result, dict) else None
    if not isinstance(apps, list):
        raise PrivateFieldRendezvousError(
            "devicectl installed-app JSON shape is unsupported"
        )
    exact = [
        value
        for value in apps
        if isinstance(value, dict) and value.get("bundleIdentifier") == BUNDLE_ID
    ]
    if len(exact) != 1:
        raise PrivateFieldRendezvousError(
            "Nembra bundle is not uniquely installed on intended device"
        )
    app = exact[0]
    if app.get("builtByDeveloper") is not True:
        raise PrivateFieldRendezvousError(
            "installed Nembra bundle is not reported as developer-built"
        )
    app_url = app.get("url")
    if not isinstance(app_url, str) or ".app" not in app_url:
        raise PrivateFieldRendezvousError(
            "installed Nembra bundle lacks a concrete app URL"
        )

    return {
        "connectedDeviceProbeVerified": True,
        "liveDeviceProductType": BASELINE_PRODUCT_TYPE,
        "liveDeviceMarketingName": str(
            hardware.get("marketingName") or BASELINE_MARKETING_NAME
        ),
        "liveDeviceOSVersion": os_version,
        "liveDeviceDeveloperMode": "enabled",
        "liveDevicePairingState": "paired",
        "liveDeviceTunnelState": str(connection.get("tunnelState") or "unknown"),
        "liveDeviceTransport": str(connection.get("transportType") or "unknown"),
        "installedBundleIdentifier": BUNDLE_ID,
        "installedAppBuiltByDeveloper": True,
        "installedAppURLSHA256": _sha(app_url.encode("utf-8")),
        "installedAppBundleVersion": str(app.get("bundleVersion") or ""),
        "installedAppVersion": str(app.get("version") or ""),
        "xcodeVersion": xcode_version,
        "xcodeBuildVersion": xcode_build_version,
        "devicectlSHA256": _sha(devicectl.read_bytes()),
    }


def _default_state_dir() -> Path:
    try:
        home = Path(pwd.getpwuid(os.getuid()).pw_dir)
    except (KeyError, OSError) as error:
        raise PrivateFieldRendezvousError(
            "could not resolve durable current-user home directory"
        ) from error
    return (
        home
        / "Library"
        / "Application Support"
        / "Nembra"
        / "FinalGOAuthority"
        / "V14"
    )


def _secure_state_dir(path: Path) -> Path:
    target = path.expanduser()
    target.mkdir(parents=True, mode=0o700, exist_ok=True)
    metadata = target.lstat()
    if target.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
        raise PrivateFieldRendezvousError(
            "private rendezvous state path is not a real directory"
        )
    target = target.resolve(strict=True)
    if metadata.st_uid != os.getuid():
        raise PrivateFieldRendezvousError(
            "private rendezvous state path has wrong owner"
        )
    if metadata.st_mode & 0o077:
        raise PrivateFieldRendezvousError(
            "private rendezvous state path must have mode 0700 or stricter"
        )
    return target


def _consume_once(
    *,
    state_dir: Path,
    attestation_id: str,
    attestation_sha256: str,
    candidate_ipa_sha256: str,
    device_commitment_sha256: str,
    now_utc: datetime,
) -> str:
    root = _secure_state_dir(state_dir)
    marker_key = _sha(
        (
            "nembra-v14-final-go-consumption\0"
            + attestation_id
            + "\0"
            + candidate_ipa_sha256
            + "\0"
            + device_commitment_sha256
        ).encode("utf-8")
    )
    marker = root / f"{marker_key}.json"
    payload = {
        "schemaVersion": 1,
        "authority": "private-final-go-rendezvous-consumption-v1",
        "attestationID": attestation_id,
        "attestationSHA256": attestation_sha256,
        "acceptedRetainedIPASHA256": candidate_ipa_sha256,
        "deviceCommitmentSHA256": device_commitment_sha256,
        "consumedAtUTC": now_utc.astimezone(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
    }
    raw = (
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode("utf-8")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(marker, flags, 0o600)
    except FileExistsError as error:
        raise PrivateFieldRendezvousError(
            "operator observation was already consumed; create a fresh observation record"
        ) from error
    try:
        offset = 0
        while offset < len(raw):
            written = os.write(fd, raw[offset:])
            if written <= 0:
                raise OSError("short write")
            offset += written
        os.fsync(fd)
    finally:
        os.close(fd)
    directory_fd = os.open(root, os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
    return _sha(raw)


def verify_private_field_rendezvous(
    *,
    candidate_root: Path,
    candidate: dict[str, Any],
    operator_attestation: Path,
    intended_device_udid_file: Path,
    operator_validator: Callable[[Path, dict[str, Any], datetime], dict[str, Any]],
    now_utc: datetime | None = None,
    profile_probe: Callable[..., dict[str, Any]] = _verify_profile_membership,
    device_probe: Callable[[str], dict[str, Any]] = _verify_live_device_install,
    state_dir: Path | None = None,
) -> dict[str, Any]:
    now = (now_utc or datetime.now(timezone.utc)).astimezone(timezone.utc)
    intended_udid = _read_private_udid(intended_device_udid_file)
    commitment = _device_commitment(intended_udid)

    observations = operator_validator(operator_attestation, candidate, now)
    if not isinstance(observations, dict):
        raise PrivateFieldRendezvousError(
            "operator observation validator returned invalid subject"
        )
    attestation_id = observations.get("attestationID")
    attestation_sha = observations.get("recordSHA256")
    if not isinstance(attestation_id, str) or not attestation_id:
        raise PrivateFieldRendezvousError("operator observation lacks attestation ID")
    if not isinstance(attestation_sha, str) or not HEX64.fullmatch(attestation_sha):
        raise PrivateFieldRendezvousError(
            "operator observation lacks exact record SHA-256"
        )

    profile = profile_probe(
        candidate_root=candidate_root,
        candidate=candidate,
        intended_device_udid=intended_udid,
        now_utc=now,
    )
    device = device_probe(intended_udid)
    if profile.get("intendedDeviceMembershipVerified") is not True:
        raise PrivateFieldRendezvousError(
            "private provisioning membership was not verified"
        )
    if device.get("connectedDeviceProbeVerified") is not True:
        raise PrivateFieldRendezvousError(
            "live intended-device probe was not verified"
        )
    if device.get("installedBundleIdentifier") != BUNDLE_ID:
        raise PrivateFieldRendezvousError(
            "live intended-device probe did not verify Nembra install"
        )

    candidate_ipa_sha = _candidate_hash(candidate, "retainedIPASHA256")
    marker_sha = _consume_once(
        state_dir=state_dir or _default_state_dir(),
        attestation_id=attestation_id,
        attestation_sha256=attestation_sha,
        candidate_ipa_sha256=candidate_ipa_sha,
        device_commitment_sha256=commitment,
        now_utc=now,
    )

    return {
        "authority": AUTHORITY,
        "classification": (
            "human-observed-preflight-bound-to-live-private-device-and-exact-retained-installable"
        ),
        "operatorObservationAuthority": observations.get("authority"),
        "operatorObservationRecordSHA256": attestation_sha,
        "attestationID": attestation_id,
        "recordedAtUTC": observations.get("recordedAtUTC"),
        "acceptedRetainedIPASHA256": candidate_ipa_sha,
        "deviceCommitmentSHA256": commitment,
        "intendedDeviceMembershipVerified": True,
        "connectedDeviceProbeVerified": True,
        "installedBundleIdentifier": BUNDLE_ID,
        "installedAppBuiltByDeveloper": device.get("installedAppBuiltByDeveloper"),
        "installedAppURLSHA256": device.get("installedAppURLSHA256"),
        "installedAppBundleVersion": device.get("installedAppBundleVersion"),
        "installedAppVersion": device.get("installedAppVersion"),
        "liveDeviceProductType": device.get("liveDeviceProductType"),
        "liveDeviceMarketingName": device.get("liveDeviceMarketingName"),
        "liveDeviceOSVersion": device.get("liveDeviceOSVersion"),
        "liveDeviceDeveloperMode": device.get("liveDeviceDeveloperMode"),
        "liveDevicePairingState": device.get("liveDevicePairingState"),
        "liveDeviceTunnelState": device.get("liveDeviceTunnelState"),
        "liveDeviceTransport": device.get("liveDeviceTransport"),
        "provisioningProfileSHA256": profile.get("provisioningProfileSHA256"),
        "provisioningProfileUUID": profile.get("provisioningProfileUUID"),
        "provisioningMembershipMode": profile.get("provisioningMembershipMode"),
        "runtimeRendezvousMatched": observations.get("runtimeRendezvousMatched") is True,
        "packageResearchAdmissionObserved": (
            observations.get("packageResearchAdmissionObserved") is True
        ),
        "ordinaryGeneralBuildAuthority": "NO-GO",
        "preflightHealth": observations.get("preflightHealth"),
        "chargerState": observations.get("chargerState"),
        "motionState": observations.get("motionState"),
        "noApplicationWriteAuthorityReview": (
            "REVIEWED_NO_APPLICATION_WRITE_OR_COMMAND_PATH"
        ),
        "oneTimeObservationConsumption": "CONSUMED",
        "oneTimeConsumptionMarkerSHA256": marker_sha,
        "xcodeVersion": device.get("xcodeVersion"),
        "xcodeBuildVersion": device.get("xcodeBuildVersion"),
        "devicectlSHA256": device.get("devicectlSHA256"),
        "rawIntendedDeviceIdentifierPublished": False,
        "physicalResultCollected": False,
    }
