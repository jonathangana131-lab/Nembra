from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    s = s.replace(old, new, 1)

replace_once(
'''    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }
''',
'''    var privateConfig: Bool { OfficialTuyaFactory.configured }
    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }
    var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }
    var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }
    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }
''',
"expose compiled field-build authority",
)

replace_once(
'''            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")
            LabeledContent("Private SDK config", value: test.privateConfig ? "Present" : "Missing")
''',
'''            LabeledContent(
                "Field build",
                value: test.fieldBuildIsAuthoritative
                    ? "Authoritative · \\(test.fieldBuildIdentifier)"
                    : "Not authoritative"
            )
            LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)
            LabeledContent("Private SDK config", value: test.privateConfig ? "Present" : "Missing")
''',
"field-build row uses compiled provenance",
)

replace_once(
'''            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: the private exact field build, current SDK account identity, and exact scooter membership must all be proven before even the OFF baseline scan can start.")
''',
'''            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: compiled exact field-build provenance, private SDK configuration, current SDK account identity, and exact scooter membership must all be proven before OFF1 correlation can start.")
''',
"primary NO-GO consumes build authority",
)

replace_once(
'''                Button("Start OFF1 correlation") { test.startBaseline() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
''',
'''                Button("Start OFF1 correlation") { test.startBaseline() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
''',
"OFF1 affordance consumes build authority",
)

path.write_text(s)
