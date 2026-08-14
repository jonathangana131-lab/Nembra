#!/usr/bin/env python3
"""Validation-only hardening witness for the Apple-signing trusted bootstrap boundary.

This successor closes two adversarial gaps left by the first harmless trusted-bootstrap witness:
(1) the sudoers capability is explicitly argument-free, so attacker argv is rejected before the
root launcher starts; and (2) a synthetic numeric UID/GID is never admitted or retired while any
live or zombie process still carries that numeric principal.

The launcher remains deliberately harmless. This test does not query signing identities, run
xcodebuild, touch Bluetooth or a device, install an app, or create physical Capture authority.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import grp
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from typing import Sequence


class ValidationError(RuntimeError):
    pass


MARKER = "NEMBRA_APPLE_SIGNING_TRUSTED_BOOTSTRAP_HARDENING_JSON="
ROOT_PREFIX = Path("/private/tmp")
SUDOERS_DIR = Path("/private/etc/sudoers.d")


def run(argv: Sequence[str], *, check: bool = False, **kwargs) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        list(argv),
        stdin=kwargs.pop("stdin", subprocess.DEVNULL),
        stdout=kwargs.pop("stdout", subprocess.PIPE),
        stderr=kwargs.pop("stderr", subprocess.PIPE),
        text=kwargs.pop("text", True),
        check=False,
        **kwargs,
    )
    if check and completed.returncode != 0:
        raise ValidationError(
            f"command failed rc={completed.returncode}: {list(argv)!r}\n"
            f"stdout={completed.stdout[-1200:]!r}\nstderr={completed.stderr[-1200:]!r}"
        )
    return completed


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def numeric_uid_processes(numeric_id: int) -> list[tuple[int, str]]:
    """Return every process (including zombies) whose real UID equals numeric_id.

    Any ps execution or parse ambiguity is infrastructure RED. Treating an unreadable process
    inventory as empty would recreate the authority hole this witness exists to close.
    """

    result = run(["/bin/ps", "-axo", "uid=,pid=,stat="])
    require(result.returncode == 0, f"process inventory failed: {result.stderr[-800:]!r}")
    matches: list[tuple[int, str]] = []
    for line_number, raw_line in enumerate(result.stdout.splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue
        fields = line.split()
        require(len(fields) == 3, f"unclassifiable process inventory line {line_number}: {raw_line!r}")
        uid_text, pid_text, state = fields
        try:
            uid = int(uid_text, 10)
            pid = int(pid_text, 10)
        except ValueError as error:
            raise ValidationError(
                f"unclassifiable process inventory identifiers at line {line_number}: {raw_line!r}"
            ) from error
        require(uid >= 0 and pid > 0 and bool(state), f"invalid process inventory line {line_number}: {raw_line!r}")
        if uid == numeric_id:
            matches.append((pid, state))
    return matches


def identity_records_are_free(numeric_id: int) -> bool:
    try:
        pwd.getpwuid(numeric_id)
        return False
    except KeyError:
        pass
    try:
        grp.getgrgid(numeric_id)
        return False
    except KeyError:
        return True


def numeric_identity_is_fresh(numeric_id: int) -> bool:
    return identity_records_are_free(numeric_id) and not numeric_uid_processes(numeric_id)


def choose_numeric_identity() -> int:
    seed = 600_000 + (os.getpid() % 20_000)
    for candidate in range(seed, seed + 10_000):
        if numeric_identity_is_fresh(candidate):
            return candidate
    raise ValidationError("could not find a process-free synthetic UID/GID")


def require_no_numeric_uid_processes(numeric_id: int, phase: str) -> None:
    occupants = numeric_uid_processes(numeric_id)
    require(not occupants, f"numeric UID {numeric_id} is process-occupied during {phase}: {occupants!r}")


def wait_for_numeric_uid_processes(numeric_id: int, *, present: bool, timeout_seconds: float) -> list[tuple[int, str]]:
    deadline = time.monotonic() + timeout_seconds
    last: list[tuple[int, str]] = []
    while True:
        last = numeric_uid_processes(numeric_id)
        if bool(last) is present:
            return last
        if time.monotonic() >= deadline:
            state = "appear" if present else "retire"
            raise ValidationError(
                f"numeric UID {numeric_id} processes did not {state} within {timeout_seconds:.1f}s: {last!r}"
            )
        time.sleep(0.10)


def retire_numeric_uid_processes(numeric_id: int) -> None:
    result = run(["/usr/bin/pkill", "-KILL", "-U", str(numeric_id)])
    require(result.returncode in (0, 1), f"pkill could not retire numeric UID {numeric_id}: {result.stderr[-800:]!r}")
    wait_for_numeric_uid_processes(numeric_id, present=False, timeout_seconds=10.0)


def ds_record_exists(kind: str, name: str) -> bool:
    result = run(["/usr/bin/dscl", ".", "-read", f"/{kind}/{name}"])
    if result.returncode == 0:
        return True
    detail = (result.stderr or "") + "\n" + (result.stdout or "")
    if "eDSRecordNotFound" in detail or "-14136" in detail or "Record was not found" in detail:
        return False
    listing = run(["/usr/bin/dscl", ".", "-list", f"/{kind}", "RecordName"], check=True)
    names = {line.split()[0] for line in listing.stdout.splitlines() if line.split()}
    if name not in names:
        return False
    raise ValidationError(f"Directory Services {kind}/{name} state is unclassifiable: {detail[-800:]!r}")


def create_identity(name: str, numeric_id: int) -> None:
    require(identity_records_are_free(numeric_id), "numeric UID/GID records appeared before identity creation")
    require_no_numeric_uid_processes(numeric_id, "pre-creation recheck")
    commands = [
        ["/usr/bin/dscl", ".", "-create", f"/Groups/{name}"],
        ["/usr/bin/dscl", ".", "-create", f"/Groups/{name}", "PrimaryGroupID", str(numeric_id)],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UniqueID", str(numeric_id)],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "PrimaryGroupID", str(numeric_id)],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "NFSHomeDirectory", "/var/empty"],
        ["/usr/bin/dscl", ".", "-create", f"/Users/{name}", "UserShell", "/bin/sh"],
    ]
    for command in commands:
        run(command, check=True)
    require(ds_record_exists("Users", name), "synthetic field user was not materialized")
    require(ds_record_exists("Groups", name), "synthetic field group was not materialized")


def delete_identity_after_process_retirement(name: str, numeric_id: int) -> None:
    retire_numeric_uid_processes(numeric_id)
    require_no_numeric_uid_processes(numeric_id, "before Directory Services deletion")
    for kind in ("Users", "Groups"):
        if ds_record_exists(kind, name):
            result = run(["/usr/bin/dscl", ".", "-delete", f"/{kind}/{name}"])
            require(result.returncode == 0, f"failed to delete synthetic {kind}/{name}: {result.stderr[-800:]!r}")
    flush = run(["/usr/bin/dscacheutil", "-flushcache"])
    require(flush.returncode == 0, f"Directory Services cache flush failed: {flush.stderr[-800:]!r}")
    require(not ds_record_exists("Users", name), "synthetic field user survived cleanup")
    require(not ds_record_exists("Groups", name), "synthetic field group survived cleanup")
    require(identity_records_are_free(numeric_id), "numeric UID/GID remained name-service occupied after cleanup")
    require_no_numeric_uid_processes(numeric_id, "post-deletion recheck")


def choose_direct_record_free_probe_id() -> int:
    seed = 630_000 + (os.getpid() % 10_000)
    for candidate in range(seed, seed + 10_000):
        if identity_records_are_free(candidate) and not numeric_uid_processes(candidate):
            return candidate
    raise ValidationError("could not find numeric UID for process-occupancy adversary")


def spawn_orphan_numeric_uid_probe(numeric_id: int) -> subprocess.Popen[str]:
    code = (
        "import os,time; "
        f"os.setgid({numeric_id}); os.setuid({numeric_id}); "
        "print(os.getuid(), flush=True); time.sleep(30)"
    )
    probe = subprocess.Popen(
        ["/usr/bin/python3", "-B", "-I", "-c", code],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    require(probe.stdout is not None, "orphan numeric-UID probe stdout unavailable")
    observed = probe.stdout.readline().strip()
    if observed != str(numeric_id):
        stderr = probe.stderr.read()[-800:] if probe.stderr is not None else ""
        try:
            probe.kill()
        except ProcessLookupError:
            pass
        probe.wait(timeout=5)
        raise ValidationError(f"orphan numeric-UID probe did not enter target UID: observed={observed!r} stderr={stderr!r}")
    wait_for_numeric_uid_processes(numeric_id, present=True, timeout_seconds=3.0)
    return probe


def stop_probe(probe: subprocess.Popen[str] | None) -> None:
    if probe is None or probe.poll() is not None:
        return
    probe.kill()
    try:
        probe.wait(timeout=5)
    except subprocess.TimeoutExpired as error:
        raise ValidationError("orphan numeric-UID probe could not be reaped") from error


def write_root_subject(directory: Path) -> tuple[Path, Path, bytes, str]:
    launcher = directory / "nembra-apple-signing-bootstrap-hardened"
    invocation_log = directory / "launcher-invocations.log"
    log_fd = os.open(invocation_log, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    os.close(log_fd)
    os.chown(invocation_log, 0, 0)
    os.chmod(invocation_log, 0o600)
    log_literal = str(invocation_log).replace("'", "'\\''")
    body = (
        b"#!/bin/sh\n"
        b"set -eu\n"
        + f"printf 'argc=%s\\n' \"$#\" >> '{log_literal}'\n".encode("utf-8")
        + b"test \"$#\" -eq 0\n"
        + b"test \"$(/usr/bin/id -u)\" = 0\n"
        + b"printf 'NEMBRA_TRUSTED_BOOTSTRAP_ROOT_UID=%s\\n' \"$(/usr/bin/id -u)\"\n"
    )
    fd = os.open(launcher, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o555)
    try:
        os.write(fd, body)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.chown(launcher, 0, 0)
    os.chmod(launcher, 0o555)
    info = launcher.lstat()
    require(stat.S_ISREG(info.st_mode) and not launcher.is_symlink(), "trusted launcher is not one regular file")
    require(info.st_uid == 0 and info.st_gid == 0, "trusted launcher is not root-owned")
    require(stat.S_IMODE(info.st_mode) == 0o555, "trusted launcher mode is not 0555")
    digest = hashlib.sha256(body).hexdigest()
    require(hashlib.sha256(launcher.read_bytes()).hexdigest() == digest, "trusted launcher bytes changed after publication")
    return launcher, invocation_log, body, digest


def install_argument_free_sudoers_rule(user: str, launcher: Path, digest: str, rule_path: Path) -> None:
    require(SUDOERS_DIR.is_dir() and not SUDOERS_DIR.is_symlink(), "macOS sudoers.d directory is unavailable or aliased")
    rule = (
        f"Defaults:{user} timestamp_timeout=0\n"
        f'{user} ALL = (root) NOPASSWD: sha256:{digest} {launcher} ""\n'
    )
    fd = os.open(rule_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o440)
    try:
        os.write(fd, rule.encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)
    os.chown(rule_path, 0, 0)
    os.chmod(rule_path, 0o440)
    check = run(["/usr/sbin/visudo", "-cf", str(rule_path)])
    require(check.returncode == 0, f"argument-free restricted sudoers rule is invalid: {check.stderr[-800:]!r}")


def as_user(user: str, command: str) -> subprocess.CompletedProcess[str]:
    return run(["/usr/bin/sudo", "-n", "-u", user, "/bin/sh", "-c", command])


def quoted(path: Path) -> str:
    return "'" + str(path).replace("'", "'\\''") + "'"


def root_main(output: Path) -> int:
    require(sys.platform == "darwin", "trusted-bootstrap hardening witness requires macOS")
    require(os.geteuid() == 0, "trusted-bootstrap hardening root phase requires uid 0")
    require(Path("/usr/bin/sudo").exists() and Path("/usr/sbin/visudo").exists(), "sudo/visudo unavailable")

    evidence: dict[str, object] = {
        "schema": 1,
        "validationOnly": True,
        "physicalAuthorityCreated": False,
        "signingIdentityQueried": False,
        "xcodebuildExecuted": False,
        "deviceOrBluetoothExecuted": False,
    }

    orphan_probe: subprocess.Popen[str] | None = None
    orphan_id = choose_direct_record_free_probe_id()
    try:
        orphan_probe = spawn_orphan_numeric_uid_probe(orphan_id)
        require(not numeric_identity_is_fresh(orphan_id), "process-occupied orphan numeric UID was treated as fresh")
        evidence["orphanedNumericUidProcessRejected"] = True
    finally:
        stop_probe(orphan_probe)
        wait_for_numeric_uid_processes(orphan_id, present=False, timeout_seconds=3.0)

    numeric_id = choose_numeric_identity()
    require_no_numeric_uid_processes(numeric_id, "post-selection pre-creation")
    evidence["freshNumericUidProcessFreeBeforeCreation"] = True
    user = f"_nembra_bootstrap_hardened_{numeric_id}"
    require(re.fullmatch(r"_[A-Za-z0-9_]+", user) is not None, "synthetic username is unsafe")

    root_dir = Path(tempfile.mkdtemp(prefix="nembra-trusted-bootstrap-hardening.", dir=str(ROOT_PREFIX)))
    os.chown(root_dir, 0, 0)
    os.chmod(root_dir, 0o755)
    rule_path = SUDOERS_DIR / f"nembra-trusted-bootstrap-hardening-{numeric_id}"
    identity_created = False

    try:
        create_identity(user, numeric_id)
        identity_created = True
        launcher, invocation_log, _body, digest = write_root_subject(root_dir)
        install_argument_free_sudoers_rule(user, launcher, digest, rule_path)

        generic = as_user(
            user,
            "/usr/bin/sudo -k >/dev/null 2>&1 || true; "
            "/usr/bin/sudo -n /usr/bin/python3 -B -I -c 'import os; print(os.geteuid())'",
        )
        detail = (generic.stdout or "") + "\n" + (generic.stderr or "")
        require(generic.returncode != 0, "fresh field identity unexpectedly retained generic noninteractive sudo")
        require("\n0\n" not in f"\n{detail}\n", "generic noninteractive sudo obtained a root-UID witness")
        evidence["genericNoninteractiveSudoDenied"] = True

        trusted = as_user(user, f"/usr/bin/sudo -n {quoted(launcher)}")
        require(trusted.returncode == 0, f"explicit no-argv trusted launcher was not admitted: {trusted.stderr[-800:]!r}")
        require("NEMBRA_TRUSTED_BOOTSTRAP_ROOT_UID=0" in trusted.stdout, "trusted launcher did not execute as uid 0")
        before_lines = invocation_log.read_text(encoding="utf-8").splitlines()
        require(before_lines == ["argc=0"], f"unexpected trusted-launcher invocation log before argv attack: {before_lines!r}")
        evidence["explicitNoArgRuleAdmitted"] = True

        attacker_arg = as_user(user, f"/usr/bin/sudo -n {quoted(launcher)} attacker-arg")
        require(attacker_arg.returncode != 0, "sudo admitted attacker argv through the explicit no-argument rule")
        after_lines = invocation_log.read_text(encoding="utf-8").splitlines()
        require(
            after_lines == before_lines,
            f"attacker argv reached the root launcher before rejection: before={before_lines!r} after={after_lines!r}",
        )
        evidence["attackerArgDeniedBeforeLauncherStart"] = True
    finally:
        if rule_path.exists() or rule_path.is_symlink():
            rule_path.unlink()
        if identity_created:
            delete_identity_after_process_retirement(user, numeric_id)
            evidence["numericUidProcessesRetiredBeforeDeletion"] = True
            evidence["numericUidProcessFreeAfterDeletion"] = True
        shutil.rmtree(root_dir, ignore_errors=True)

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, sort_keys=True) + "\n", encoding="utf-8")
    print(MARKER + json.dumps(evidence, sort_keys=True))
    print("TRUSTED_BOOTSTRAP_HARDENING_ACCEPTED validationOnly=true physicalAuthorityCreated=false")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--root-child", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()

    if args.root_child:
        return root_main(output)

    require(sys.platform == "darwin", "trusted-bootstrap hardening witness requires macOS")
    require(os.geteuid() != 0, "outer validation phase must begin as the ordinary runner identity")
    result = run(
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/python3",
            "-B",
            "-I",
            str(Path(__file__).resolve()),
            "--output",
            str(output),
            "--root-child",
        ]
    )
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    require(result.returncode == 0, "root trusted-bootstrap hardening phase failed")
    require(output.is_file(), "trusted-bootstrap hardening evidence file was not produced")
    payload = json.loads(output.read_text(encoding="utf-8"))
    required_true = (
        "orphanedNumericUidProcessRejected",
        "freshNumericUidProcessFreeBeforeCreation",
        "genericNoninteractiveSudoDenied",
        "explicitNoArgRuleAdmitted",
        "attackerArgDeniedBeforeLauncherStart",
        "numericUidProcessesRetiredBeforeDeletion",
        "numericUidProcessFreeAfterDeletion",
    )
    for key in required_true:
        require(payload.get(key) is True, f"missing trusted-bootstrap hardening invariant: {key}")
    require(payload.get("physicalAuthorityCreated") is False, "validation must not create physical authority")
    require(payload.get("signingIdentityQueried") is False, "validation unexpectedly queried signing identity")
    require(payload.get("xcodebuildExecuted") is False, "validation unexpectedly ran xcodebuild")
    require(payload.get("deviceOrBluetoothExecuted") is False, "validation unexpectedly touched device/Bluetooth")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValidationError as error:
        print(f"TRUSTED_BOOTSTRAP_HARDENING_REJECTED: {error}", file=sys.stderr)
        raise SystemExit(1)
