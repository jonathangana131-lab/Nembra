#!/usr/bin/env python3
"""Fail-closed contract for Darwin KERN_PROC PID-0 credential authority."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile


class ContractError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def main() -> int:
    witness_path = Path(__file__).with_name("test_capture_numeric_principal_process_credentials.py").resolve()
    source = witness_path.read_text(encoding="utf-8")

    # Source policy: PID 0 remains an admitted KERN_PROC credential subject, but it
    # never enters the ordinary ps/kill liveness reconciliation where kill(0, 0)
    # has process-group semantics. Candidate matches, including PID 0, remain in
    # the same `matches` map used to reject occupied numeric principals.
    required_source = (
        "if (pid < 0) {",
        "require(pid >= 0, f\"kernel scanner emitted invalid pid: {raw_line!r}\")",
        "require(pid >= 0 and slots == GROUP_LIST",
        "matches[pid] = matches.get(pid, 0) | slots",
        "pid > 0 and pid_still_exists(pid)",
        "if not matches:",
    )
    missing = [fragment for fragment in required_source if fragment not in source]
    require(not missing, f"PID-0 fail-closed source invariant missing: {missing!r}")

    spec = importlib.util.spec_from_file_location("nembra_numeric_principal_witness", witness_path)
    require(spec is not None and spec.loader is not None, "could not load numeric-principal witness")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    # Exact current-Darwin ABI requirement: KERN_PROC_ALL must expose exactly one
    # PID-0 kernel entry. `kernel_group_snapshot` rejects duplicate PID records,
    # so membership here means exactly one was observed. If Darwin changes this
    # ABI later, the witness must be deliberately reclassified instead of silently
    # falling back to an unproven special-case policy.
    with tempfile.TemporaryDirectory(prefix="nembra-numeric-pid0-contract.") as raw:
        binary = module.compile_group_scanner(Path(raw))
        kernel_pids, _matches = module.kernel_group_snapshot(binary, os.getgid())
    require(0 in kernel_pids, "current KERN_PROC_ALL omitted the required kernel PID-0 entry")

    print("NEMBRA_NUMERIC_PID0_CONTRACT_ACCEPTED kernelPIDZeroObserved=true physicalAuthorityCreated=false")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ContractError as error:
        print(f"ERROR: {error}")
        raise SystemExit(1)
