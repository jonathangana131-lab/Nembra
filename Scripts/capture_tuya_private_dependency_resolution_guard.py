#!/usr/bin/env python3
"""Run pre-generated Tuya dependency work under private-input vnode custody.

This is intentionally *not* the physical field-build CLI. The canonical build
guard's CLI requires accepted tracked-source, generated CocoaPods, private-review,
and helper authority because it protects xcodebuild. Dependency resolution runs
one rung earlier, before those generated subjects can exist.

The canonical guard deliberately preserves a private-only `run_guarded_build`
API for callers whose five admitted inputs are the lock/manifest anchor plus the
private security and identity trees. This adapter exposes only that narrow mode.
It grants no xcodebuild, generated-build, private-review, source-acceptance, or
physical GO authority. The child command must independently establish semantic
authority (bootstrap uses the root-sealed private-identity receipt) after vnode
watchers are armed.
"""

from __future__ import annotations

import argparse
import importlib.util
import inspect
from pathlib import Path
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


def _load_guard():
    guard_path = Path(__file__).with_name("capture_tuya_private_input_build_guard.py")
    if not guard_path.is_file() or guard_path.is_symlink():
        raise ResolutionGuardError("canonical private-input build guard is missing or symlinked")
    spec = importlib.util.spec_from_file_location(
        "nembra_private_dependency_resolution_build_guard",
        guard_path,
    )
    if spec is None or spec.loader is None:
        raise ResolutionGuardError("canonical private-input build guard could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _require_private_only_guard_api(guard) -> None:
    """Fail closed if the canonical callable surface drifts under this adapter.

    The current canonical guard is itself the narrow private-input vnode-custody
    primitive. This adapter deliberately calls only its two positional authority
    inputs and relies on the three test-injection parameters retaining their
    current defaults. Any signature change requires an explicit adapter review
    instead of silently inheriting a broader or differently gated authority mode.
    """

    try:
        parameters = tuple(inspect.signature(guard.run_guarded_build).parameters)
    except (TypeError, ValueError, AttributeError) as error:
        raise ResolutionGuardError("canonical private-input guard API is unavailable") from error
    if parameters != _EXPECTED_RUN_GUARDED_BUILD_PARAMETERS:
        raise ResolutionGuardError(
            "canonical private-input guard API drifted; dependency-resolution authority requires review"
        )


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

    # Reuse the canonical guard's ancestry admission exactly. The lockfile slot
    # is a generic watched regular-file anchor here; bootstrap intentionally
    # supplies the tracked Podfile because CocoaPods executes it.
    lockfile = guard._lexical_absolute(args.lockfile)
    root = lockfile.parent
    lockfile = guard._require_real_checkout_ancestry(lockfile, root, label="dependency manifest anchor")
    security_podspec = guard._require_real_checkout_ancestry(
        args.security_podspec, root, label="private security podspec"
    )
    security_build = guard._require_real_checkout_ancestry(
        args.security_build, root, label="private security build tree"
    )
    identity_podspec = guard._require_real_checkout_ancestry(
        args.identity_podspec, root, label="private identity podspec"
    )
    identity_sources = guard._require_real_checkout_ancestry(
        args.identity_sources, root, label="private identity source tree"
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
