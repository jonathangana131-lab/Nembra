#!/usr/bin/env python3
"""Materialize the exact ES80 signer runtime, including its post-materialization runner.

This is a thin pre-key composition over the accepted generic signer-bundle materializer. It adds the
external runner itself to the exact Git-object source set so the code that later receives a private-
key path was already copied and hashed before any key argument is supplied. This utility has no
private-key input and creates no field or physical authority.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
BASE_PATH = HERE / "es80_materialize_field_authorization_signer_bundle.py"
RUNNER_RELATIVE_PATH = "scripts/ci/es80_run_materialized_field_authorization_signer.py"
EXPECTED_BASE_SOURCES = (
    "scripts/ci/es80_sign_field_authorization_from_rendezvous.py",
    "scripts/ci/es80_field_authorization_rendezvous.py",
    "scripts/ci/es80_field_authorization_envelope.py",
    "scripts/ci/es80_signed_field_artifact_evidence.py",
)
EXECUTION_SOURCES = (RUNNER_RELATIVE_PATH, *EXPECTED_BASE_SOURCES)


def _load_base():
    spec = importlib.util.spec_from_file_location(
        "nembra_prekey_signer_bundle_materializer", BASE_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("pre-key signer bundle materializer is unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


base = _load_base()
PreKeyBundleError = base.PreKeyBundleError


def materialize(source_commit: str, output_directory: Path) -> dict[str, object]:
    if tuple(base.EXECUTION_SOURCES) != EXPECTED_BASE_SOURCES:
        raise PreKeyBundleError("accepted base signer source set drifted")
    original = base.EXECUTION_SOURCES
    base.EXECUTION_SOURCES = EXECUTION_SOURCES
    try:
        result = base.materialize(source_commit, output_directory)
    finally:
        base.EXECUTION_SOURCES = original
    result["runnerPath"] = os.fspath(
        Path(str(result["outputDirectory"])) / RUNNER_RELATIVE_PATH
    )
    return result


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(description=__doc__)
    value.add_argument("--source-commit", required=True)
    value.add_argument("--output-directory", type=Path, required=True)
    return value


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        result = materialize(args.source_commit, args.output_directory)
    except (PreKeyBundleError, RuntimeError, OSError) as error:
        print(f"REFUSED_NOT_AUTHORITY: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
