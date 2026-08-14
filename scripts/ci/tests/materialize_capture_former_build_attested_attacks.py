#!/usr/bin/env python3
"""Validation-only materializer/parser for former-build attack credential proof."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


TEST_PATH = Path("scripts/ci/tests/test_capture_signed_app_real_xcode_group_custody.py")
MARKER = "NEMBRA_REAL_XCODE_ORIGIN_JSON="


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one {label}, found {count}")
    return source.replace(old, new)


def replace_attack_call(source: str, variable: str, target_fragment: str, label: str) -> str:
    """Replace one subprocess attack while preserving its exact payload source line.

    The canonical witness intentionally embeds shell strings whose escaping may change
    without changing the authority question. Match the assignment boundary, preserve
    the exact command line already present in the canonical witness, and replace only
    the credential-launch mechanism.
    """
    marker = f"        {variable} = subprocess.run(\n"
    if source.count(marker) != 1:
        raise SystemExit(f"expected exactly one {label} assignment, found {source.count(marker)}")
    start = source.index(marker)
    end_marker = "        )\n"
    end = source.find(end_marker, start + len(marker))
    if end < 0:
        raise SystemExit(f"could not find {label} call boundary")
    end += len(end_marker)
    block = source[start:end]
    lines = block.splitlines(keepends=True)
    if len(lines) < 3 or target_fragment not in lines[1]:
        raise SystemExit(f"{label} payload line changed unexpectedly")
    command_line = lines[1]
    replacement = (
        f"        {variable} = helper._run_exec_bound_build(\n"
        + command_line
        + "            name=build_name,\n"
        + "            uid=build_uid,\n"
        + "            gid=build_gid,\n"
        + "            baseline_groups=build_directory_groups,\n"
        + "            environment=build_environment,\n"
        + "            cwd=source_root,\n"
        + "        )\n"
    )
    return source[:start] + replacement + source[end:]


def materialize() -> None:
    source = TEST_PATH.read_text(encoding="utf-8")

    source = replace_attack_call(
        source,
        "former_build_writable_attack",
        "str(product)",
        "writable former-build attack",
    )
    source = replace_attack_call(
        source,
        "former_build_attack",
        "str(frozen)",
        "readonly former-build attack",
    )

    writable_evidence = '            "formerBuildWritablePathAttackReturnCode": former_build_writable_attack.returncode,\n'
    source = replace_once(
        source,
        writable_evidence,
        writable_evidence + '            "formerBuildWritableAttackCredentialAttested": True,\n',
        "writable evidence anchor",
    )
    readonly_evidence = '            "formerBuildReadonlyAttackReturnCode": former_build_attack.returncode,\n'
    source = replace_once(
        source,
        readonly_evidence,
        readonly_evidence + '            "formerBuildReadonlyAttackCredentialAttested": True,\n',
        "readonly evidence anchor",
    )

    writable_required = '            and evidence.get("formerBuildWritablePathAttackReturnCode") != 0\n'
    source = replace_once(
        source,
        writable_required,
        writable_required + '            and evidence.get("formerBuildWritableAttackCredentialAttested") is True\n',
        "writable success predicate",
    )
    readonly_required = '            and evidence.get("formerBuildReadonlyAttackReturnCode") != 0\n'
    source = replace_once(
        source,
        readonly_required,
        readonly_required + '            and evidence.get("formerBuildReadonlyAttackCredentialAttested") is True\n',
        "readonly success predicate",
    )

    if source.count("former_build_writable_attack = helper._run_exec_bound_build(") != 1:
        raise SystemExit("writable attacker is not uniquely exec-bound")
    if source.count("former_build_attack = helper._run_exec_bound_build(") != 1:
        raise SystemExit("readonly attacker is not uniquely exec-bound")
    if "**structured_credentials(build_uid, build_gid, [])" in source:
        raise SystemExit("unattested requested-credential attacker survived")
    compile(source, str(TEST_PATH), "exec", dont_inherit=True)
    TEST_PATH.write_text(source, encoding="utf-8")


def verify_log(path: Path) -> None:
    lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line.startswith(MARKER)]
    if len(lines) != 1:
        raise SystemExit(f"expected one real-Xcode evidence line, got {len(lines)}")
    payload = json.loads(lines[0][len(MARKER):])
    required_true = (
        "buildEffectiveGroupAuthorityAttested",
        "execBoundCredentialAttestationUsed",
        "formerBuildWritableAttackCredentialAttested",
        "formerBuildReadonlyAttackCredentialAttested",
        "buildPrincipalRetired",
    )
    for key in required_true:
        if payload.get(key) is not True:
            raise SystemExit(f"missing true invariant: {key}={payload.get(key)!r}")
    for key in ("formerBuildWritablePathAttackReturnCode", "formerBuildReadonlyAttackReturnCode"):
        if not isinstance(payload.get(key), int) or payload[key] == 0:
            raise SystemExit(f"mutation attack was not denied: {key}={payload.get(key)!r}")
    if payload.get("nonForcedDetachReturnCode") != 0 or payload.get("readonlyNonForcedDetachReturnCode") != 0:
        raise SystemExit("normal APFS detach did not remain successful")
    if payload.get("compilerProductSHA256") != payload.get("readonlyRemountSHA256"):
        raise SystemExit("compiler/remount byte identity drifted")
    if payload.get("physicalAuthorityCreated") is not False:
        raise SystemExit("validation crossed physical authority boundary")
    print("NEMBRA_FORMER_BUILD_ATTESTED_ATTACK_VALIDATION_ACCEPTED physicalAuthorityCreated=false")


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("materialize")
    verify = sub.add_parser("verify-log")
    verify.add_argument("path", type=Path)
    args = parser.parse_args()
    if args.command == "materialize":
        materialize()
    else:
        verify_log(args.path)


if __name__ == "__main__":
    main()
