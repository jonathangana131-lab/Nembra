#!/usr/bin/env python3
"""Validation-only Darwin process-credential inventory for numeric UID/GID reuse.

This witness is intentionally read-only. It takes a KERN_PROC_ALL / struct
kinfo_proc snapshot for PID + advisory-group inventory and combines it with
proc_pidinfo(PROC_PIDTBSDINFO) for each still-live process's effective/real/saved
UID and GID slots. It creates no Directory Services records, uses no sudo, and
changes no process identity.
"""
from __future__ import annotations

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
SELF_MARKER = "NEMBRA_PROCESS_CREDENTIAL_SELF_PID="

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
#include <libproc.h>
#include <errno.h>
#include <inttypes.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define RUID_BIT (1u << 0)
#define EUID_BIT (1u << 1)
#define SVUID_BIT (1u << 2)
#define RGID_BIT (1u << 3)
#define EGID_BIT (1u << 4)
#define SVGID_BIT (1u << 5)
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

/*
 * Return 1 with a complete current BSD credential scalar record, or 0 only
 * when the PID from the KERN_PROC_ALL snapshot has demonstrably exited.
 * Any still-existing PID whose BSD record cannot be classified is fatal.
 */
static int current_bsd_info(pid_t pid, struct proc_bsdinfo *info_out) {
    memset(info_out, 0, sizeof(*info_out));
    errno = 0;
    int bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, info_out, (int)sizeof(*info_out));
    if (bytes == (int)sizeof(*info_out)) {
        if ((pid_t)info_out->pbi_pid != pid) {
            fprintf(stderr, "credential inventory error: proc_pidinfo PID mismatch expected=%d observed=%u\n",
                    pid, info_out->pbi_pid);
            exit(70);
        }
        return 1;
    }
    if (bytes != 0) {
        fprintf(stderr, "credential inventory error: proc_pidinfo partial record pid=%d bytes=%d expected=%zu\n",
                pid, bytes, sizeof(*info_out));
        exit(70);
    }

    int info_errno = errno;
    errno = 0;
    if (kill(pid, 0) == -1 && errno == ESRCH) {
        return 0;
    }
    int probe_errno = errno;
    fprintf(stderr,
            "credential inventory error: live pid=%d has unclassifiable PROC_PIDTBSDINFO errno=%d probe_errno=%d\n",
            pid, info_errno, probe_errno);
    exit(70);
}

static int match_slots(const struct kinfo_proc *entry, uint32_t candidate, unsigned int *slots_out) {
    const struct _ucred *ucred = &entry->kp_eproc.e_ucred;
    pid_t pid = entry->kp_proc.p_pid;
    if (ucred->cr_ngroups <= 0 || ucred->cr_ngroups > NGROUPS) {
        fprintf(stderr, "credential inventory error: pid=%d has invalid group count=%d\n",
                pid, (int)ucred->cr_ngroups);
        exit(70);
    }

    struct proc_bsdinfo bsd;
    if (!current_bsd_info(pid, &bsd)) {
        return 0;
    }

    unsigned int slots = 0;
    if ((uint32_t)bsd.pbi_ruid == candidate) slots |= RUID_BIT;
    if ((uint32_t)bsd.pbi_uid == candidate) slots |= EUID_BIT;
    if ((uint32_t)bsd.pbi_svuid == candidate) slots |= SVUID_BIT;
    if ((uint32_t)bsd.pbi_rgid == candidate) slots |= RGID_BIT;
    if ((uint32_t)bsd.pbi_gid == candidate) slots |= EGID_BIT;
    if ((uint32_t)bsd.pbi_svgid == candidate) slots |= SVGID_BIT;
    for (int index = 0; index < ucred->cr_ngroups; ++index) {
        if ((uint32_t)ucred->cr_groups[index] == candidate) {
            slots |= GROUP_LIST_BIT;
            break;
        }
    }
    *slots_out = slots;
    return 1;
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
    printf("NEMBRA_PROCESS_CREDENTIAL_SELF_PID=%d\n", getpid());
    for (size_t index = 0; index < count; ++index) {
        const struct kinfo_proc *entry = &entries[index];
        if (entry->kp_proc.p_pid <= 0) {
            free(entries);
            fprintf(stderr, "credential inventory error: invalid pid in KERN_PROC_ALL\n");
            return 70;
        }
        unsigned int slots = 0;
        if (!match_slots(entry, candidate, &slots)) {
            continue;
        }
        if (slots != 0) {
            printf("NEMBRA_PROCESS_CREDENTIAL_MATCH=%d,%u\n", entry->kp_proc.p_pid, slots);
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


def compile_scanner(directory: Path) -> Path:
    source = directory / "nembra_process_credential_inventory.c"
    binary = directory / "nembra_process_credential_inventory"
    source.write_text(C_SOURCE, encoding="utf-8")
    completed = run([
        "/usr/bin/clang",
        "-std=c11",
        "-O2",
        "-Wall",
        "-Wextra",
        "-Werror",
        str(source),
        "-lproc",
        "-o",
        str(binary),
    ])
    require(
        completed.returncode == 0,
        "could not compile Darwin process-credential scanner: "
        + ((completed.stdout or "") + "\n" + (completed.stderr or ""))[-2000:],
    )
    return binary


def scan(binary: Path, candidate: int) -> tuple[int, dict[int, int]]:
    completed = run([str(binary), str(candidate)])
    require(
        completed.returncode == 0,
        f"process-credential scan failed for {candidate}: "
        + ((completed.stdout or "") + "\n" + (completed.stderr or ""))[-2000:],
    )
    self_pid: int | None = None
    matches: dict[int, int] = {}
    for raw_line in completed.stdout.splitlines():
        if raw_line.startswith(SELF_MARKER):
            require(self_pid is None, "scanner emitted duplicate self PID")
            self_pid = int(raw_line[len(SELF_MARKER):], 10)
        elif raw_line.startswith(MATCH_MARKER):
            fields = raw_line[len(MATCH_MARKER):].split(",")
            require(len(fields) == 2, f"scanner emitted malformed match line: {raw_line!r}")
            pid = int(fields[0], 10)
            slots = int(fields[1], 10)
            require(pid > 0 and slots > 0, f"scanner emitted invalid match line: {raw_line!r}")
            matches[pid] = matches.get(pid, 0) | slots
        elif raw_line.strip():
            raise ValidationError(f"scanner emitted unknown stdout: {raw_line!r}")
    require(self_pid is not None and self_pid > 0, "scanner emitted no self PID")
    return self_pid, matches


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
        binary = compile_scanner(directory)

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
            "schema": 2,
            "uidSlotsObserved": True,
            "primaryGIDSlotsObserved": True,
            "supplementaryGroupOnlyCollisionObserved": True,
            "supplementaryCollisionCandidate": supplementary,
            "processFreeCandidateObserved": free_candidate,
            "processFreeCandidateMatchCount": len(free_matches),
            "usedKernProcAllKinfoProc": True,
            "usedProcPidTBSDInfo": True,
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
