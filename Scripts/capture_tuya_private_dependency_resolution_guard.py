#!/usr/bin/env python3
"""Run pre-generated Tuya dependency work under private-input vnode custody.

This is intentionally *not* the physical field-build CLI. The canonical build
guard's CLI protects the later xcodebuild window. Dependency resolution runs one
rung earlier, before generated CocoaPods subjects can exist.

The canonical guard currently exposes a narrow `run_guarded_build` primitive for
the five admitted private-input subjects. This adapter supplies those subjects,
adds symlink-free checkout ancestry admission for this earlier call site, and
fails closed if the canonical callable surface drifts. It grants no xcodebuild,
generated-build, private-review, source-acceptance, or physical GO authority.
The child command must independently establish semantic authority (bootstrap uses
the root-sealed private-identity receipt) after vnode watchers are armed.
"""

from __future__ import annotations

import argparse
import importlib.util
import inspect
import os
from pathlib import Path
import stat
import sys
from typing import Sequence


class ResolutionGuardError(RuntimeError):
    pass


_EXPECTED_RUN_GUARDED_BUILD_PARAMETERS = (
    "inputs",
    "command",
    "backend_factory",
    "popen_factory",
    "poll_interval",
)
_CANONICAL_GUARD_MODULE_NAME = "nembra_private_dependency_resolution_build_guard"


def _load_guard():
    guard_path = Path(__file__).with_name("capture_tuya_private_input_build_guard.py")
    if not guard_path.is_file() or guard_path.is_symlink():
        raise ResolutionGuardError("canonical private-input build guard is missing or symlinked")
    spec = importlib.util.spec_from_file_location(_CANONICAL_GUARD_MODULE_NAME, guard_path)
    if spec is None or spec.loader is None:
        raise ResolutionGuardError("canonical private-input build guard could not be loaded")
    module = importlib.util.module_from_spec(spec)
    # The canonical guard defines dataclasses. Python's dataclass machinery
    # resolves postponed annotations through sys.modules while the class body is
    # executed, so the module must be registered before exec_module.
    sys.modules[_CANONICAL_GUARD_MODULE_NAME] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        if sys.modules.get(_CANONICAL_GUARD_MODULE_NAME) is module:
            sys.modules.pop(_CANONICAL_GUARD_MODULE_NAME, None)
        raise
    return module


def _require_private_only_guard_api(guard) -> None:
    """Fail closed if the canonical callable surface drifts under this adapter."""

    try:
        parameters = tuple(inspect.signature(guard.run_guarded_build).parameters)
    except (TypeError, ValueError, AttributeError) as error:
        raise ResolutionGuardError("canonical private-input guard API is unavailable") from error
    if parameters != _EXPECTED_RUN_GUARDED_BUILD_PARAMETERS:
        raise ResolutionGuardError(
            "canonical private-input guard API drifted; dependency-resolution authority requires review"
        )


def _lexical_absolute(path: Path) -> Path:
    raw = os.fspath(path)
    if not raw or "\x00" in raw:
        raise ResolutionGuardError("dependency-resolution input path is invalid")
    return Path(os.path.abspath(os.path.normpath(raw)))


def _require_real_checkout_path(
    path: Path,
    root: Path,
    *,
    label: str,
    expected_kind: str,
) -> Path:
    """Admit one path only through real, symlink-free ancestry beneath checkout root."""

    authority_root = _lexical_absolute(root)
    candidate = _lexical_absolute(path)
    try:
        relative = candidate.relative_to(authority_root)
    except ValueError as error:
        raise ResolutionGuardError(f"{label} escaped the dependency checkout root") from error
    if not relative.parts:
        raise ResolutionGuardError(f"{label} must name a checkout child")

    current = authority_root
    try:
        root_metadata = os.lstat(current)
    except OSError as error:
        raise ResolutionGuardError("dependency checkout root is unavailable") from error
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        raise ResolutionGuardError("dependency checkout root must be one real directory")

    metadata = root_metadata
    for index, component in enumerate(relative.parts):
        current = current / component
        try:
            metadata = os.lstat(current)
        except OSError as error:
            raise ResolutionGuardError(f"{label} is unavailable") from error
        if stat.S_ISLNK(metadata.st_mode):
            raise ResolutionGuardError(f"{label} ancestry must not contain symlinks")
        if index < len(relative.parts) - 1 and not stat.S_ISDIR(metadata.st_mode):
            raise ResolutionGuardError(f"{label} ancestry must contain only real directories")

    if expected_kind == "file":
        if not stat.S_ISREG(metadata.st_mode):
            raise ResolutionGuardError(f"{label} must be one real regular file")
    elif expected_kind == "directory":
        if not stat.S_ISDIR(metadata.st_mode):
            raise ResolutionGuardError(f"{label} must be one real directory")
    else:
        raise ResolutionGuardError("dependency adapter requested an unknown path kind")
    return candidate


def _parse_args(guard, argv: Sequence[str]):
    parser = argparse.ArgumentParser(
        description="Run pre-generated private Tuya dependency work under vnode custody."
    )
    parser.add_argument("--lockfile", required=True, type=Path)
    parser.add_argument("--security-podspec", required=True, type=Path)
    parser.add_argument("--security-build", required=True, type=Path)
    parser.add_argument("--identity-podspec", required=True, type=Path)
    parser.add_argument("--identity-sources", required=True, type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    command = list(args.command)
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        raise ResolutionGuardError("no guarded dependency command was supplied")

    # The tracked Podfile is the stable regular-file anchor and defines checkout
    # root for this earlier dependency-resolution window. Every private subject
    # must be physically beneath that same real, symlink-free root.
    lockfile = _lexical_absolute(args.lockfile)
    root = lockfile.parent
    lockfile = _require_real_checkout_path(
        lockfile, root, label="dependency manifest anchor", expected_kind="file"
    )
    security_podspec = _require_real_checkout_path(
        args.security_podspec, root, label="private security podspec", expected_kind="file"
    )
    security_build = _require_real_checkout_path(
        args.security_build, root, label="private security build tree", expected_kind="directory"
    )
    identity_podspec = _require_real_checkout_path(
        args.identity_podspec, root, label="private identity podspec", expected_kind="file"
    )
    identity_sources = _require_real_checkout_path(
        args.identity_sources, root, label="private identity source tree", expected_kind="directory"
    )
    return (
        guard.PrivateInputs(
            lockfile=lockfile,
            security_podspec=security_podspec,
            security_build=security_build,
            identity_podspec=identity_podspec,
            identity_sources=identity_sources,
        ),
        command,
    )


def main(argv: Sequence[str] | None = None) -> int:
    try:
        guard = _load_guard()
        _require_private_only_guard_api(guard)
        inputs, command = _parse_args(guard, sys.argv[1:] if argv is None else argv)
        return guard.run_guarded_build(inputs, command)
    except ResolutionGuardError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 74
    except Exception as error:
        guard_error = getattr(locals().get("guard", None), "BuildGuardError", ())
        if guard_error and isinstance(error, guard_error):
            print(f"ERROR: {error}", file=sys.stderr)
            return 74
        print("ERROR: unexpected dependency-resolution custody failure", file=sys.stderr)
        return 77


if __name__ == "__main__":
    raise SystemExit(main())
