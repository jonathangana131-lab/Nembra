#!/usr/bin/env python3
"""Remove the legacy hard-false build-authority cycle after app-session materialization.

This runs only after the canonical SecureLink field-authorization materializer has inserted the
package-owned one-time authorization session. Build metadata remains a required exact-runtime
prerequisite, but it is not authority. The verified package session is the independent authority
that admits OFF1/authentication/official connection/observation.
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
        "sealAfterAcceptedArtifactFreeze()",
    )
    for token in required:
        if token not in source:
            raise SystemExit(f"authorization lifecycle must be materialized first: missing {token}")

    # The old name described a Boolean that is intentionally hard false. Once the independently
    # verified one-time app session exists, self-described build metadata is only a prerequisite.
    source = replace_exact(
        source,
        "fieldBuildIsAuthoritative",
        "fieldBuildMetadataReady",
        "rename legacy build-authority presentation seam",
        expected=12,
    )

    source = replace_exact(
        source,
        "private var fieldBuildMetadataReady: Bool { buildIdentity.isAuthoritativeFieldBuild }",
        "private var fieldBuildMetadataReady: Bool { buildIdentity.hasCompleteFieldBuildMetadata }",
        "root metadata readiness",
    )
    source = replace_exact(
        source,
        "var fieldBuildMetadataReady: Bool { buildIdentity.isAuthoritativeFieldBuild }",
        "var fieldBuildMetadataReady: Bool { buildIdentity.hasCompleteFieldBuildMetadata }",
        "SecureLink metadata readiness",
    )

    # Handoff is non-authorizing: it may prepare/read retained subjects once exact runtime metadata
    # is complete. The package verifier still mints no authority until the signed envelope verifies.
    source = replace_exact(
        source,
        "guard phase == .idle, buildIdentity.isAuthoritativeFieldBuild else { return }",
        "guard phase == .idle, buildIdentity.hasCompleteFieldBuildMetadata else { return }",
        "non-authorizing handoff reachability",
    )

    # The runtime build guards remain defense-in-depth metadata checks. Physical transition authority
    # is immediately downstream in the package-owned fieldAuthorization admission methods.
    source = replace_exact(
        source,
        "guard buildIdentity.isAuthoritativeFieldBuild else {",
        "guard buildIdentity.hasCompleteFieldBuildMetadata else {",
        "OFF1 metadata guard",
    )
    source = replace_exact(
        source,
        "              buildIdentity.isAuthoritativeFieldBuild,",
        "              buildIdentity.hasCompleteFieldBuildMetadata,",
        "official connection metadata guard",
    )

    # Product language must not promote metadata into authority. The separate one-time authorization
    # row/status is the visible independent authority and remains required by authorityReady.
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

    if "buildIdentity.isAuthoritativeFieldBuild" in source:
        raise SystemExit("legacy hard-false build authority still participates in app runtime")

    # Fail closed on the actual independent authority: metadata alone may unlock account selection and
    # handoff preparation, but authorityReady must still require the armed verifier-owned session.
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

    APP.write_text(source, encoding="utf-8")


if __name__ == "__main__":
    main()
