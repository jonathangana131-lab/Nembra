#!/usr/bin/env python3
"""Expected-red portable witness for partial trusted-bootstrap principal cleanup.

This test executes the real `root_main()` control flow from the current trusted-bootstrap
hardening validator while replacing only platform side effects. It injects a Directory
Services failure after the synthetic group and user records have begun materializing.
The validator must still retire all partially-created principal state before the failure
escapes. No macOS, sudo, signing identity, Xcode, device, Bluetooth, or physical authority
is exercised by this portable witness.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SUBJECT = ROOT / "scripts/ci/tests/test_capture_apple_signing_trusted_bootstrap_hardening.py"
spec = importlib.util.spec_from_file_location("capture_bootstrap_hardening_subject", SUBJECT)
if spec is None or spec.loader is None:
    raise SystemExit("could not load trusted-bootstrap hardening subject")
subject = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subject)

numeric_id = 654_321
records: dict[str, set[str]] = {"Users": set(), "Groups": set()}
cleanup_calls: list[tuple[str, int]] = []
injected = {"fired": False}


def fake_run(argv, *, check=False, **_kwargs):
    command = list(argv)
    if command[:3] == ["/usr/bin/dscl", ".", "-create"]:
        path = command[3]
        if path.startswith("/Groups/") and len(command) == 4:
            records["Groups"].add(path.removeprefix("/Groups/"))
        elif path.startswith("/Users/") and len(command) == 4:
            records["Users"].add(path.removeprefix("/Users/"))
        elif path.startswith("/Users/") and len(command) >= 5 and command[4] == "UniqueID":
            injected["fired"] = True
            completed = subprocess.CompletedProcess(command, 73, "", "injected partial user creation failure")
            if check:
                raise subject.ValidationError(
                    f"command failed rc={completed.returncode}: {command!r} stderr={completed.stderr!r}"
                )
            return completed
        return subprocess.CompletedProcess(command, 0, "", "")
    return subprocess.CompletedProcess(command, 0, "", "")


def fake_record_exists(kind: str, name: str) -> bool:
    return name in records[kind]


def fake_cleanup(name: str, candidate_id: int) -> None:
    cleanup_calls.append((name, candidate_id))
    records["Users"].discard(name)
    records["Groups"].discard(name)


with tempfile.TemporaryDirectory() as temp_dir:
    temp = Path(temp_dir)
    private_tmp = temp / "private-tmp"
    sudoers_dir = temp / "sudoers.d"
    private_tmp.mkdir()
    sudoers_dir.mkdir()

    original_platform = subject.sys.platform
    original_geteuid = subject.os.geteuid
    original_chown = subject.os.chown
    original_require = subject.require
    try:
        subject.sys.platform = "darwin"
        subject.os.geteuid = lambda: 0
        subject.os.chown = lambda *_args, **_kwargs: None
        subject.ROOT_PREFIX = private_tmp
        subject.SUDOERS_DIR = sudoers_dir

        # Keep the real require behavior except for host-tool presence: the portable witness
        # does not execute sudo/visudo and should not depend on an Ubuntu image shipping them.
        def portable_require(condition: bool, message: str) -> None:
            if message == "sudo/visudo unavailable":
                return
            original_require(condition, message)

        subject.require = portable_require
        subject.run = fake_run
        subject.ds_record_exists = fake_record_exists
        subject.identity_records_are_free = lambda _candidate: True
        subject.numeric_identity_is_fresh = lambda _candidate: False
        subject.choose_direct_record_free_probe_id = lambda: numeric_id + 1
        subject.spawn_orphan_numeric_uid_probe = lambda _candidate: object()
        subject.stop_probe = lambda _probe: None
        subject.wait_for_numeric_uid_processes = lambda *_args, **_kwargs: []
        subject.choose_numeric_identity = lambda: numeric_id
        subject.require_no_numeric_uid_processes = lambda *_args, **_kwargs: None
        subject.delete_identity_after_process_retirement = fake_cleanup

        try:
            subject.root_main()
        except subject.ValidationError as error:
            failure = str(error)
        else:
            raise SystemExit("injected partial Directory Services failure did not escape as RED")
    finally:
        subject.sys.platform = original_platform
        subject.os.geteuid = original_geteuid
        subject.os.chown = original_chown
        subject.require = original_require

if not injected["fired"]:
    raise SystemExit("partial-principal failure injection never fired")
if not records["Users"] and not records["Groups"]:
    print("partial trusted-bootstrap principal cleanup: PASS")
    raise SystemExit(0)

print(
    "EXPECTED RED: partial trusted-bootstrap principal state escaped cleanup; "
    f"records={records!r} cleanupCalls={cleanup_calls!r} failure={failure!r}"
)
raise SystemExit(1)