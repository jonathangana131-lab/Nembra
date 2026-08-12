#!/usr/bin/env python3
"""Exact successor for #3137's field-UID supplementary-group semantics.

Real xcode-27 evidence falsified two stronger assumptions while preserving the useful
path-authority result:
- `extra_groups=[]` did not make the field UID group-empty;
- even a duplicate-primary non-empty reset sentinel did not replace the field UID's
  macOS group vector.

That is the wrong property to chase for a signing bridge whose purpose is to preserve the
real field UID. This validation-only adapter now requires the threat-relevant invariant:
- ordinary field negatives retain the exact pre-sudo field UID/primary/supplementary set;
- the signer keeps that same field UID and receives only the fresh capability as primary GID;
- the signer child's actual kernel `os.getgroups()` must normalize exactly to the captured
  pre-sudo field baseline (field primary GID + active supplementary GIDs), with no extra or
  missing baseline group;
- the fresh capability must remain absent from the field account's ordinary authority;
- raw child groups are retained in evidence instead of being inferred from constructor args.

The imported parent's self-path is rebound to this wrapper so its sudo transition executes
the same adapter. A green result remains architecture evidence only: it does not prove an
Apple Development identity, provisioning, install, device, Bluetooth, Tuya, telemetry, or
physical authority.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import pwd
from typing import Iterable

HERE = Path(__file__).resolve().parent
PARENT_PATH = HERE / "test_capture_signed_app_codesign_capability_freeze.py"


def load_parent():
    spec = importlib.util.spec_from_file_location(
        "nembra_codesign_capability_field_baseline_parent",
        PARENT_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load exact codesign capability parent oracle")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def install_field_baseline_adapter(parent) -> None:
    original_credentials = parent.structured_credentials
    original_path_probe = parent.probe_signer_path_authority
    original_root_probe = parent.root_probe
    captured: dict[str, list[int]] = {}

    def baseline_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
        requested = sorted({int(group) for group in groups if int(group) != gid})
        return original_credentials(uid, gid, requested)

    def root_probe_with_baseline(field_active_groups: list[int]) -> int:
        captured["fieldActiveSupplementaryGroups"] = list(field_active_groups)
        return original_root_probe(field_active_groups)

    def attested_path_probe(
        app: Path,
        *,
        environment: dict[str, str],
        field_uid: int,
        signer_gid: int,
        signer_groups: list[int],
    ) -> dict[str, object]:
        evidence = original_path_probe(
            app,
            environment=environment,
            field_uid=field_uid,
            signer_gid=signer_gid,
            signer_groups=signer_groups,
        )
        raw = evidence.get("effectiveSupplementaryGroups")
        if not isinstance(raw, list) or any(not isinstance(group, int) for group in raw):
            raise parent.ProbeError("signer path probe did not expose one integer kernel group vector")
        active = captured.get("fieldActiveSupplementaryGroups")
        if active is None:
            raise parent.ProbeError("signer path probe ran without captured pre-sudo field groups")
        field_primary_gid = pwd.getpwuid(field_uid).pw_gid
        if field_primary_gid <= 0:
            raise parent.ProbeError("field account exposes invalid primary GID during signer attestation")
        baseline = sorted(set([field_primary_gid, *active]))
        # A duplicate of the already-primary fresh signer GID would add no distinct authority.
        normalized = sorted({group for group in raw if group != signer_gid})
        unexpected = sorted(set(normalized).difference(baseline))
        missing = sorted(set(baseline).difference(normalized))
        if unexpected or missing:
            raise parent.ProbeError(
                "signer kernel groups diverged from exact pre-sudo field baseline: "
                f"unexpected={unexpected} missing={missing} raw={raw} baseline={baseline}"
            )
        evidence = dict(evidence)
        evidence["rawEffectiveSupplementaryGroups"] = list(raw)
        evidence["capturedFieldBaselineGroups"] = baseline
        evidence["unexpectedSupplementaryGroupsBeyondFieldBaseline"] = unexpected
        evidence["missingFieldBaselineGroups"] = missing
        evidence["fieldBaselinePreservedExact"] = True
        # Parent semantic acceptance models signer_groups as *new distinct supplementary
        # authority*. Raw groups remain above; zero here means nothing beyond field baseline.
        evidence["effectiveSupplementaryGroups"] = []
        return evidence

    parent.structured_credentials = baseline_credentials
    parent.root_probe = root_probe_with_baseline
    parent.probe_signer_path_authority = attested_path_probe


def main() -> int:
    parent = load_parent()
    # Parent parent_probe re-enters itself through sudo using Path(__file__). Rebind that
    # module-global path before invoking it so the privileged phase also loads this wrapper.
    parent.__file__ = str(Path(__file__).resolve())
    install_field_baseline_adapter(parent)
    return parent.main()


if __name__ == "__main__":
    raise SystemExit(main())
