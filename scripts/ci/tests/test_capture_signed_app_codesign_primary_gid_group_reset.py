#!/usr/bin/env python3
"""Exact successor for #3137's ambient supplementary-group leak.

The base codesign/APFS oracle intentionally records a logical zero-distinct-extra-groups
signer. Real xcode-27 evidence on 9bcb882f showed that Python 3.9/macOS can preserve the
parent's ambient supplementary vector when subprocess is asked for `extra_groups=[]`.
That is not acceptable authority isolation.

This validation-only adapter changes only credential launch mechanics:
- ordinary field negatives retain their exact pre-sudo supplementary vector;
- a launch that requests zero distinct supplementary authority supplies the already-
  primary GID once in the raw `extra_groups` vector, forcing a real setgroups transition;
- the child path-attestation retains the raw kernel `os.getgroups()` vector and separately
  normalizes it by removing only the already-primary GID;
- acceptance still requires zero *distinct* supplementary GIDs before codesign.

The duplicate-primary sentinel adds no GID authority beyond the primary credential. It is
only acceptable if the real child reports no other supplementary GID. This does not create
Apple identity, provisioning, install, device, Bluetooth, Tuya, telemetry, or physical
authority.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
from typing import Iterable

HERE = Path(__file__).resolve().parent
PARENT_PATH = HERE / "test_capture_signed_app_codesign_capability_freeze.py"


def load_parent():
    spec = importlib.util.spec_from_file_location(
        "nembra_codesign_capability_primary_gid_reset_parent",
        PARENT_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load exact codesign capability parent oracle")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def install_group_reset_adapter(parent) -> None:
    original_credentials = parent.structured_credentials
    original_path_probe = parent.probe_signer_path_authority

    def reset_credentials(uid: int, gid: int, groups: Iterable[int]) -> dict[str, object]:
        requested = sorted({int(group) for group in groups if int(group) != gid})
        if requested:
            return original_credentials(uid, gid, requested)
        if uid <= 0 or gid <= 0:
            raise parent.ProbeError("group-reset credentials require non-root UID/GID")
        # Python/macOS kept ambient groups for an empty raw vector on the exact predecessor.
        # A non-empty vector forces the setgroups path; repeating the primary GID does not add
        # a distinct GID authority and is checked against the child's real os.getgroups().
        return {"user": uid, "group": gid, "extra_groups": [gid]}

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
        evidence = dict(evidence)
        evidence["rawEffectiveSupplementaryGroups"] = list(raw)
        evidence["effectiveSupplementaryGroups"] = sorted(
            {group for group in raw if group != signer_gid}
        )
        evidence["primaryGIDResetSentinelPresent"] = signer_gid in raw
        return evidence

    parent.structured_credentials = reset_credentials
    parent.probe_signer_path_authority = attested_path_probe


def main() -> int:
    parent = load_parent()
    install_group_reset_adapter(parent)
    return parent.main()


if __name__ == "__main__":
    raise SystemExit(main())
