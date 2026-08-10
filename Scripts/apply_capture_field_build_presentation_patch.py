from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one patch anchor, got {count}")
    s = s.replace(old, new, 1)


replace_once(
    "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }",
    "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }",
    "field-build presentation authority",
)

replace_once(
    '            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact provenance verified" : "Not authoritative")',
    "field-build row",
)

replace_once(
    "            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
    "            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
    "NO-GO banner build authority",
)

replace_once(
    "                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "OFF1 action build authority",
)

path.write_text(s)
