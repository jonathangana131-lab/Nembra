#!/usr/bin/env python3
"""Validation-only Darwin process-credential inventory for numeric UID/GID reuse.

This witness is intentionally read-only. It combines:
- KERN_PROC_ALL / struct kinfo_proc for PID + supplementary/advisory groups; and
- the system ps credential columns for effective/real/saved UID and GID slots.

The hybrid avoids proc_pidinfo(PROC_PIDTBSDINFO), which current macOS may deny
with EPERM for protected live processes when the witness is intentionally
unprivileged. Persistent PID-set disagreement between the two independent
snapshots fails closed; only a PID proven gone by ESRCH may be ignored.

No Directory Services records are created, sudo is never used, and no process
identity is changed.
"""
from __future__ import annotations

import errno
import grp
import json
import os
from pathlib import Path
import pwd
import subprocess
import sys
import tempfile


class ValidationError(RuntimeError):
    pass


MARKER = "NEMBRA_NUMERIC_PROCESS_CREDENTIAL_JSON="
MATCH_MARKER = "NEMBRA_PROCESS_CREDENTIAL_MATCH="
KERN_PID_MARKER = "NEMBRA_KERN_PROC_PID="

RUID = 1 << 0
EUID = 1 << 1
SVUID = 1 << 2
RGID = 1 << 3
EGID = 1 << 4
SVGID = 1 << 5
GROUP_LIST = 1 << 6

C_SOURCE = r'''
#include <sys/types.h>
#include <sys/param.h>
#include <sys/sysctl.h>
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GROUP_LIST_BIT (1u << 6)

static void die(const char *message) {
    fprintf(stderr, "credential inventory error: %s (errno=%d: %s)\n", message, errno, strerror(errno));
    exit(70);
}

static struct kinfo_proc *snapshot_processes(size_t *count_out) {
    int mib[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
    for (int attempt = 0; attempt < 8; ++attempt) {
        size_t needed = 0;
        if (sysctl(mib, 3, NULL, &needed, NULL, 0) != 0) {
            die("KERN_PROC_ALL size query failed");
        }
        if (needed == 0) {
            fprintf(stderr, "credential inventory error: KERN_PROC_ALL returned zero bytes\n");
            exit(70);
        }
        size_t capacity = needed + (32u * sizeof(struct kinfo_proc));
        struct kinfo_proc *entries = calloc(1, capacity);
        if (entries == NULL) {
            die("could not allocate KERN_PROC_ALL buffer");
        }
        size_t actual = capacity;
        if (sysctl(mib, 3, entries, &actual, NULL, 0) == 0) {
            if (actual == 0 || actual % sizeof(struct kinfo_proc) != 0) {
                free(entries);
                fprintf(stderr, "credential inventory error: KERN_PROC_ALL byte count is unclassifiable\n");
                exit(70);
            }
            *count_out = actual / sizeof(struct kinfo_proc);
            return entries;
        }
        int saved_errno = errno;
        free(entries);
        if (saved_errno != ENOMEM) {
            errno = saved_errno;
            die("KERN_PROC_ALL snapshot failed");
        }
    }
    fprintf(stderr, "credential inventory error: KERN_PROC_ALL did not converge after retries\n");
    exit(70);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s NUMERIC_ID\n", argv[0]);
        return 64;
    }
    char *end = NULL;
    errno = 0;
    unsigned long parsed = strtoul(argv[1], &end, 10);
    if (errno != 0 || end == argv[1] || *end != '\0' || parsed > UINT32_MAX) {
        fprintf(stderr, "invalid numeric principal: %s\n", argv[1]);
        return 64;
    }
    uint32_t candidate = (uint32_t)parsed;
    if (candidate == 0) {
        fprintf(stderr, "root numeric principal is never admissible\n");
        return 64;
    }

    size_t count = 0;
    struct kinfo_proc *entries = snapshot_processes(&count);
    for (size_t index = 0; index < count; ++index) {
        const struct kinfo_proc *entry = &entries[index];
        const struct _ucred *ucred = &entry->kp_eproc.e_ucred;
        pid_t pid = entry->kp_proc.p_pid;
        if (pid <= 0) {
            free(entries);
            fprintf(stderr, "credential inventory error: invalid pid in KERN_PROC_ALL\n");
            return 70;
        }
        if (ucred->cr_ngroups <= 0 || ucred->cr_ngroups > NGROUPS) {
            free(entries);
            fprintf(stderr, "credential inventory error: pid=%d has invalid group count=%d\n",
                    pid, (int)ucred->cr_ngroups);
            return 70;
        }
        printf("NEMBRA_KERN_PROC_PID=%d\n", pid);
        for (int group_index = 0; group_index < ucred->cr_ngroups; ++group_index) {
            if ((uint32_t)ucred->cr_groups[group_index] == candidate) {
                printf("NEMBRA_PROCESS_CREDENTIAL_MATCH=%d,%u\n", pid, GROUP_LIST_BIT);
                break;
            }
        }
    }
    free(entries);
    return 0;
}
'''


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def run(argv: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        **kwargs,
    )


def compile_group_scanner(directory: Path) -> Path:
    source = directory / "nembra_process_group_inventory.c"
    binary = directory / "nembra_process_group_inventory"
    source.write_text(C_SOURCE, encoding="utf-8")
    completed = run([
        "/usr/bin/clang",
        "-std=c11",
        "-O2",
        "-Wall",
        "-Wextra",
        "-Werror",
        str(source),
        "-o",
        str(binary),
    ])
    require(
        completed.returncode == 0,
        "could not compile Darwin process-group scanner: "
        + ((completed.stdout or "") + "\n" + (completed.stderr or ""))[-2000:],
    )
    return binary


def kernel_group_snapshot(binary: Path, candidate: int) -> tuple[set[int], dict[int, int]]:
    completed = run([str(binary), str(candidate)])
    require(
        completed.returncode == 0,
        f"KERN_PROC_ALL supplementary-group scan failed for {candidate}: "
        + ((completed.stdout or "") + "\n" + (completed.stderr or ""))[-2000:],
    )
    pids: set[int] = set()
    matches: dict[int, int] = {}
    for raw_line in completed.stdout.splitlines():
        if raw_line.startswith(KERN_PID_MARKER):
            pid = int(raw_line[len(KERN_PID_MARKER):], 10)
            require(pid > 0, f"kernel scanner emitted invalid pid: {raw_line!r}")
            require(pid not in pids, f"kernel scanner emitted duplicate pid: {pid}")
            pids.add(pid)
        elif raw_line.startswith(MATCH_MARKER):
            fields = raw_line[len(MATCH_MARKER):].split(",")
            require(len(fields) == 2, f"kernel scanner emitted malformed match: {raw_line!r}")
            pid = int(fields[0], 10)
            slots = int(fields[1], 10)
            require(pid > 0 and slots == GROUP_LIST, f"kernel scanner emitted invalid group match: {raw_line!r}")
            matches[pid] = matches.get(pid, 0) | slots
        elif raw_line.strip():
            raise ValidationError(f"kernel scanner emitted unknown stdout: {raw_line!r}")
    require(pids, "KERN_PROC_ALL scanner emitted no process IDs")
    require(set(matches).issubset(pids), "KERN_PROC_ALL match appeared without its PID record")
    return pids, matches


def ps_scalar_snapshot(candidate: int) -> tuple[set[int], dict[int, int]]:
    ps = Path("/bin/ps")
    require(ps.is_file(), "system /bin/ps is unavailable")
    completed = run([
        str(ps),
        "-A",
        "-o", "pid=",
        "-o", "uid=",
        "-o", "ruid=",
        "-o", "svuid=",
        "-o", "gid=",
        "-o", "rgid=",
        "-o", "svgid=",
    ], env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "LANG": "C"})
    require(
        completed.returncode == 0,
        "system ps credential snapshot failed: "
        + ((completed.stdout or "") + "\n" + (completed.stderr or ""))[-2000:],
    )
    pids: set[int] = set()
    matches: dict[int, int] = {}
    for raw_line in completed.stdout.splitlines():
        fields = raw_line.split()
        require(len(fields) == 7, f"ps emitted malformed credential row: {raw_line!r}")
        values = [int(field, 10) for field in fields]
        pid, euid, ruid, svuid, egid, rgid, svgid = values
        require(pid > 0, f"ps emitted invalid pid: {raw_line!r}")
        require(pid not in pids, f"ps emitted duplicate pid: {pid}")
        pids.add(pid)
        slots = 0
        if ruid == candidate:
            slots |= RUID
        if euid == candidate:
            slots |= EUID
        if svuid == candidate:
            slots |= SVUID
        if rgid == candidate:
            slots |= RGID
        if egid == candidate:
            slots |= EGID
        if svgid == candidate:
            slots |= SVGID
        if slots:
            matches[pid] = slots
    require(pids, "system ps emitted no process IDs")
    return pids, matches


def pid_still_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError as error:
        if error.errno == errno.ESRCH:
            return False
        if error.errno == errno.EPERM:
            return True
        raise ValidationError(f"kill(0) process-existence probe failed pid={pid} errno={error.errno}") from error
    return True


def scan(binary: Path, candidate: int) -> tuple[int, dict[int, int]]:
    witness_pid = os.getpid()
    for attempt in range(8):
        kernel_pids, group_matches = kernel_group_snapshot(binary, candidate)
        ps_pids, scalar_matches = ps_scalar_snapshot(candidate)

        persistent_kernel_only = sorted(pid for pid in kernel_pids - ps_pids if pid_still_exists(pid))
        persistent_ps_only = sorted(pid for pid in ps_pids - kernel_pids if pid_still_exists(pid))
        if persistent_kernel_only or persistent_ps_only:
            if attempt == 7:
                raise ValidationError(
                    "KERN_PROC_ALL/ps PID sets did not converge for still-live processes: "
                    f"kernel_only={persistent_kernel_only[:24]} ps_only={persistent_ps_only[:24]}"
                )
            continue

        require(witness_pid in kernel_pids, "witness PID was absent from KERN_PROC_ALL snapshot")
        require(witness_pid in ps_pids, "witness PID was absent from ps credential snapshot")

        matches = dict(group_matches)
        for pid, slots in scalar_matches.items():
            matches[pid] = matches.get(pid, 0) | slots
        return witness_pid, matches
    raise ValidationError("KERN_PROC_ALL/ps credential snapshots did not converge")


def require_self_slots(binary: Path, candidate: int, required_slots: int, label: str) -> None:
    self_pid, matches = scan(binary, candidate)
    observed = matches.get(self_pid, 0)
    require(
        observed & required_slots == required_slots,
        f"scanner did not observe {label} on its own kernel credential: "
        f"candidate={candidate} required={required_slots} observed={observed} matches={matches}",
    )


def identity_record_free(candidate: int) -> bool:
    try:
        pwd.getpwuid(candidate)
        return False
    except KeyError:
        pass
    try:
        grp.getgrgid(candidate)
        return False
    except KeyError:
        pass
    return True


def choose_process_free_candidate(binary: Path) -> int:
    for candidate in range(52_000, 62_000):
        if candidate <= 0 or not identity_record_free(candidate):
            continue
        _, matches = scan(binary, candidate)
        if not matches:
            return candidate
    raise ValidationError("could not find one process-credential-free numeric principal")


def main() -> int:
    require(sys.platform == "darwin", "Darwin process-credential witness must run on macOS")
    require(Path("/usr/bin/clang").is_file(), "Darwin clang is unavailable")

    uid = os.getuid()
    gid = os.getgid()
    require(uid > 0 and gid > 0, "validation must run as one ordinary non-root account")

    advisory_groups = sorted({int(value) for value in os.getgroups() if int(value) > 0})
    supplementary_only = [value for value in advisory_groups if value not in {uid, gid}]
    require(
        supplementary_only,
        "runner has no supplementary-only group with which to prove group-list collision detection",
    )
    supplementary = supplementary_only[0]

    with tempfile.TemporaryDirectory(prefix="nembra-process-credential-inventory.") as raw_dir:
        directory = Path(raw_dir)
        binary = compile_group_scanner(directory)

        require_self_slots(binary, uid, RUID | EUID | SVUID, "real/effective/saved UID")
        require_self_slots(binary, gid, RGID | EGID | SVGID | GROUP_LIST, "real/effective/saved primary GID")

        self_pid, supplementary_matches = scan(binary, supplementary)
        observed = supplementary_matches.get(self_pid, 0)
        require(observed & GROUP_LIST, "scanner missed its own supplementary-group credential")
        require(
            observed & (RUID | EUID | SVUID | RGID | EGID | SVGID) == 0,
            "supplementary-group witness is not isolated from primary UID/GID slots",
        )

        free_candidate = choose_process_free_candidate(binary)
        _, free_matches = scan(binary, free_candidate)
        require(not free_matches, "chosen process-free numeric principal became occupied before evidence freeze")

        payload = {
            "schema": 3,
            "uidSlotsObserved": True,
            "primaryGIDSlotsObserved": True,
            "supplementaryGroupOnlyCollisionObserved": True,
            "supplementaryCollisionCandidate": supplementary,
            "processFreeCandidateObserved": free_candidate,
            "processFreeCandidateMatchCount": len(free_matches),
            "usedKernProcAllKinfoProc": True,
            "usedSystemPSCredentialScalars": True,
            "usedProcPidTBSDInfo": False,
            "persistentPIDSetsReconciled": True,
            "vanishedPIDsAreOnlySkippableAfterESRCH": True,
            "directoryServicesMutated": False,
            "sudoUsed": False,
            "physicalAuthorityCreated": False,
        }
        print(MARKER + json.dumps(payload, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValidationError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
