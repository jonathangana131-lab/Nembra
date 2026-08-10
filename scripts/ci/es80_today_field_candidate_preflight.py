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


def _stable_file_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int, int, int, int]:
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


def _regular_nonsymlink(path: Path) -> os.stat_result | None:
    try:
        info = path.lstat()
    except OSError:
        return None
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        return None
    return info


def _repository_directory_identity(repository_root: Path) -> tuple[int, int] | None:
    try:
        resolved_repository = repository_root.resolve(strict=True)
        metadata = os.stat(resolved_repository)
    except OSError:
        return None
    if not stat.S_ISDIR(metadata.st_mode):
        return None
    return metadata.st_dev, metadata.st_ino


def _private_udid_file_is_ready(path: Path, repository_root: Path) -> bool:
    """Mirror frozen a0f4's normal-path private identifier constraints.

    This is still only an early operator check. The frozen producer independently reopens the
    private input with its own descriptor-bound implementation. The preflight must nevertheless
    avoid a false READY for path shapes that the producer deterministically rejects, including a
    symlinked ancestor or a file that traverses the Nembra repository directory.
    """
    if (
        not hasattr(os, "O_NOFOLLOW")
        or not hasattr(os, "O_DIRECTORY")
        or os.open not in os.supports_dir_fd
    ):
        return False
    if not path.is_absolute() or path.anchor != os.sep:
        return False

    components = path.parts[1:]
    if not components or any(component in ("", ".", "..") for component in components):
        return False

    repository_identity = _repository_directory_identity(repository_root)
    if repository_identity is None:
        return False

    close_on_exec = os.O_CLOEXEC if hasattr(os, "O_CLOEXEC") else 0
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | close_on_exec
    file_flags = os.O_RDONLY | os.O_NOFOLLOW | close_on_exec

    try:
        parent_descriptor = os.open(os.sep, directory_flags)
    except OSError:
        return False

    descriptor: int | None = None
    try:
        root_metadata = os.fstat(parent_descriptor)
        if (root_metadata.st_dev, root_metadata.st_ino) == repository_identity:
            return False

        for component in components[:-1]:
            try:
                next_descriptor = os.open(component, directory_flags, dir_fd=parent_descriptor)
            except OSError:
                return False

            next_metadata = os.fstat(next_descriptor)
            if (next_metadata.st_dev, next_metadata.st_ino) == repository_identity:
                os.close(next_descriptor)
                return False
            os.close(parent_descriptor)
            parent_descriptor = next_descriptor

        try:
            descriptor = os.open(components[-1], file_flags, dir_fd=parent_descriptor)
        except OSError:
            return False
    finally:
        os.close(parent_descriptor)

    if descriptor is None:
        return False

    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            return False
        # TODAY's operator handoff intentionally requires exact mode 0600 even though the frozen
        # reader's lower-level privacy rule is expressed as no group/other access.
        if stat.S_IMODE(metadata.st_mode) != 0o600:
            return False
        if metadata.st_size < 1 or metadata.st_size > MAX_PRIVATE_IDENTIFIER_BYTES:
            return False
        if metadata.st_nlink != 1:
            return False
        if hasattr(os, "geteuid") and metadata.st_uid != os.geteuid():
            return False

        try:
            with os.fdopen(os.dup(descriptor), "rb") as handle:
                raw = handle.read(MAX_PRIVATE_IDENTIFIER_BYTES + 1)
            final_metadata = os.fstat(descriptor)
        except OSError:
            return False

        if (
            len(raw) != metadata.st_size
            or len(raw) > MAX_PRIVATE_IDENTIFIER_BYTES
            or _stable_file_identity(final_metadata) != _stable_file_identity(metadata)
        ):
            return False
    finally:
        os.close(descriptor)

    try:
        value = raw.decode("utf-8")
    except UnicodeDecodeError:
        return False
    # Frozen a0f4 rejects a trailing newline and every other leading/trailing whitespace byte.
    if not value or value != value.strip():
        return False
    if any(ord(character) < 33 or ord(character) == 127 for character in value):
        return False
    if value in os.fspath(path):
        return False
    return True


def _export_options_are_ready(path: Path, expected_team: str) -> bool:
    """Read one exact ExportOptions subject and mirror frozen producer admission.

    This remains a non-authorizing readiness check. Resolve the absolute path component-by-component
    with no-follow directory descriptors, open the final plist without following aliases, parse only
    a duplicate of that already-open descriptor, require the subject identity to remain stable, and
    then apply the frozen producer's deterministic dictionary/team/method checks. Signing and
    provisioning authority remains with Xcode and the retained-candidate evidence ladder.
    """
    if (
        not hasattr(os, "O_NOFOLLOW")
        or not hasattr(os, "O_DIRECTORY")
        or os.open not in os.supports_dir_fd
    ):
        return False
    if not path.is_absolute() or path.anchor != os.sep:
        return False

    components = path.parts[1:]
    if not components or any(component in ("", ".", "..") for component in components):
        return False

    close_on_exec = os.O_CLOEXEC if hasattr(os, "O_CLOEXEC") else 0
    nonblocking = os.O_NONBLOCK if hasattr(os, "O_NONBLOCK") else 0
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | close_on_exec
    # O_NONBLOCK is inert for regular files and prevents a special-file candidate from hanging
    # before fstat can reject it as non-regular.
    file_flags = os.O_RDONLY | os.O_NOFOLLOW | close_on_exec | nonblocking

    try:
        parent_descriptor = os.open(os.sep, directory_flags)
    except OSError:
        return False

    descriptor: int | None = None
    try:
        for component in components[:-1]:
            try:
                next_descriptor = os.open(component, directory_flags, dir_fd=parent_descriptor)
            except OSError:
                return False
            os.close(parent_descriptor)
            parent_descriptor = next_descriptor

        try:
            descriptor = os.open(components[-1], file_flags, dir_fd=parent_descriptor)
        except OSError:
            return False
    finally:
        os.close(parent_descriptor)

    if descriptor is None:
        return False

    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size < 1:
            return False
        try:
            with os.fdopen(os.dup(descriptor), "rb") as handle:
                payload = plistlib.load(handle)
            final_metadata = os.fstat(descriptor)
        except (OSError, plistlib.InvalidFileException, ValueError):
            return False
        if _stable_file_identity(final_metadata) != _stable_file_identity(metadata):
            return False
    finally:
        os.close(descriptor)

    if not isinstance(payload, dict):
        return False

    team = payload.get("teamID")
    if team is not None and team != expected_team:
        return False

    method = payload.get("method")
    if method is not None and (not isinstance(method, str) or not method.strip()):
        return False
    return True


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


def _checkout_file_matches_frozen_blob(
    runner: Runner,
    repo: Path,
    expected_source_sha: str,
    relative_path: str,
) -> bool:
    """Require raw checkout bytes to equal the exact frozen Git blob.

    `git status` remains a broad hygiene check, but repository-local clean filters can influence its
    worktree view. These two executable handoff scripts run from the outer checkout before the
    canonical producer creates its own fresh worktree, so their raw bytes need an independent
    exact-object check that bypasses clean/smudge filters.
    """
    expected = _git(
        runner,
        repo,
        "rev-parse",
        "--verify",
        f"{expected_source_sha}:{relative_path}",
    )
    expected_blob = expected.stdout.strip()
    if expected.returncode != 0 or SHA_RE.fullmatch(expected_blob) is None:
        return False

    actual = _git(
        runner,
        repo,
        "hash-object",
        "--no-filters",
        "--",
        relative_path,
    )
    return actual.returncode == 0 and actual.stdout.strip() == expected_blob


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
    checks["exportOptionsPlist"] = _export_options_are_ready(
        inputs.export_options_plist,
        inputs.development_team,
    )

    try:
        source_repo = inputs.source_repo.resolve(strict=True)
        repo_ready = source_repo.is_dir()
    except OSError:
        source_repo = inputs.source_repo
        repo_ready = False
    checks["sourceRepository"] = repo_ready
    checks["privateIntendedDeviceInput"] = (
        _private_udid_file_is_ready(inputs.intended_device_udid_file, source_repo)
        if repo_ready
        else False
    )

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
        checks["todayWrapperMatchesFrozenGitBlob"] = _checkout_file_matches_frozen_blob(
            runner, source_repo, expected, TODAY_WRAPPER
        )
        checks["canonicalProducerMatchesFrozenGitBlob"] = _checkout_file_matches_frozen_blob(
            runner, source_repo, expected, CANONICAL_PRODUCER
        )
    else:
        for key in (
            "exactFrozenSourceHEAD",
            "cleanInvocationCheckout",
            "todayWrapperAtFrozenSource",
            "canonicalProducerAtFrozenSource",
            "todayWrapperExecutableInCheckout",
            "canonicalProducerExecutableInCheckout",
            "todayWrapperMatchesFrozenGitBlob",
            "canonicalProducerMatchesFrozenGitBlob",
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
        "sourceRepository": "source-repository-unavailable",
        "privateIntendedDeviceInput": "private-intended-device-input-invalid",
        "exactFrozenSourceHEAD": "source-head-does-not-match-frozen-subject",
        "cleanInvocationCheckout": "invocation-checkout-not-clean",
        "todayWrapperAtFrozenSource": "today-wrapper-not-executable-in-frozen-git-tree",
        "canonicalProducerAtFrozenSource": "canonical-producer-not-executable-in-frozen-git-tree",
        "todayWrapperExecutableInCheckout": "today-wrapper-not-executable-in-checkout",
        "canonicalProducerExecutableInCheckout": "canonical-producer-not-executable-in-checkout",
        "todayWrapperMatchesFrozenGitBlob": "today-wrapper-checkout-bytes-do-not-match-frozen-git-blob",
        "canonicalProducerMatchesFrozenGitBlob": "canonical-producer-checkout-bytes-do-not-match-frozen-git-blob",
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