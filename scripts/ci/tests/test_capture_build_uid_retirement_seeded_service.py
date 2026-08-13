#!/usr/bin/env python3
"""Validation-only launchd service-registry adversary for build-UID retirement.

This witness consumes the exact #3224 retirement candidate materializer without
changing production bytes in Git. It seeds one harmless, non-RunAtLoad service in
the fresh build UID's launchd user domain before retirement, then requires the
specific service to be absent and non-kickstartable after retirement even if the
parent user/<uid> namespace remains observable as tearing-down metadata.

No Xcode build, signing, provisioning, device, Bluetooth, Tuya, or scooter action.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import pwd
import shutil
import subprocess
import sys
import tempfile
import time
from types import ModuleType
from typing import Sequence


class ValidationError(RuntimeError):
    pass


REPO_ROOT = Path(__file__).resolve().parents[3]
CONVERGENCE_TEST = REPO_ROOT / "scripts/ci/tests/test_capture_build_uid_retirement_convergence.py"
HELPER = REPO_ROOT / "scripts/ci/capture_signed_app_build_origin_custody.py"


def _run(argv: Sequence[str], *, check: bool = False, **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(argv),
        stdin=kwargs.pop("stdin", subprocess.DEVNULL),
        stdout=kwargs.pop("stdout", subprocess.PIPE),
        stderr=kwargs.pop("stderr", subprocess.PIPE),
        text=kwargs.pop("text", True),
        check=check,
        **kwargs,
    )


def _load(path: Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValidationError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _git(*args: str) -> str:
    completed = _run(
        [
            "/usr/bin/env",
            "GIT_NO_REPLACE_OBJECTS=1",
            "GIT_CONFIG_NOSYSTEM=1",
            "GIT_CONFIG_GLOBAL=/dev/null",
            "/usr/bin/git",
            "-c",
            "core.hooksPath=/dev/null",
            *args,
        ],
        cwd=REPO_ROOT,
    )
    if completed.returncode != 0:
        raise ValidationError(f"git command failed: {args!r}: {completed.stderr[-800:]!r}")
    return completed.stdout.strip()


def _launchctl_absent(completed: subprocess.CompletedProcess[str]) -> bool:
    detail = ((completed.stdout or "") + "\n" + (completed.stderr or "")).strip()
    markers = (
        "Could not find domain",
        "Could not find service",
        "No such process",
        "No such file or directory",
        "service not found",
    )
    return completed.returncode != 0 and any(marker.lower() in detail.lower() for marker in markers)


def _root_seeded_service() -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise ValidationError("seeded-service adversary requires root on real macOS")
    field_name = os.environ.get("SUDO_USER", "")
    if not field_name:
        raise ValidationError("sudo did not identify the invoking field account")
    field = pwd.getpwnam(field_name)
    field_groups = tuple(sorted(set(os.getgrouplist(field.pw_name, field.pw_gid))))
    if field.pw_uid <= 0 or field.pw_gid <= 0 or any(value <= 0 for value in field_groups):
        raise ValidationError("field authority vector is invalid")

    candidate = _load(HELPER, "nembra_seeded_service_candidate")
    uid = int(candidate._choose_ephemeral_id())
    name = f"nembrasvc{uid}"
    label = f"com.nembra.validation.retired-build.{uid}.{os.getpid()}"
    root = Path(tempfile.mkdtemp(prefix="nembra-build-uid-seeded-service.", dir="/private/tmp"))
    home = root / "home"
    home.mkdir(mode=0o700)
    plist = root / "seeded-service.plist"
    service_target = f"user/{uid}/{label}"
    user_target = f"user/{uid}"
    bootstrap_child: subprocess.Popen[bytes] | None = None
    created = False
    try:
        candidate._create_local_build_identity(name, uid, uid, home)
        created = True

        # Force creation of the per-user launch domain using an ordinary process
        # under the dedicated UID before the harmless service is registered.
        bootstrap_child = subprocess.Popen(
            ["/bin/sleep", "120"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty", "LANG": "C", "LC_ALL": "C"},
            **candidate._structured_credentials(uid, uid, ()),
        )
        time.sleep(0.20)
        live, _ = candidate._process_state_for_uid(uid)
        if bootstrap_child.pid not in live:
            raise ValidationError(f"dedicated UID launch-domain seed process was not observable: {live}")

        domain_before, _, _ = candidate._launch_domain_state(uid)
        if not domain_before:
            raise ValidationError("dedicated UID user launch domain was not observable before service bootstrap")

        plist_payload = {
            "Label": label,
            "ProgramArguments": ["/bin/sleep", "120"],
            "RunAtLoad": False,
            "KeepAlive": False,
            "ProcessType": "Background",
        }
        plist.write_bytes(plistlib.dumps(plist_payload, fmt=plistlib.FMT_XML, sort_keys=True))
        os.chown(plist, 0, 0)
        os.chmod(plist, 0o444)

        bootstrap = _run(["/bin/launchctl", "bootstrap", user_target, str(plist)])
        if bootstrap.returncode != 0:
            raise ValidationError(
                "could not bootstrap harmless seeded service into dedicated UID domain: "
                f"rc={bootstrap.returncode} stderr={bootstrap.stderr[-1000:]!r}"
            )
        printed_before = _run(["/bin/launchctl", "print", service_target])
        if printed_before.returncode != 0:
            raise ValidationError(
                "seeded service was not mechanically registered before retirement: "
                f"rc={printed_before.returncode} stderr={printed_before.stderr[-1000:]!r}"
            )

        candidate._remove_local_build_identity(name, uid, require_absent=True)
        created = False
        try:
            bootstrap_child.wait(timeout=2.0)
        except subprocess.TimeoutExpired as error:
            raise ValidationError("dedicated UID seed process did not reap after retirement") from error
        live_after, zombies_after = candidate._process_state_for_uid(uid)
        if live_after or zombies_after:
            raise ValidationError(
                f"retired UID retained process authority: live={live_after} zombies={zombies_after}"
            )

        service_after = _run(["/bin/launchctl", "print", service_target])
        if not _launchctl_absent(service_after):
            raise ValidationError(
                "seeded service registry survived whole-domain retirement: "
                f"rc={service_after.returncode} stdout={service_after.stdout[-600:]!r} "
                f"stderr={service_after.stderr[-600:]!r}"
            )
        kickstart = _run(["/bin/launchctl", "kickstart", service_target])
        if not _launchctl_absent(kickstart):
            raise ValidationError(
                "retired seeded service remained kickstartable or failed ambiguously: "
                f"rc={kickstart.returncode} stdout={kickstart.stdout[-600:]!r} "
                f"stderr={kickstart.stderr[-600:]!r}"
            )

        domain_after, _, _ = candidate._launch_domain_state(uid)
        if domain_after and not candidate._numeric_principal_in_use(uid):
            raise ValidationError("lingering parent launch domain did not block numeric UID reuse")

        field_asuser = subprocess.run(
            ["/bin/launchctl", "asuser", str(uid), "/usr/bin/true"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            env={
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": field.pw_dir,
                "USER": field.pw_name,
                "LOGNAME": field.pw_name,
                "LANG": "C",
                "LC_ALL": "C",
            },
            **candidate._structured_credentials(field.pw_uid, field.pw_gid, field_groups),
        )
        if field_asuser.returncode == 0:
            raise ValidationError("ordinary field identity retained launchctl asuser authority for retired UID")

        evidence = {
            "schema": 1,
            "retiredUID": uid,
            "serviceLabel": label,
            "domainPresentBeforeRetirement": True,
            "serviceRegisteredBeforeRetirement": True,
            "zeroLiveUIDProcessesAfterRetirement": True,
            "seededServiceAbsentAfterRetirement": True,
            "seededServiceKickstartDeniedAfterRetirement": True,
            "domainLingeringAfterRetirement": domain_after,
            "numericReuseBlockedIfDomainLingering": (not domain_after) or candidate._numeric_principal_in_use(uid),
            "ordinaryFieldAsuserDenied": True,
            "ordinaryFieldAsuserReturnCode": field_asuser.returncode,
            "xcodeUsed": False,
            "appleSigningIdentityUsed": False,
            "privateTuyaInputsUsed": False,
            "deviceUsed": False,
            "bluetoothUsed": False,
            "physicalAuthorityCreated": False,
        }
        print("NEMBRA_BUILD_UID_SEEDED_SERVICE_JSON=" + json.dumps(evidence, sort_keys=True, separators=(",", ":")))
        return 0
    finally:
        if bootstrap_child is not None and bootstrap_child.poll() is None:
            bootstrap_child.kill()
            try:
                bootstrap_child.wait(timeout=1.0)
            except Exception:
                pass
        if created:
            candidate._remove_local_build_identity(name, uid, require_absent=False)
        shutil.rmtree(root, ignore_errors=True)


def _default(expected_production_parent: str, expected_validation_parent: str, output: Path) -> int:
    if sys.platform != "darwin" or os.geteuid() == 0:
        raise ValidationError("seeded-service runner requires one non-root macOS field account")
    if _git("rev-parse", "HEAD") != expected_validation_parent:
        raise ValidationError("checkout is not the exact accepted validation parent")
    convergence = _load(CONVERGENCE_TEST, "nembra_retirement_convergence_materializer")
    original = convergence._materialize_candidate(expected_production_parent)
    try:
        completed = _run(
            ["/usr/bin/sudo", "/usr/bin/python3", "-B", "-I", str(Path(__file__).resolve()), "--root-seeded-service"],
            cwd=REPO_ROOT,
        )
        combined = (completed.stdout or "") + (completed.stderr or "")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(combined, encoding="utf-8")
        if completed.returncode != 0:
            raise ValidationError(
                f"seeded launchd service retirement adversary failed: rc={completed.returncode} tail={combined[-1800:]!r}"
            )
        marker = "NEMBRA_BUILD_UID_SEEDED_SERVICE_JSON="
        records = [json.loads(line[len(marker) :]) for line in combined.splitlines() if line.startswith(marker)]
        if len(records) != 1:
            raise ValidationError(f"expected one seeded-service evidence record, found {len(records)}")
        evidence = records[0]
        required_true = (
            "serviceRegisteredBeforeRetirement",
            "zeroLiveUIDProcessesAfterRetirement",
            "seededServiceAbsentAfterRetirement",
            "seededServiceKickstartDeniedAfterRetirement",
            "numericReuseBlockedIfDomainLingering",
            "ordinaryFieldAsuserDenied",
        )
        if evidence.get("schema") != 1 or any(evidence.get(key) is not True for key in required_true):
            raise ValidationError(f"seeded-service evidence failed semantic gates: {evidence}")
        if any(
            evidence.get(key) is not False
            for key in (
                "xcodeUsed",
                "appleSigningIdentityUsed",
                "privateTuyaInputsUsed",
                "deviceUsed",
                "bluetoothUsed",
                "physicalAuthorityCreated",
            )
        ):
            raise ValidationError(f"seeded-service witness crossed forbidden authority boundary: {evidence}")
        print("BUILD_UID_SEEDED_SERVICE_RETIREMENT_ACCEPTED physicalAuthorityCreated=false")
        return 0
    finally:
        HELPER.write_bytes(original)
        expected_blob = _git("rev-parse", f"{expected_production_parent}:scripts/ci/capture_signed_app_build_origin_custody.py")
        restored_blob = _git("hash-object", str(HELPER))
        if restored_blob != expected_blob:
            raise ValidationError(
                f"production helper restoration failed: expected={expected_blob} actual={restored_blob}"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-production-parent")
    parser.add_argument("--expected-validation-parent")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--root-seeded-service", action="store_true")
    args = parser.parse_args()
    if args.root_seeded_service:
        return _root_seeded_service()
    if not args.expected_production_parent or not args.expected_validation_parent or args.output is None:
        parser.error("default mode requires exact production/validation parents and --output")
    for value in (args.expected_production_parent, args.expected_validation_parent):
        if len(value) != 40 or any(ch not in "0123456789abcdef" for ch in value):
            raise ValidationError("exact parent identities must be lowercase 40-hex SHAs")
    return _default(args.expected_production_parent, args.expected_validation_parent, args.output)


if __name__ == "__main__":
    raise SystemExit(main())
