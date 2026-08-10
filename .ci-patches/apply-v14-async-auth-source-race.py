from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
app = APP.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global app
    count = app.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    app = app.replace(old, new, 1)

replace_once(
    '''            guard stillAuthorized,
                  self.sdkAccountLoggedIn,
                  self.accountIdentityLeaseIsAuthorized,
                  self.selectedID == candidate.id else {''',
    '''            guard stillAuthorized,
                  self.sdkAccountLoggedIn,
                  self.sdkDeviceMembershipVerified,
                  self.accountIdentityLeaseIsAuthorized,
                  self.phase == .selected,
                  self.targetCorrelationOperatorConfirmed,
                  self.selectedID == candidate.id else {''',
    "async membership callback authority",
)

replace_once(
    '''    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected || phase == .failed else { return }
        guard candidate.likely,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {''',
    '''    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected else { return }
        guard candidate.likely,
              targetCorrelationOperatorConfirmed,
              selectedID == candidate.id,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {''',
    "failed-phase resurrection fence",
)

replace_once(
    '''    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        await authenticationAcquisitionFailed(
            token: token,
            message: "Tuya SmartLife SDK did not establish the supported BLE session.",
            kind: "official_connect_failed"
        )
    }''',
    '''    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
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
    }''',
    "SDK failure source-authority race",
)

for marker in (
    "self.phase == .selected",
    "self.targetCorrelationOperatorConfirmed",
    "guard phase == .selected else { return }",
    "selectedID == candidate.id",
    "sdk_source_authority_lost_before_auth_failure",
):
    if marker not in app:
        raise SystemExit(f"required authority marker missing: {marker}")
if "phase == .selected || phase == .failed" in app:
    raise SystemExit("failed-phase connection resurrection remains")

APP.write_text(app)
print("V14 async authentication authority repair applied")
