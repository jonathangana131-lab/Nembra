from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()
old = '''    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        await authenticationAcquisitionFailed(
            token: token,
            message: "Tuya SmartLife SDK did not establish the supported BLE session.",
            kind: "official_connect_failed"
        )
    }'''
new = '''    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            await invalidateSourceAuthority(
                token: token,
                message: "Tuya account/device source authority changed before the SDK failure callback was classified.",
                kind: "sdk_source_authority_lost_before_auth_failure"
            )
            return
        }
        await authenticationAcquisitionFailed(
            token: token,
            message: "Tuya SmartLife SDK did not establish the supported BLE session.",
            kind: "official_connect_failed"
        )
    }'''
if source.count(old) != 1:
    raise SystemExit(f"expected one authenticationFailed block, found {source.count(old)}")
source = source.replace(old, new, 1)
for marker in ("sdkAccountLoggedIn", "sdkDeviceMembershipVerified", "accountIdentityLeaseIsAuthorized", "invalidateSourceAuthority", "authenticationAcquisitionFailed"):
    if marker not in source:
        raise SystemExit(f"missing source-race marker: {marker}")
path.write_text(source)
print("authentication failure source-race fix applied")
