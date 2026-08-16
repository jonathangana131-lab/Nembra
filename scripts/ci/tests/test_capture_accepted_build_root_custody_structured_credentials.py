#!/usr/bin/env python3
"""Re-run accepted build-root custody with macOS-safe structured credentials.

Validation-only successor for the #3419 witness harness. The production custody
helper and the parent custody assertions remain byte-identical. This wrapper
replaces only the field-attacker subprocess launcher: Python's structured
``user``/``group``/``extra_groups`` Popen contract is used instead of a
``preexec_fn`` that currently aborts before exec on the xcode-27 runner.

No signing, install, device, Bluetooth, Tuya, telemetry, command, or physical
authority is created by this witness.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
from pathlib import Path
import pwd
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve()
PARENT_WITNESS = HERE.with_name("test_capture_accepted_build_root_custody.py")


def load_parent_witness():
    spec = importlib.util.spec_from_file_location(
        "nembra_build_root_custody_parent_witness",
        PARENT_WITNESS,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load parent accepted build-root custody witness")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def structured_field_run(
    field: pwd.struct_passwd,
    groups: tuple[int, ...],
    source: str,
    *paths: Path,
) -> subprocess.CompletedProcess[str]:
    """Launch the real field identity without unsafe post-fork Python hooks."""

    extra_groups = sorted({int(group) for group in groups if int(group) != field.pw_gid})
    if field.pw_uid <= 0 or field.pw_gid <= 0 or any(group <= 0 for group in extra_groups):
        raise RuntimeError("field credential fixture is invalid")
    return subprocess.run(
        ["/usr/bin/python3", "-I", "-c", source, *[str(path) for path in paths]],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        user=field.pw_uid,
        group=field.pw_gid,
        extra_groups=extra_groups,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--field-user", required=True)
    args, remaining = parser.parse_known_args()
    if remaining:
        raise RuntimeError(f"unexpected test arguments: {remaining!r}")

    os.environ["NEMBRA_TEST_FIELD_USER"] = args.field_user
    parent = load_parent_witness()
    parent.field_run = structured_field_run

    suite = unittest.defaultTestLoader.loadTestsFromTestCase(
        parent.AcceptedBuildRootCustodyTests
    )
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
