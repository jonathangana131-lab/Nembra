#!/usr/bin/env python3
"""Red-team residual launchd service authority after Capture build-UID retirement.

Validation only. Production helper bytes are patched only in the ephemeral runner
workspace via the exact #3224 convergence materializer, then restored byte-exact.
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


ROOT = Path(__file__).resolve().parents[3]
CONVERGENCE = ROOT / "scripts/ci/tests/test_capture_build_uid_retirement_convergence.py"
HELPER = ROOT / "scripts/ci/capture_signed_app_build_origin_custody.py"
MARKER = "NEMBRA_BUILD_UID_SEEDED_SERVICE_JSON="


def _run(argv: Sequence[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(argv),
        stdin=kwargs.pop("stdin", subprocess.DEVNULL),
        stdout=kwargs.pop("stdout", subprocess.PIPE),
        stderr=kwargs.pop("stderr", subprocess.PIPE),
        text=kwargs.pop("text", True),
        check=False,
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
        cwd=ROOT,
    )
    if completed.returncode != 0:
        raise ValidationError(f"git failed {args!r}: {completed.stderr[-800:]!r}")
    return completed.stdout.strip()


def _launchctl_absent(result: subprocess.CompletedProcess[str]) -> bool:
    detail = ((result.stdout or "") + "\n" + (result.stderr or "")).lower()
    markers = (
        "could not find domain",
        "could not find service",
        "no such process",
        "no such file or directory",
        "service not found",
    )
    return result.returncode != 0 and any(marker in detail for marker in markers)


def _root_witness() -> int:
    if sys.platform != "darwin" or os.geteuid() != 0:
        raise ValidationError("seeded-service witness requires root on macOS")
    field_name = os.environ.get("SUDO_USER", "")
    if not field_name:
        raise ValidationError("sudo did not expose the invoking field user")
    field = pwd.getpwnam(field_name)
    field_groups = tuple(sorted(set(os.getgrouplist(field.pw_name, field.pw_gid))))
    if field.pw_uid <= 0 or field.pw_gid <= 0 or any(group <= 0 for group in field_groups):
        raise ValidationError("field credential vector is invalid")

    helper = _load(HELPER, "nembra_seeded_service_candidate")
    uid = int(helper._choose_ephemeral_id())
    name = f"nembrasvc{uid}"
    label = f"com.nembra.validation.build-retirement.{uid}.{os.getpid()}"
    root = Path(tempfile.mkdtemp(prefix="nembra-seeded-build-service.", dir="/private/tmp"))
    home = root / "home"
    home.mkdir(mode=0o700)
    plist = root / "service.plist"
    user_target = f"user/{uid}"
    service_target = f"user/{uid}/{label}"
    seed: subprocess.Popen[bytes] | None = None
    created = False
    try:
        helper._create_local_build_identity(name, uid, uid, home)
        created = True
        seed = subprocess.Popen(
            ["/bin/sleep", "120"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/empty", "LANG": "C", "LC_ALL": "C"},
            **helper._structured_credentials(uid, uid, ()),
        )
        time.sleep(0.20)
        live, _ = helper._process_state_for_uid(uid)
        if seed.pid not in live:
            raise ValidationError(f"dedicated UID seed process not observable: {live}")
        domain_before, _, _ = helper._launch_domain_state(uid)
        if not domain_before:
            raise ValidationError("dedicated UID launch domain absent before service bootstrap")

        plist.write_bytes(
            plistlib.dumps(
                {
                    "Label": label,
                    "ProgramArguments": ["/bin/sleep", "120"],
                    "RunAtLoad": False,
                    "KeepAlive": False,
                    "ProcessType": "Background",
                },
                fmt=plistlib.FMT_XML,
                sort_keys=True,
            )
        )
        os.chown(plist, 0, 0)
        os.chmod(plist, 0o444)
        bootstrap = _run(["/bin/launchctl", "bootstrap", user_target, str(plist)])
        if bootstrap.returncode != 0:
            raise ValidationError(
                f"seeded service bootstrap failed: rc={bootstrap.returncode} stderr={bootstrap.stderr[-800:]!r}"
            )
        before = _run(["/bin/launchctl", "print", service_target])
        if before.returncode != 0:
            raise ValidationError(
                f"seeded service not registered before retirement: rc={before.returncode} stderr={before.stderr[-800:]!r}"
            )

        helper._remove_local_build_identity(name, uid, require_absent=True)
        created = False
        try:
            seed.wait(timeout=2.0)
        except subprocess.TimeoutExpired as error:
            raise ValidationError("dedicated UID seed process did not reap") from error
        live_after, zombies_after = helper._process_state_for_uid(uid)
        if live_after or zombies_after:
            raise ValidationError(
                f"retired UID retained process authority: live={live_after} zombies={zombies_after}"
            )

        service_after = _run(["/bin/launchctl", "print", service_target])
        if not _launchctl_absent(service_after):
            raise ValidationError(
                f"seeded service registry survived retirement: rc={service_after.returncode} "
                f"stdout={service_after.stdout[-500:]!r} stderr={service_after.stderr[-500:]!r}"
            )
        kickstart = _run(["/bin/launchctl", "kickstart", service_target])
        if not _launchctl_absent(kickstart):
            raise ValidationError(
                f"retired service remains kickstartable/ambiguous: rc={kickstart.returncode} "
                f"stdout={kickstart.stdout[-500:]!r} stderr={kickstart.stderr[-500:]!r}"
            )

        domain_after, _, _ = helper._launch_domain_state(uid)
        if domain_after and not helper._numeric_principal_in_use(uid):
            raise ValidationError("lingering parent launch domain permits numeric UID reuse")

        asuser = subprocess.run(
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
            **helper._structured_credentials(field.pw_uid, field.pw_gid, field_groups),
        )
        if asuser.returncode == 0:
            raise ValidationError("ordinary field identity retained launchctl asuser authority")

        evidence = {
            "schema": 1,
            "serviceRegisteredBeforeRetirement": True,
            "zeroLiveUIDProcessesAfterRetirement": True,
            "seededServiceAbsentAfterRetirement": True,
            "seededServiceKickstartDeniedAfterRetirement": True,
            "domainLingeringAfterRetirement": domain_after,
            "numericReuseBlockedIfDomainLingering": (not domain_after) or helper._numeric_principal_in_use(uid),
            "ordinaryFieldAsuserDenied": True,
            "ordinaryFieldAsuserReturnCode": asuser.returncode,
            "xcodeUsed": False,
            "appleSigningIdentityUsed": False,
            "privateTuyaInputsUsed": False,
            "deviceUsed": False,
            "bluetoothUsed": False,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(evidence, sort_keys=True, separators=(",", ":")))
        return 0
    finally:
        if seed is not None and seed.poll() is None:
            seed.kill()
            try:
                seed.wait(timeout=1.0)
            except Exception:
                pass
        if created:
            helper._remove_local_build_identity(name, uid, require_absent=False)
        shutil.rmtree(root, ignore_errors=True)


def _default(production_parent: str, validation_parent: str, output: Path) -> int:
    if sys.platform != "darwin" or os.geteuid() == 0:
        raise ValidationError("seeded-service runner requires a non-root macOS field account")
    if _git("merge-base", "HEAD", validation_parent) != validation_parent:
        raise ValidationError("checkout is not descended from the exact #3224 validation parent")

    convergence = _load(CONVERGENCE, "nembra_seeded_service_materializer")
    original = convergence._materialize_candidate(production_parent)
    try:
        result = _run(
            ["/usr/bin/sudo", "/usr/bin/python3", "-B", "-I", str(Path(__file__).resolve()), "--root-witness"],
            cwd=ROOT,
        )
        combined = (result.stdout or "") + (result.stderr or "")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(combined, encoding="utf-8")
        if result.returncode != 0:
            raise ValidationError(
                f"seeded-service adversary failed: rc={result.returncode} tail={combined[-1800:]!r}"
            )
        records = [json.loads(line[len(MARKER) :]) for line in combined.splitlines() if line.startswith(MARKER)]
        if len(records) != 1:
            raise ValidationError(f"expected one seeded-service record, found {len(records)}")
        evidence = records[0]
        for key in (
            "serviceRegisteredBeforeRetirement",
            "zeroLiveUIDProcessesAfterRetirement",
            "seededServiceAbsentAfterRetirement",
            "seededServiceKickstartDeniedAfterRetirement",
            "numericReuseBlockedIfDomainLingering",
            "ordinaryFieldAsuserDenied",
        ):
            if evidence.get(key) is not True:
                raise ValidationError(f"seeded-service semantic gate failed: {key}: {evidence}")
        for key in (
            "xcodeUsed",
            "appleSigningIdentityUsed",
            "privateTuyaInputsUsed",
            "deviceUsed",
            "bluetoothUsed",
            "physicalAuthorityCreated",
        ):
            if evidence.get(key) is not False:
                raise ValidationError(f"seeded-service crossed forbidden authority boundary: {key}: {evidence}")
        print("BUILD_UID_SEEDED_SERVICE_RETIREMENT_ACCEPTED physicalAuthorityCreated=false")
        return 0
    finally:
        HELPER.write_bytes(original)
        expected_blob = _git("rev-parse", f"{production_parent}:scripts/ci/capture_signed_app_build_origin_custody.py")
        actual_blob = _git("hash-object", str(HELPER))
        if actual_blob != expected_blob:
            raise ValidationError(f"production helper restore mismatch: expected={expected_blob} actual={actual_blob}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--production-parent")
    parser.add_argument("--validation-parent")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--root-witness", action="store_true")
    args = parser.parse_args()
    if args.root_witness:
        return _root_witness()
    if not args.production_parent or not args.validation_parent or args.output is None:
        parser.error("default mode requires exact production/validation parents and --output")
    for value in (args.production_parent, args.validation_parent):
        if len(value) != 40 or any(ch not in "0123456789abcdef" for ch in value):
            raise ValidationError("parent identities must be lowercase 40-hex SHAs")
    return _default(args.production_parent, args.validation_parent, args.output)


if __name__ == "__main__":
    raise SystemExit(main())
