#!/usr/bin/env python3
"""Run pre-generated Tuya dependency work under private-input vnode custody.

This is intentionally *not* the physical field-build CLI. The canonical build
guard's CLI protects the later xcodebuild window. Dependency resolution runs one
rung earlier, before generated CocoaPods subjects can exist.

The canonical guard deliberately preserves a private-only `run_guarded_build`
API whose authority is exactly the five admitted inputs plus the child command.
This adapter exposes only that narrow mode. It grants no xcodebuild,
generated-build, private-review, source-acceptance, or physical GO authority.
The child command must independently establish semantic authority (bootstrap
uses the root-sealed private-identity receipt) after vnode watchers are armed.
"""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
import sys
from typing import Sequence


class ResolutionGuardError(RuntimeError):
    pass


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
        inputs, command = _parse_args(guard, sys.argv[1:] if argv is None else argv)
        # This is the canonical guard's deliberately narrow private API. Its
        # current contract takes the admitted PrivateInputs + child command;
        # dependency-resolution authority is not expressed through optional
        # "disable acceptance" toggles that the canonical guard does not own.
        # Bootstrap independently re-verifies the root-sealed private identity
        # inside the already-armed vnode window before the child executes.
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
