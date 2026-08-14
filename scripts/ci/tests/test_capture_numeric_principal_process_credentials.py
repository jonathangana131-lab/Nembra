#!/usr/bin/env python3
"""Validation-only Darwin process-credential inventory for numeric UID/GID reuse.

This witness is intentionally read-only. It compiles a tiny C scanner against the
runner's own SDK headers and uses KERN_PROC_ALL / struct kinfo_proc to inspect every
process's real/effective/saved UID and GID plus its advisory/supplementary group list.
It creates no Directory Services records, uses no sudo, and changes no process identity.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import pwd
import grp
import subprocess
import sys
import tempfile


class ValidationError(RuntimeError):
    pass


MARKER = "NEMBRA_NUMERIC_PROCESS_CREDENTIAL_JSON="
MATCH_MARKER = "NEMBRA_PROCESS_CREDENTIAL_MATCH="
SELF_MARKER = "NEMBRA_PROCESS_CREDENTIAL_SELF_PID="

# Bit positions emitted by the C scanner. A candidate is occupied if any bit is set.
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

static unsigned int match_slots(const struct kinfo_proc *entry, uint32_t candidate) {
    const struct _pcred *pcred = &entry->kp_eproc.e_pcred;
    const struct _ucred *ucred = &entry->kp_eproc.e_ucred;
    if (ucred->cr_ngroups <= 0 || ucred->cr_ngroups > NGROUPS) {
        fprintf(stderr, "credential inventory error: pid=%d has invalid group count=%d\n",
                entry->kp_proc.p_pid, (int)ucred->cr_ngroups);
        exit(70);
    }

    unsigned int slots = 0;
    if ((uint32_t)pcred->p_ruid == candidate) slots |= RUID_BIT;
    if ((uint32_t)ucred->cr_uid == candidate) slots |= EUID_BIT;
    if ((uint32_t)pcred->p_svuid == candidate) slots |= SVUID_BIT;
    if ((uint32_t)pcred->p_rgid == candidate) slots |= RGID_BIT;
    if ((uint32_t)ucred->cr_groups[0] == candidate) slots |= EGID_BIT;
    if ((uint32_t)pcred->p_svgid == candidate) slots |= SVGID_BIT;
    for (int index = 0; index < ucred->cr_ngroups; ++index) {
        if ((uint32_t)ucred->cr_groups[index] == candidate) {
            slots |= GROUP_LIST_BIT;
            break;
        }
    }
    return slots;
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
        unsigned int slots = match_slots(entry, candidate);
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
        "-o",
        str(binary),
    ])
    require(
        completed.returncode == 0,
        "could not compile Darwin process-credential scanner: "
        + ((completed.stdout or "") + "\n" + (completed.stderr or ""))[-1600:],
    )
    return binary


def scan(binary: Path, candidate: int) -> tuple[int, dict[int, int]]:
    completed = run([str(binary), str(candidate)])
    require(
        completed.returncode == 0,
        f"process-credential scan failed for {candidate}: "
        + ((completed.stdout or "") + "\n" + (completed.stderr or ""))[-1600:],
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

        # A normal process should carry its account's real/effective/saved UID slots.
        require_self_slots(binary, uid, RUID | EUID | SVUID, "real/effective/saved UID")

        # Its primary group should be visible as real/effective/saved GID and in the advisory list.
        require_self_slots(binary, gid, RGID | EGID | SVGID | GROUP_LIST, "real/effective/saved primary GID")

        # This is the key negative witness: candidate != UID/GID but is already in a live
        # process's supplementary/advisory group list, so numeric GID reuse must be rejected.
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
            "schema": 1,
            "uidSlotsObserved": True,
            "primaryGIDSlotsObserved": True,
            "supplementaryGroupOnlyCollisionObserved": True,
            "supplementaryCollisionCandidate": supplementary,
            "processFreeCandidateObserved": free_candidate,
            "processFreeCandidateMatchCount": len(free_matches),
            "usedKernProcAllKinfoProc": True,
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
