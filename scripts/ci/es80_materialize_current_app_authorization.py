#!/usr/bin/env python3
"""Materialize the reviewed Capture authorization lifecycle under the current source contract.

The historical one-shot remains the source of the large, already-reviewed lifecycle insertion. This
helper deliberately performs only the small successor rewrite required after Nembra replaced the
caller-constructible `isAuthoritativeFieldBuild` bootstrap with the signed one-shot app session.
It never makes that legacy boolean true and never publishes or authorizes a physical attempt.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import textwrap

APP_RELATIVE = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
ONE_SHOT_RELATIVE = Path(".github/workflows/capture-app-authorization-close-one-shot.yml")


class MaterializationError(RuntimeError):
    pass


def _replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise MaterializationError(f"{label}: expected one anchor, found {count}")
    return source.replace(old, new, 1)


def _run_reviewed_one_shot(root: Path) -> None:
    workflow = (root / ONE_SHOT_RELATIVE).read_text(encoding="utf-8")
    section = workflow.index("      - name: Materialize field authorization into real SecureLink lifecycle")
    run_marker = "        run: |\n"
    start = workflow.index(run_marker, section) + len(run_marker)
    end = workflow.index("\n      - name: Enforce truth-preserving source shape", start)
    script = textwrap.dedent(workflow[start:end])

    previous = Path.cwd()
    try:
        os.chdir(root)
        exec(compile(script, "capture-app-authorization-reviewed-materializer", "exec"), {"__name__": "__main__"})
    finally:
        os.chdir(previous)


def _repair_current_contract(source: str) -> str:
    source = _replace_once(
        source,
        "guard phase == .idle, buildIdentity.isAuthoritativeFieldBuild else { return }",
        "guard phase == .idle, buildIdentity.hasCompleteFieldBuildMetadata else { return }",
        "non-authorizing handoff bootstrap",
    )

    source = _replace_once(
        source,
        "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n"
        "    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n",
        "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n"
        "    var fieldBuildMetadataComplete: Bool { buildIdentity.hasCompleteFieldBuildMetadata }\n"
        "    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n",
        "build metadata presentation seam",
    )

    source = _replace_once(
        source,
        "        guard buildIdentity.isAuthoritativeFieldBuild else {\n"
        "            failLocally(buildIdentity.blocker ?? \"Exact field-build provenance is unavailable.\", \"field_build_identity_unavailable\")\n"
        "            return\n"
        "        }\n"
        "        guard privateConfig, sdkAccountLoggedIn else {",
        "        guard privateConfig, sdkAccountLoggedIn else {",
        "OFF1 legacy build-authority gate",
    )

    source = _replace_once(
        source,
        "        guard buildIdentity.isAuthoritativeFieldBuild else {\n"
        "            failLocally(buildIdentity.blocker ?? \"Exact field-build provenance is unavailable.\", \"field_build_identity_unavailable\")\n"
        "            return\n"
        "        }\n"
        "        guard !deviceID.isEmpty, !tuyaUUID.isEmpty, !productID.isEmpty else {",
        "        guard !deviceID.isEmpty, !tuyaUUID.isEmpty, !productID.isEmpty else {",
        "authentication legacy build-authority gate",
    )

    source = _replace_once(
        source,
        "              candidate.likely,\n"
        "              buildIdentity.isAuthoritativeFieldBuild,\n"
        "              sdkDeviceMembershipVerified,",
        "              candidate.likely,\n"
        "              sdkDeviceMembershipVerified,",
        "official-connection legacy build-authority gate",
    )

    source = _replace_once(
        source,
        '                    requirementRow("Capture build", ready: test.fieldBuildIsAuthoritative)\n',
        '                    requirementRow("Capture build", ready: test.fieldBuildMetadataComplete)\n',
        "preflight build-metadata row",
    )
    source = _replace_once(
        source,
        "                if test.fieldBuildIsAuthoritative && !test.fieldAuthorizationReady {\n",
        "                if test.fieldBuildMetadataComplete && !test.fieldAuthorizationReady {\n",
        "preflight handoff status visibility",
    )
    source = _replace_once(
        source,
        "            if !test.fieldBuildIsAuthoritative || !test.privateConfig {\n",
        "            if !test.fieldBuildMetadataComplete || !test.privateConfig {\n",
        "failed-state metadata routing",
    )
    source = _replace_once(
        source,
        "        test.fieldBuildIsAuthoritative\n"
        "            && test.fieldAuthorizationReady\n",
        "        test.fieldBuildMetadataComplete\n"
        "            && test.fieldAuthorizationReady\n",
        "preflight signed-session readiness",
    )

    panel_start = source.index("    private var secureObservationPanel: some View")
    panel_end = source.index("    private var failureRecoveryContextPanel: some View", panel_start)
    panel = source[panel_start:panel_end]
    panel = _replace_once(
        panel,
        "                    .disabled(!authorityReady || test.membershipBusy)\n",
        "                    .disabled(test.membershipBusy)\n",
        "post-OFF1 authentication action",
    )
    source = source[:panel_start] + panel + source[panel_end:]
    return source


def materialize(root: Path) -> Path:
    root = root.resolve()
    app = root / APP_RELATIVE
    one_shot = root / ONE_SHOT_RELATIVE
    if not app.is_file() or not one_shot.is_file():
        raise MaterializationError("required Capture app/one-shot source is unavailable")

    before = app.read_text(encoding="utf-8")
    if "NembraCaptureFieldAuthorizationController" in before:
        raise MaterializationError("app already contains field-authorization lifecycle wiring")

    _run_reviewed_one_shot(root)
    generated = app.read_text(encoding="utf-8")
    repaired = _repair_current_contract(generated)
    if repaired == generated:
        raise MaterializationError("current-contract repair produced no change")
    if "isAuthoritativeFieldBuild = true" in repaired:
        raise MaterializationError("materializer must never create legacy field-build authority")
    app.write_text(repaired, encoding="utf-8")
    return app


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    materialize(args.repository_root)
    print("MATERIALIZED_CURRENT_APP_AUTHORIZATION_NOT_PHYSICAL_GO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
