#!/usr/bin/env python3
"""Make the verified one-time app session the field authority after lifecycle materialization.

Self-described build metadata remains a mandatory exact-runtime prerequisite. It is deliberately not
physical authority. The package verifier-owned session must be armed before OFF1, remains live through
observation, and seals only after exact accepted artifact bytes are frozen.
"""

from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")


def replace_exact(source: str, old: str, new: str, label: str, expected: int = 1) -> str:
    count = source.count(old)
    if count != expected:
        raise SystemExit(f"{label}: expected {expected} anchor(s), found {count}")
    return source.replace(old, new)


def main() -> None:
    source = APP.read_text(encoding="utf-8")
    required = (
        "import NembraCaptureAppAuthorization",
        "NembraCaptureFieldAuthorizationController()",
        "advanceInboxHandoffIfAvailable()",
        "admitOFF1Start()",
        "admitAuthenticationStart()",
        "admitOfficialConnectionStart()",
        "admitObservationStart()",
        "freezeAcceptedArtifactForAuthorizationSeal()",
        "sealAfterAcceptedArtifactFreeze()",
    )
    for token in required:
        if token not in source:
            raise SystemExit(f"authorization lifecycle must be materialized first: missing {token}")

    legacy_name_count = source.count("fieldBuildIsAuthoritative")
    if legacy_name_count < 8:
        raise SystemExit(
            f"legacy build-authority presentation seam unexpectedly sparse: {legacy_name_count}"
        )
    source = source.replace("fieldBuildIsAuthoritative", "fieldBuildMetadataReady")

    legacy_predicate_count = source.count("buildIdentity.isAuthoritativeFieldBuild")
    if legacy_predicate_count < 5:
        raise SystemExit(
            f"legacy hard-false runtime predicate unexpectedly sparse: {legacy_predicate_count}"
        )
    source = source.replace(
        "buildIdentity.isAuthoritativeFieldBuild",
        "buildIdentity.hasCompleteFieldBuildMetadata",
    )

    # At the two canonical acceptance re-checks, metadata is necessary but the live independent
    # session must also still own observation authority. A stale/revoked session cannot ride on a
    # valid plist tuple into an accepted artifact.
    source = replace_exact(
        source,
        "guard self.buildIdentity.hasCompleteFieldBuildMetadata else {\n                        await self.invalidateSourceAuthority(",
        "guard self.buildIdentity.hasCompleteFieldBuildMetadata,\n                          self.fieldAuthorization.stage == .observationAdmitted else {\n                        await self.invalidateSourceAuthority(",
        "pre-seal live session authority",
    )
    source = replace_exact(
        source,
        "guard self.buildIdentity.hasCompleteFieldBuildMetadata,\n                              self.accountIdentityLeaseIsAuthorized else {",
        "guard self.buildIdentity.hasCompleteFieldBuildMetadata,\n                              self.fieldAuthorization.stage == .observationAdmitted,\n                              self.accountIdentityLeaseIsAuthorized else {",
        "final acceptance live session authority",
    )

    copy_replacements = (
        (
            'Text(fieldBuildMetadataReady ? "Field build ready" : "Capture locked")',
            'Text(fieldBuildMetadataReady ? "Build metadata ready" : "Capture locked")',
            "root build title",
        ),
        (
            '? "Account and scooter checks are still required before Bluetooth can start."',
            '? "Account, scooter, and one-time field authorization checks are still required before Bluetooth can start."',
            "root ready explanation",
        ),
        (
            ': "Bluetooth stays locked until the reviewed field build is installed.")',
            ': "Bluetooth stays locked until exact build metadata is complete and one-time field authorization is verified.")',
            "root locked explanation",
        ),
        (
            '.accessibilityLabel(fieldBuildMetadataReady ? "Field build ready" : "Physical capture locked")',
            '.accessibilityLabel(fieldBuildMetadataReady ? "Build metadata ready" : "Physical capture locked")',
            "root accessibility label",
        ),
        (
            '? "Account and scooter checks are still required before Bluetooth starts."',
            '? "Account, scooter, and one-time field authorization checks are still required before Bluetooth starts."',
            "root accessibility value",
        ),
        (
            'test.fieldBuildMetadataReady ? "Field build" : "Build blocked"',
            'test.fieldBuildMetadataReady ? "Build metadata" : "Build metadata missing"',
            "SecureLink hero build label",
        ),
        (
            'requirementRow("Capture build", ready: test.fieldBuildMetadataReady)',
            'requirementRow("Capture build metadata", ready: test.fieldBuildMetadataReady)',
            "preflight metadata label",
        ),
    )
    for old, new, label in copy_replacements:
        source = replace_exact(source, old, new, label)

    if "fieldBuildIsAuthoritative" in source:
        raise SystemExit("legacy fieldBuildIsAuthoritative presentation name survived migration")
    if "buildIdentity.isAuthoritativeFieldBuild" in source:
        raise SystemExit("legacy hard-false build authority still participates in app runtime")

    authority_start = source.index("private var authorityReady: Bool")
    authority_end = source.index("private var currentStageIndex: Int", authority_start)
    authority = source[authority_start:authority_end]
    for token in (
        "test.fieldBuildMetadataReady",
        "test.fieldAuthorizationReady",
        "test.privateConfig",
        "test.sdkAccountLoggedIn",
        "test.sdkDeviceMembershipVerified",
        "test.accountIdentityLeaseIsAuthorized",
    ):
        if token not in authority:
            raise SystemExit(f"authorityReady lost required gate: {token}")

    handoff_start = source.index("func advanceFieldAuthorizationHandoffIfAvailable()")
    handoff_end = source.index("func activateMembershipRequestsForView()", handoff_start)
    handoff = source[handoff_start:handoff_end]
    if "guard phase == .idle, buildIdentity.hasCompleteFieldBuildMetadata else { return }" not in handoff:
        raise SystemExit("non-authorizing handoff is not reachable from complete runtime metadata")

    baseline_start = source.index("private func beginBaselineAfterCurrentOperatorAttestation()")
    baseline_end = source.index("private func beginCorrelationSeries()", baseline_start)
    baseline = source[baseline_start:baseline_end]
    if baseline.index("buildIdentity.hasCompleteFieldBuildMetadata") > baseline.index("admitOFF1Start()"):
        raise SystemExit("OFF1 authorization admission must remain downstream of metadata validation")
    if baseline.index("admitOFF1Start()") > baseline.index("beginCorrelationSeries()"):
        raise SystemExit("OFF1 authorization admission must precede Bluetooth correlation")

    connection_start = source.index("private func beginOfficialConnection(candidate: Candidate)")
    connection_end = source.index("private func authenticated(token: TuyaReadOnlyConnectionToken)", connection_start)
    connection = source[connection_start:connection_end]
    if connection.index("buildIdentity.hasCompleteFieldBuildMetadata") > connection.index("admitOfficialConnectionStart()"):
        raise SystemExit("official connection must validate metadata before session admission")
    if connection.index("admitOfficialConnectionStart()") > connection.index("OfficialTuyaFactory.make()"):
        raise SystemExit("independent authorization must precede official Tuya driver creation")

    ready_start = source.index("case .readyForStationaryMapping:")
    accepted_start = source.index("self.phase = .accepted", ready_start)
    acceptance = source[ready_start:accepted_start]
    if acceptance.count("fieldAuthorization.stage == .observationAdmitted") < 2:
        raise SystemExit("canonical acceptance must re-check live observation authority at both seal boundaries")
    if acceptance.index("fieldAuthorization.stage == .observationAdmitted") > acceptance.index("sealAfterAcceptedArtifactFreeze()"):
        raise SystemExit("live observation authority must be checked before capability seal")

    APP.write_text(source, encoding="utf-8")


if __name__ == "__main__":
    main()
