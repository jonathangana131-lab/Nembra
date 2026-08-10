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
'''            guard stillAuthorized,
                  self.sdkAccountLoggedIn,
                  self.accountIdentityLeaseIsAuthorized,
                  self.selectedID == candidate.id else {
                self.failLocally("Exact scooter/account authority could not be re-verified immediately before BLE authentication.", "sdk_device_membership_recheck_failed")
                return
            }
            self.beginOfficialConnection(candidate: candidate)
''',
'''            guard stillAuthorized,
                  self.phase == .selected,
                  self.targetCorrelationOperatorConfirmed,
                  self.sdkAccountLoggedIn,
                  self.accountIdentityLeaseIsAuthorized,
                  self.selectedID == candidate.id else {
                self.failLocally("Exact confirmed scooter/account authority could not be re-verified immediately before BLE authentication.", "sdk_device_membership_recheck_failed")
                return
            }
            self.beginOfficialConnection(candidate: candidate)
''',
"membership callback rechecks selected confirmation",
)

replace_once(
'''    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected || phase == .failed else { return }
        guard candidate.likely,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Tuya account/device authority changed before connection start.", "sdk_authority_changed")
            return
        }
''',
'''    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected else { return }
        guard targetCorrelationOperatorConfirmed,
              selectedID == candidate.id,
              candidate.likely,
              buildIdentity.isAuthoritativeFieldBuild,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Confirmed build or Tuya account/device authority changed before connection start.", "sdk_authority_changed")
            return
        }
''',
"connection start admits selected authority only",
)

path.write_text(s)
