#!/usr/bin/env python3
"""Validation-only macOS witness for a restricted Apple-signing bootstrap boundary.

This test does not run the signing oracle or create product/physical authority. It proves a
necessary replacement for the mutable-wrapper bootstrap rejected by #3226: after entry into a
fresh non-admin field identity, noninteractive sudo may invoke exactly one root-owned,
digest-pinned launcher while the same caller cannot spend generic root authority.

The launcher used here is deliberately harmless and fixed: it prints one root-UID marker. A later
production successor must replace that harmless body with independently reviewed accepted-object
materialization/sealing, install it through a separate administrator-trusted setup step, revoke any
ambient generic sudo timestamp, and re-earn exact-head validation before private field execution.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import grp
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from typing import Sequence


class ValidationError(RuntimeError):
    pass


MARKER = "NEMBRA_APPLE_SIGNING_TRUSTED_BOOTSTRAP_JSON="
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


def choose_numeric_identity() -> int:
    seed = 600_000 + (os.getpid() % 20_000)
    for candidate in range(seed, seed + 10_000):
        try:
            pwd.getpwuid(candidate)
            continue
        except KeyError:
            pass
        try:
            grp.getgrgid(candidate)
            continue
        except KeyError:
            return candidate
    raise ValidationError("could not find a fresh synthetic UID/GID")


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


def delete_identity(name: str) -> None:
    for kind in ("Users", "Groups"):
        if ds_record_exists(kind, name):
            result = run(["/usr/bin/dscl", ".", "-delete", f"/{kind}/{name}"])
            if result.returncode != 0:
                raise ValidationError(f"failed to delete synthetic {kind}/{name}: {result.stderr[-800:]!r}")
    run(["/usr/bin/dscacheutil", "-flushcache"])
    require(not ds_record_exists("Users", name), "synthetic field user survived cleanup")
    require(not ds_record_exists("Groups", name), "synthetic field group survived cleanup")


def write_root_subject(directory: Path) -> tuple[Path, bytes, str]:
    launcher = directory / "nembra-apple-signing-bootstrap"
    body = (
        b"#!/bin/sh\n"
        b"set -eu\n"
        b"test \"$#\" -eq 0\n"
        b"test \"$(/usr/bin/id -u)\" = 0\n"
        b"printf 'NEMBRA_TRUSTED_BOOTSTRAP_ROOT_UID=%s\\n' \"$(/usr/bin/id -u)\"\n"
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
    return launcher, body, digest


def install_sudoers_rule(user: str, launcher: Path, digest: str, rule_path: Path) -> None:
    require(SUDOERS_DIR.is_dir() and not SUDOERS_DIR.is_symlink(), "macOS sudoers.d directory is unavailable or aliased")
    rule = (
        f"Defaults:{user} timestamp_timeout=0\n"
        f"{user} ALL = (root) NOPASSWD: sha256:{digest} {launcher}\n"
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
    require(check.returncode == 0, f"temporary restricted sudoers rule is invalid: {check.stderr[-800:]!r}")


def as_user(user: str, command: str) -> subprocess.CompletedProcess[str]:
    return run(["/usr/bin/sudo", "-n", "-u", user, "/bin/sh", "-c", command])


def quoted(path: Path) -> str:
    return "'" + str(path).replace("'", "'\\''") + "'"


def root_main(output: Path) -> int:
    require(sys.platform == "darwin", "trusted-bootstrap witness requires macOS")
    require(os.geteuid() == 0, "trusted-bootstrap root phase requires uid 0")
    require(Path("/usr/bin/sudo").exists() and Path("/usr/sbin/visudo").exists(), "sudo/visudo unavailable")

    numeric_id = choose_numeric_identity()
    user = f"_nembra_bootstrap_{numeric_id}"
    require(re.fullmatch(r"_[A-Za-z0-9_]+", user) is not None, "synthetic username is unsafe")
    root_dir = Path(tempfile.mkdtemp(prefix="nembra-trusted-bootstrap.", dir=str(ROOT_PREFIX)))
    os.chown(root_dir, 0, 0)
    os.chmod(root_dir, 0o755)
    caller_dir = root_dir / "caller"
    caller_dir.mkdir(mode=0o700)
    os.chown(caller_dir, numeric_id, numeric_id)
    os.chmod(caller_dir, 0o700)
    rule_path = SUDOERS_DIR / f"nembra-trusted-bootstrap-{numeric_id}"
    attacker = caller_dir / "caller-owned-wrapper.sh"
    evidence: dict[str, object] = {
        "schema": 1,
        "validationOnly": True,
        "physicalAuthorityCreated": False,
        "signingIdentityQueried": False,
        "xcodebuildExecuted": False,
        "deviceOrBluetoothExecuted": False,
    }

    try:
        create_identity(user, numeric_id)
        launcher, original_launcher, digest = write_root_subject(root_dir)
        install_sudoers_rule(user, launcher, digest, rule_path)

        generic = as_user(
            user,
            "/usr/bin/sudo -k >/dev/null 2>&1 || true; "
            "/usr/bin/sudo -n /usr/bin/python3 -B -I -c 'import os; print(os.geteuid())'",
        )
        generic_detail = (generic.stdout or "") + "\n" + (generic.stderr or "")
        require(generic.returncode != 0, "fresh field identity unexpectedly retained generic noninteractive sudo")
        require("\n0\n" not in f"\n{generic_detail}\n", "generic noninteractive sudo obtained a root-UID witness")
        evidence["genericNoninteractiveSudoDenied"] = True

        trusted = as_user(user, f"/usr/bin/sudo -n {quoted(launcher)}")
        require(trusted.returncode == 0, f"digest-pinned trusted launcher was not admitted: {trusted.stderr[-800:]!r}")
        require("NEMBRA_TRUSTED_BOOTSTRAP_ROOT_UID=0" in trusted.stdout, "trusted launcher did not execute as uid 0")
        evidence["digestPinnedLauncherAdmitted"] = True

        generic_out_path = caller_dir / "generic.out"
        generic_err_path = caller_dir / "generic.err"
        trusted_out_path = caller_dir / "trusted.out"
        trusted_err_path = caller_dir / "trusted.err"
        attack_body = f"""#!/bin/sh
set +e
/usr/bin/sudo -n /usr/bin/python3 -B -I -c 'import os; print(os.geteuid())' >{quoted(generic_out_path)} 2>{quoted(generic_err_path)}
generic_rc=$?
/usr/bin/sudo -n {quoted(launcher)} >{quoted(trusted_out_path)} 2>{quoted(trusted_err_path)}
trusted_rc=$?
printf 'GENERIC_RC=%s TRUSTED_RC=%s\n' "$generic_rc" "$trusted_rc"
test "$generic_rc" -ne 0
test "$trusted_rc" -eq 0
""".encode("utf-8")
        fd = os.open(attacker, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o700)
        try:
            os.write(fd, attack_body)
            os.fsync(fd)
        finally:
            os.close(fd)
        os.chown(attacker, numeric_id, numeric_id)
        os.chmod(attacker, 0o700)
        attacked = as_user(user, quoted(attacker))
        require(attacked.returncode == 0, f"caller-owned bootstrap adversary did not reach its assertions: {attacked.stderr[-800:]!r}")
        generic_out = generic_out_path.read_text(encoding="utf-8", errors="replace") if generic_out_path.exists() else ""
        trusted_out = trusted_out_path.read_text(encoding="utf-8", errors="replace") if trusted_out_path.exists() else ""
        require(generic_out.strip() != "0", "caller-owned wrapper obtained arbitrary root before any self-check")
        require("NEMBRA_TRUSTED_BOOTSTRAP_ROOT_UID=0" in trusted_out, "caller-owned wrapper could not invoke the fixed narrow launcher")
        evidence["mutableWrapperArbitraryRootDenied"] = True
        evidence["mutableWrapperCanOnlyReachNarrowLauncher"] = True

        launcher.write_bytes(original_launcher + b"# digest-mismatch\n")
        os.chown(launcher, 0, 0)
        os.chmod(launcher, 0o555)
        mismatch = as_user(user, f"/usr/bin/sudo -n {quoted(launcher)}")
        require(mismatch.returncode != 0, "sudo admitted a launcher whose bytes no longer match the authorized digest")
        evidence["digestMismatchRejected"] = True

        launcher.write_bytes(original_launcher)
        os.chown(launcher, 0, 0)
        os.chmod(launcher, 0o555)
        restored = as_user(user, f"/usr/bin/sudo -n {quoted(launcher)}")
        require(restored.returncode == 0 and "NEMBRA_TRUSTED_BOOTSTRAP_ROOT_UID=0" in restored.stdout, "restored exact launcher did not regain narrow authority")
        evidence["exactLauncherRestorationAdmitted"] = True

        mutation = as_user(user, f"printf x >> {quoted(launcher)}")
        replacement = as_user(user, f"rm -f {quoted(launcher)}")
        require(mutation.returncode != 0, "synthetic field identity mutated root-owned launcher")
        require(replacement.returncode != 0, "synthetic field identity replaced root-owned launcher")
        evidence["fieldLauncherMutationDenied"] = True
        evidence["fieldLauncherReplacementDenied"] = True

        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(evidence, sort_keys=True) + "\n", encoding="utf-8")
        print(MARKER + json.dumps(evidence, sort_keys=True))
        print("TRUSTED_BOOTSTRAP_BOUNDARY_ACCEPTED validationOnly=true physicalAuthorityCreated=false")
        return 0
    finally:
        try:
            if rule_path.exists() or rule_path.is_symlink():
                rule_path.unlink()
        finally:
            try:
                delete_identity(user)
            finally:
                shutil.rmtree(root_dir, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--root-child", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()

    if args.root_child:
        return root_main(output)

    require(sys.platform == "darwin", "trusted-bootstrap witness requires macOS")
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
    require(result.returncode == 0, "root validation phase failed")
    require(output.is_file(), "trusted-bootstrap evidence file was not produced")
    payload = json.loads(output.read_text(encoding="utf-8"))
    required_true = (
        "genericNoninteractiveSudoDenied",
        "digestPinnedLauncherAdmitted",
        "mutableWrapperArbitraryRootDenied",
        "mutableWrapperCanOnlyReachNarrowLauncher",
        "digestMismatchRejected",
        "exactLauncherRestorationAdmitted",
        "fieldLauncherMutationDenied",
        "fieldLauncherReplacementDenied",
    )
    for key in required_true:
        require(payload.get(key) is True, f"missing accepted bootstrap invariant: {key}")
    require(payload.get("physicalAuthorityCreated") is False, "validation must not create physical authority")
    require(payload.get("signingIdentityQueried") is False, "validation unexpectedly queried signing identity")
    require(payload.get("xcodebuildExecuted") is False, "validation unexpectedly ran xcodebuild")
    require(payload.get("deviceOrBluetoothExecuted") is False, "validation unexpectedly touched device/Bluetooth")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValidationError as error:
        print(f"TRUSTED_BOOTSTRAP_BOUNDARY_REJECTED: {error}", file=sys.stderr)
        raise SystemExit(1)
