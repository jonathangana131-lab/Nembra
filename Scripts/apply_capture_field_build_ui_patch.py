from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()

def once(old: str, new: str) -> None:
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"anchor count {n}: {old[:120]!r}")
    s = s.replace(old, new, 1)

once(
'''    var accountIdentityLeaseIsAuthorized: Bool {
        TuyaSDKAccountIdentityLeaseGate.verdict(for: accountIdentityLeaseSnapshot) == .authorized
    }
''',
'''    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }

    var accountIdentityLeaseIsAuthorized: Bool {
        TuyaSDKAccountIdentityLeaseGate.verdict(for: accountIdentityLeaseSnapshot) == .authorized
    }
''')
once(
'            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")',
'            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact provenance" : "Not authoritative")'
)
once(
'''            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: the private exact field build, current SDK account identity, and exact scooter membership must all be proven before even the OFF baseline scan can start.")
''',
'''            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: exact compiled field-build provenance, private SDK configuration, current SDK account identity, and exact scooter membership must all be proven before OFF1 correlation can start.")
''')
once(
'''                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
''',
'''                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
''')
path.write_text(s)
