from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    s = s.replace(old, new, 1)

replace_once(
'''    func authenticate() {
        guard let candidate = selected, candidate.likely else {
            failLocally("A fresh repeated OFF1→ON1→OFF2→ON2 Bluetooth correlation is required before Tuya BLE ownership.", "candidate_not_authoritative")
            return
        }
''',
'''    func authenticate() {
        guard phase == .selected,
              targetCorrelationOperatorConfirmed,
              let candidate = selected,
              candidate.likely else {
            failLocally("An explicitly confirmed fresh OFF1→ON1→OFF2→ON2 Bluetooth correlation is required before Tuya BLE ownership.", "candidate_not_authoritative")
            return
        }
''',
"authenticate entry authority",
)

replace_once(
'''            guard stillAuthorized,
                  self.sdkAccountLoggedIn,
                  self.accountIdentityLeaseIsAuthorized,
                  self.selectedID == candidate.id else {
                self.failLocally("Exact scooter/account authority could not be re-verified immediately before BLE authentication.", "sdk_device_membership_recheck_failed")
                return
            }
''',
'''            guard stillAuthorized,
                  self.phase == .selected,
                  self.targetCorrelationOperatorConfirmed,
                  self.sdkAccountLoggedIn,
                  self.accountIdentityLeaseIsAuthorized,
                  self.selectedID == candidate.id else {
                self.failLocally("Exact selected-target confirmation and scooter/account authority could not be re-verified immediately before BLE authentication.", "sdk_device_membership_recheck_failed")
                return
            }
''',
"async membership callback authority",
)

replace_once(
'''    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected || phase == .failed else { return }
        guard candidate.likely,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {
''',
'''    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected else { return }
        guard targetCorrelationOperatorConfirmed,
              selectedID == candidate.id,
              candidate.likely,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {
''',
"connection start authority",
)

path.write_text(s)
