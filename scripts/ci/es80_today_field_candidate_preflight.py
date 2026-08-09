#!/usr/bin/env python3
"""Fail-closed operator preflight for the private ES80 TODAY signed-field handoff.

This tool intentionally cannot authorize Bluetooth activity or physical Experiment One. It checks
that the operator is about to invoke the frozen TODAY Research Field Build producer from the exact
expected source with coherent private signing inputs and an Xcode 27 selection. The canonical
producer and all later retained-candidate/install/runtime/Final-GO checks remain authoritative.

The report is deliberately secret-minimizing: it never emits the Apple TeamIdentifier, intended
UDID, private input paths, or export-options contents.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
from typing import Callable, Mapping, Sequence

AUTHORITY = "operator-pre-signing-readiness-not-field-authorization"
READY_STATUS = "READY_TO_INVOKE_SIGNED_FIELD_PRODUCER"
NOT_READY_STATUS = "NOT_READY"
PHYSICAL_AUTHORIZATION = "not-granted"
RESEARCH_COMPILE_MODE = "private-today-v1"
RESEARCH_COMPILE_AUTHORITY = "canonical-producer-explicit-mode"
RESEARCH_COMPILE_CONDITION = "NEMBRA_ES80_TODAY_RESEARCH"
RECIPE = "ES80-FINGERPRINT-v1"
PROCEDURE = "V14"
MAX_PRIVATE_IDENTIFIER_BYTES = 128

TODAY_WRAPPER = "scripts/ci/xcode27_today_research_field_candidate.sh"
CANONICAL_PRODUCER = "scripts/ci/xcode27_signed_field_candidate.sh"
TEAM_RE = re.compile(r"^[A-Z0-9]{10}$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
XCODE_27_RE = re.compile(r"^Xcode 27(?:\.|$)", re.MULTILINE)


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str


Runner = Callable[[Sequence[str], Path | None, Mapping[str, str]], CommandResult]


@dataclass(frozen=True)
class Inputs:
    source_repo: Path
    expected_source_sha: str
    development_team: str
    export_options_plist: Path
    intended_device_udid_file: Path
    allow_provisioning_updates: str


def _closed_env(extra: Mapping[str, str] | None = None) -> dict[str, str]:
    env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }
    if extra:
        env.update(extra)
    return env


def _default_runner(
    argv: Sequence[str], cwd: Path | None, env: Mapping[str, str]
) -> CommandResult:
    try:
        completed = subprocess.run(
            list(argv),
            cwd=str(cwd) if cwd is not None else None,
            env=dict(env),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    except OSError:
        # Never leak a caller path or private process diagnostic merely because one required system
        # command is unavailable. The named readiness check will fail closed instead.
        return CommandResult(127, "", "")
    return CommandResult(completed.returncode, completed.stdout, completed.stderr)


def _regular_nonsymlink(path: Path) -> os.stat_result | None:
    try:
        info = path.lstat()
    except OSError:
        return None
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        return None
    return info


def _private_udid_file_is_ready(path: Path) -> bool:
    """Mirror the normal-path privacy/format contract enforced by frozen a0f4's private runner.

    This remains only an early operator check. The frozen producer reopens and independently
    validates the file component-by-component before signed evidence admission.
    """
    if not path.is_absolute():
        return False
    info = _regular_nonsymlink(path)
    if info is None:
        return False
    if stat.S_IMODE(info.st_mode) != 0o600:
        return False
    if info.st_size < 1 or info.st_size > MAX_PRIVATE_IDENTIFIER_BYTES:
        return False
    if info.st_nlink != 1:
        return False
    if hasattr(os, "geteuid") and info.st_uid != os.geteuid():
        return False
    try:
        raw = path.read_bytes()
    except OSError:
        return False
    if len(raw) != info.st_size or len(raw) > MAX_PRIVATE_IDENTIFIER_BYTES:
        return False
    try:
        value = raw.decode("utf-8")
    except UnicodeDecodeError:
        return False
    # Frozen a0f4's exact private runner rejects a trailing newline and every other leading/trailing
    # whitespace byte. Do not normalize the value here: doing so would create a false READY state.
    if not value or value != value.strip():
        return False
    if any(ord(character) < 33 or ord(character) == 127 for character in value):
        return False
    if value in os.fspath(path):
        return False
    return True


def _export_options_are_ready(path: Path) -> bool:
    if _regular_nonsymlink(path) is None:
        return False
    try:
        with path.open("rb") as handle:
            payload = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException, ValueError):
        return False
    return isinstance(payload, dict)


def _git(
    runner: Runner,
    repo: Path,
    *args: str,
) -> CommandResult:
    return runner(("/usr/bin/git", *args), repo, _closed_env())


def _git_head_matches(runner: Runner, repo: Path, expected: str) -> bool:
    result = _git(runner, repo, "rev-parse", "--verify", "HEAD^{commit}")
    return result.returncode == 0 and result.stdout.strip() == expected


def _git_checkout_is_clean(runner: Runner, repo: Path) -> bool:
    result = _git(runner, repo, "status", "--porcelain=v1", "--untracked-files=all")
    return result.returncode == 0 and result.stdout == ""


def _git_subject_is_executable(
    runner: Runner,
    repo: Path,
    expected_source_sha: str,
    relative_path: str,
) -> bool:
    result = _git(runner, repo, "ls-tree", expected_source_sha, "--", relative_path)
    if result.returncode != 0:
        return False
    line = result.stdout.strip()
    if not line:
        return False
    fields = line.split(None, 3)
    return len(fields) == 4 and fields[0] == "100755" and fields[1] == "blob"


def _selected_xcode_27_is_ready(runner: Runner) -> bool:
    selected = runner(("/usr/bin/xcode-select", "-p"), None, _closed_env())
    if selected.returncode != 0:
        return False
    developer_dir = selected.stdout.strip()
    if not developer_dir.startswith("/") or "\n" in developer_dir:
        return False
    version = runner(
        ("/usr/bin/xcodebuild", "-version"),
        None,
        _closed_env({"DEVELOPER_DIR": developer_dir}),
    )
    return version.returncode == 0 and XCODE_27_RE.search(version.stdout) is not None


def evaluate_preflight(
    inputs: Inputs,
    *,
    runner: Runner = _default_runner,
    system_name: str | None = None,
) -> tuple[dict[str, object], int]:
    checks: dict[str, bool] = {}
    problems: list[str] = []

    expected = inputs.expected_source_sha
    checks["expectedSourceSHAFormat"] = SHA_RE.fullmatch(expected) is not None
    checks["developmentTeamFormat"] = TEAM_RE.fullmatch(inputs.development_team) is not None
    checks["allowProvisioningUpdates"] = inputs.allow_provisioning_updates in {"0", "1"}
    checks["exportOptionsPlist"] = _export_options_are_ready(inputs.export_options_plist)
    checks["privateIntendedDeviceInput"] = _private_udid_file_is_ready(
        inputs.intended_device_udid_file
    )

    try:
        source_repo = inputs.source_repo.resolve(strict=True)
        repo_ready = source_repo.is_dir()
    except OSError:
        source_repo = inputs.source_repo
        repo_ready = False
    checks["sourceRepository"] = repo_ready

    if repo_ready and checks["expectedSourceSHAFormat"]:
        checks["exactFrozenSourceHEAD"] = _git_head_matches(runner, source_repo, expected)
        checks["cleanInvocationCheckout"] = _git_checkout_is_clean(runner, source_repo)
        checks["todayWrapperAtFrozenSource"] = _git_subject_is_executable(
            runner, source_repo, expected, TODAY_WRAPPER
        )
        checks["canonicalProducerAtFrozenSource"] = _git_subject_is_executable(
            runner, source_repo, expected, CANONICAL_PRODUCER
        )
        wrapper_path = source_repo / TODAY_WRAPPER
        producer_path = source_repo / CANONICAL_PRODUCER
        checks["todayWrapperExecutableInCheckout"] = (
            _regular_nonsymlink(wrapper_path) is not None and os.access(wrapper_path, os.X_OK)
        )
        checks["canonicalProducerExecutableInCheckout"] = (
            _regular_nonsymlink(producer_path) is not None and os.access(producer_path, os.X_OK)
        )
    else:
        for key in (
            "exactFrozenSourceHEAD",
            "cleanInvocationCheckout",
            "todayWrapperAtFrozenSource",
            "canonicalProducerAtFrozenSource",
            "todayWrapperExecutableInCheckout",
            "canonicalProducerExecutableInCheckout",
        ):
            checks[key] = False

    actual_system = system_name if system_name is not None else os.uname().sysname
    checks["macOSSigningSurface"] = actual_system == "Darwin"
    checks["selectedXcode27"] = (
        _selected_xcode_27_is_ready(runner) if checks["macOSSigningSurface"] else False
    )

    labels = {
        "expectedSourceSHAFormat": "expected-source-sha-invalid",
        "developmentTeamFormat": "development-team-input-invalid",
        "allowProvisioningUpdates": "provisioning-update-mode-invalid",
        "exportOptionsPlist": "export-options-input-invalid",
        "privateIntendedDeviceInput": "private-intended-device-input-invalid",
        "sourceRepository": "source-repository-unavailable",
        "exactFrozenSourceHEAD": "source-head-does-not-match-frozen-subject",
        "cleanInvocationCheckout": "invocation-checkout-not-clean",
        "todayWrapperAtFrozenSource": "today-wrapper-not-executable-in-frozen-git-tree",
        "canonicalProducerAtFrozenSource": "canonical-producer-not-executable-in-frozen-git-tree",
        "todayWrapperExecutableInCheckout": "today-wrapper-not-executable-in-checkout",
        "canonicalProducerExecutableInCheckout": "canonical-producer-not-executable-in-checkout",
        "macOSSigningSurface": "private-signing-surface-is-not-macos",
        "selectedXcode27": "selected-xcode-is-not-xcode-27",
    }
    for name, passed in checks.items():
        if not passed:
            problems.append(labels[name])

    ready = not problems
    report: dict[str, object] = {
        "schemaVersion": 1,
        "authority": AUTHORITY,
        "status": READY_STATUS if ready else NOT_READY_STATUS,
        "physicalExperimentAuthorization": PHYSICAL_AUTHORIZATION,
        "sourceCommitSHA": expected if checks["expectedSourceSHAFormat"] else "invalid",
        "experimentRecipeID": RECIPE,
        "procedureVersion": PROCEDURE,
        "researchCompileMode": RESEARCH_COMPILE_MODE,
        "researchCompileAuthority": RESEARCH_COMPILE_AUTHORITY,
        "researchCompileCondition": RESEARCH_COMPILE_CONDITION,
        "checks": checks,
        "problems": problems,
        "nextAction": (
            "Invoke scripts/ci/xcode27_today_research_field_candidate.sh from this exact frozen checkout; retain and independently inspect its immutable candidate. This preflight is not Final GO."
            if ready
            else "Correct only the listed pre-signing blocker(s), then rerun this preflight. Do not invoke the physical experiment."
        ),
    }
    return report, 0 if ready else 2


def _path_from(value: str | None, env_name: str) -> Path:
    selected = value or os.environ.get(env_name)
    if not selected:
        raise ValueError(f"missing-{env_name.lower().replace('_', '-')}")
    return Path(selected)


def _string_from(value: str | None, env_name: str) -> str:
    selected = value or os.environ.get(env_name)
    if not selected:
        raise ValueError(f"missing-{env_name.lower().replace('_', '-')}")
    return selected


def _args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Check private TODAY signed-field producer invocation readiness. "
            "This tool never grants physical experiment authorization."
        )
    )
    parser.add_argument("--source-repo", type=Path, default=Path.cwd())
    parser.add_argument("--expected-source-sha", required=True)
    parser.add_argument("--development-team")
    parser.add_argument("--export-options-plist")
    parser.add_argument("--intended-device-udid-file")
    parser.add_argument("--allow-provisioning-updates")
    return parser.parse_args(list(argv))


def main(argv: Sequence[str] | None = None) -> int:
    args = _args(sys.argv[1:] if argv is None else argv)
    try:
        inputs = Inputs(
            source_repo=args.source_repo,
            expected_source_sha=args.expected_source_sha,
            development_team=_string_from(args.development_team, "NEMBRA_DEVELOPMENT_TEAM"),
            export_options_plist=_path_from(
                args.export_options_plist, "NEMBRA_EXPORT_OPTIONS_PLIST"
            ),
            intended_device_udid_file=_path_from(
                args.intended_device_udid_file, "NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"
            ),
            allow_provisioning_updates=(
                args.allow_provisioning_updates
                or os.environ.get("NEMBRA_ALLOW_PROVISIONING_UPDATES", "0")
            ),
        )
        report, exit_code = evaluate_preflight(inputs)
    except ValueError as error:
        report = {
            "schemaVersion": 1,
            "authority": AUTHORITY,
            "status": NOT_READY_STATUS,
            "physicalExperimentAuthorization": PHYSICAL_AUTHORIZATION,
            "problems": [str(error)],
            "nextAction": "Provide the missing private producer input locally. Do not invoke the physical experiment.",
        }
        exit_code = 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
