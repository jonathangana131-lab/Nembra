#!/usr/bin/env python3
"""Validation successor for the dedicated-UID real-Xcode APFS freeze oracle.

The underlying dedicated-UID oracle intentionally compares the fresh build GID
against the field account's complete directory-service group membership. On the
hosted Xcode runner that account advertises more directory groups than Python's
setgroups-backed Popen path can replay, so the field negative control can fail
with ``ValueError: too many groups`` before APFS quiescence is tested.

This wrapper preserves the full directory-membership check, but executes the
negative control with the *actual effective supplementary groups of the runner
process that invoked sudo*. Those are the authority-bearing groups the field
process really had at admission time and are kernel-representable by definition.
The wrapper is validation-only and creates no product or physical authority.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import pwd
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
BASE_ORACLE_PATH = HERE / "test_capture_signed_app_real_xcode_dedicated_uid_freeze.py"
WRAPPER_MARKER = "NEMBRA_REAL_XCODE_DEDICATED_UID_EFFECTIVE_GROUPS_JSON="


class WrapperError(RuntimeError):
    pass


def load_base_oracle():
    spec = importlib.util.spec_from_file_location("nembra_real_xcode_dedicated_uid_base", BASE_ORACLE_PATH)
    if spec is None or spec.loader is None:
        raise WrapperError("could not load dedicated-UID real-Xcode base oracle")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def canonical_group_vector(groups: list[int]) -> list[int]:
    normalized = sorted(set(groups))
    if any(group < 0 for group in normalized):
        raise WrapperError("effective group vector contains a negative gid")
    return normalized


def parse_group_vector(raw: str) -> list[int]:
    if raw == "":
        return []
    pieces = raw.split(",")
    if any(piece == "" or not piece.isdigit() for piece in pieces):
        raise WrapperError("effective group vector is not canonical decimal CSV")
    parsed = [int(piece, 10) for piece in pieces]
    if parsed != canonical_group_vector(parsed):
        raise WrapperError("effective group vector is not strictly sorted and unique")
    return parsed


def root_probe(package_root: Path, field_effective_groups_raw: str) -> int:
    base = load_base_oracle()
    if sys.platform != "darwin" or os.geteuid() != 0:
        base.emit_error("environment", "effective-group root wrapper requires sudo on real macOS")
        return 90

    try:
        field_uid = int(os.environ["SUDO_UID"])
        field_gid = int(os.environ["SUDO_GID"])
        field_user = os.environ["SUDO_USER"]
        field_effective_groups = parse_group_vector(field_effective_groups_raw)
    except (KeyError, ValueError, WrapperError) as error:
        base.emit_error("identity", f"could not recover exact field effective groups: {error}")
        return 91

    if field_uid <= 0 or field_gid <= 0:
        base.emit_error("identity", "field identity must remain non-root")
        return 91
    account = pwd.getpwuid(field_uid)
    if account.pw_name != field_user or account.pw_gid != field_gid:
        base.emit_error("identity", "sudo identity does not match the field account")
        return 91

    directory_groups = sorted(set(os.getgrouplist(account.pw_name, field_gid)))
    effective_authority = sorted(set([field_gid, *field_effective_groups]))
    if 0 in directory_groups or 0 in effective_authority:
        base.emit_error("identity", "field identity carries root-group authority")
        return 91
    if not set(effective_authority).issubset(set(directory_groups)):
        base.emit_error(
            "identity",
            "caller effective groups are not a subset of current directory-service membership",
        )
        return 91

    # The base oracle deliberately uses complete directory membership for its
    # build-GID non-overlap proof. Intercept only the one field-user Popen call
    # and replay the invoking process's real effective supplementary groups.
    # Build-UID and former-build-UID credential transitions remain untouched.
    original_structured_credentials = base.structured_credentials
    field_extra_groups = [group for group in field_effective_groups if group != field_gid]

    def structured_credentials(uid: int, gid: int, groups):
        requested = sorted(set(groups))
        if uid == field_uid and gid == field_gid and requested == directory_groups:
            return original_structured_credentials(field_uid, field_gid, field_extra_groups)
        return original_structured_credentials(uid, gid, requested)

    base.structured_credentials = structured_credentials
    try:
        return base.root_probe(package_root)
    finally:
        base.structured_credentials = original_structured_credentials


def parent_probe() -> int:
    base = load_base_oracle()
    if sys.platform != "darwin":
        base.emit_error("environment", "effective-group dedicated-UID probe requires macOS")
        return 90
    sudo = subprocess.run(
        ["/usr/bin/sudo", "-n", "/usr/bin/true"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if sudo.returncode != 0:
        base.emit_error("environment", "runner does not expose noninteractive sudo for validation")
        return 90

    field_uid = os.getuid()
    field_gid = os.getgid()
    field_effective_groups = canonical_group_vector(list(os.getgroups()))
    effective_authority = sorted(set([field_gid, *field_effective_groups]))
    if field_uid <= 0 or field_gid <= 0 or 0 in effective_authority:
        base.emit_error("identity", "field runner must be non-root and carry no root-group authority")
        return 91
    encoded_groups = ",".join(str(group) for group in field_effective_groups)

    with tempfile.TemporaryDirectory(prefix="nembra-real-xcode-dedicated-uid-effective-groups-") as temporary:
        package = Path(temporary)
        base.make_package(package)
        completed = subprocess.run(
            [
                "/usr/bin/sudo",
                "-n",
                "/usr/bin/python3",
                "-B",
                "-I",
                str(Path(__file__).resolve()),
                "--root-probe",
                "--package-root",
                str(package),
                "--field-effective-groups",
                encoded_groups,
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        sys.stdout.write(completed.stdout)
        sys.stderr.write(completed.stderr)
        if completed.returncode != 0:
            return completed.returncode

        records = [
            line[len(base.MARKER):]
            for line in completed.stdout.splitlines()
            if line.startswith(base.MARKER)
        ]
        if len(records) != 1:
            base.emit_error("evidence", "missing or ambiguous dedicated-UID Xcode freeze evidence")
            return 92
        evidence = json.loads(records[0])
        required = (
            evidence.get("xcodebuildReturnCode") == 0
            and evidence.get("fieldAttackReturnCode") != 0
            and evidence.get("fieldGroupsContainBuildGID") is False
            and evidence.get("buildIdentityDistinctFromField") is True
            and evidence.get("nonForcedDetachReturnCode") == 0
            and evidence.get("rootReadonlyAttackReturnCode") != 0
            and evidence.get("formerBuildReadonlyAttackReturnCode") != 0
            and evidence.get("compilerProductSHA256") == evidence.get("readonlyRemountSHA256")
            and evidence.get("physicalAuthorityCreated") is False
        )
        if not required:
            base.emit_error("evidence", f"effective-group dedicated-UID evidence failed semantic checks: {evidence}")
            return 93

        wrapper_evidence = {
            "schemaVersion": 1,
            "fieldUID": field_uid,
            "fieldPrimaryGID": field_gid,
            "fieldEffectiveSupplementaryGroups": field_effective_groups,
            "fieldEffectiveGroupCount": len(field_effective_groups),
            "compilerProductSHA256": evidence.get("compilerProductSHA256"),
            "readonlyRemountSHA256": evidence.get("readonlyRemountSHA256"),
            "nonForcedDetachReturnCode": evidence.get("nonForcedDetachReturnCode"),
            "physicalAuthorityCreated": False,
        }
        print(WRAPPER_MARKER + json.dumps(wrapper_evidence, sort_keys=True))
        return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-probe", action="store_true")
    parser.add_argument("--package-root", type=Path)
    parser.add_argument("--field-effective-groups", default="")
    args = parser.parse_args()
    if args.root_probe:
        if args.package_root is None:
            base = load_base_oracle()
            base.emit_error("arguments", "--package-root is required for root probe")
            return 94
        return root_probe(args.package_root, args.field_effective_groups)
    if args.package_root is not None or args.field_effective_groups != "":
        base = load_base_oracle()
        base.emit_error("arguments", "root-only arguments are not accepted by the field parent")
        return 94
    return parent_probe()


if __name__ == "__main__":
    raise SystemExit(main())
