from pathlib import Path
import re

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    source = source.replace(old, new, 1)


# 1) There must be one discovery owner: the package-owned bounded correlation session.
replace_once('    static let fd50 = CBUUID(string: "FD50")\n', '', 'legacy FD50 constant')
replace_once('    private var central: CBCentralManager!\n', '', 'legacy central manager')
replace_once('    private var baseline = Set<UUID>()\n', '', 'legacy baseline set')
replace_once('        central = CBCentralManager(delegate: self, queue: .main)\n', '', 'legacy manager initialization')
source = source.replace('        central.stopScan()\n', '')
source = source.replace('        baseline.removeAll()\n', '')

legacy_scanner = re.compile(
    r'\n    private static func hasTuyaCompanyID\(_ data: Data\?\) -> Bool \{.*?\n\}\n\nextension SecureLinkController: @preconcurrency CBCentralManagerDelegate \{.*?\n\}\n\n@MainActor\nprivate protocol OfficialTuyaDriver',
    re.S,
)
source, count = legacy_scanner.subn(
    '\n}\n\n@MainActor\nprivate protocol OfficialTuyaDriver',
    source,
    count=1,
)
if count != 1:
    raise SystemExit(f'legacy scanner block: expected one match, found {count}')

# 2) Compiled build provenance, not Tuya account state, owns field-build presentation authority.
replace_once(
    '    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }\n    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n',
    '    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }\n    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n',
    'field build authority property',
)
replace_once(
    '            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")\n',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Authoritative" : "Not authoritative")\n',
    'field build presentation row',
)
replace_once(
    '            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {\n',
    '            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {\n',
    'NO-GO build provenance gate',
)
replace_once(
    '                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)\n',
    '                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)\n',
    'OFF1 build provenance gate',
)
replace_once(
    '                    .disabled(!test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)\n',
    '                    .disabled(!test.fieldBuildIsAuthoritative || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)\n',
    'confirmation build provenance gate',
)
replace_once(
    '''                    !candidate.likely\n                        || !test.privateConfig\n''',
    '''                    !candidate.likely\n                        || !test.fieldBuildIsAuthoritative\n                        || !test.privateConfig\n''',
    'authentication build provenance gate',
)

# 3) An impossible active ledger generation at explicit confirmation must be terminally retired,
# never hidden by a local presentation failure.
replace_once(
    '''        guard currentConnectionToken == nil else {\n            pendingCorrelatedTargetID = nil\n            failLocally("An authenticated generation already owns session authority. Relaunch Capture before confirming another target.", "active_generation_blocks_target_confirmation")\n            return\n        }\n''',
    '''        guard currentConnectionToken == nil else {\n            pendingCorrelatedTargetID = nil\n            if let token = currentConnectionToken {\n                Task { @MainActor [weak self] in\n                    guard let self else { return }\n                    await self.invalidateInternalLifecycle(\n                        token: token,\n                        message: "An authenticated generation unexpectedly existed during target confirmation. The exact generation was retired before any target authority could be promoted.",\n                        kind: "active_generation_retired_before_target_confirmation"\n                    )\n                }\n            }\n            return\n        }\n''',
    'confirmation lifecycle terminal',
)

# 4) A stale async membership success can never resurrect a stopped/failed attempt.
replace_once(
    '''            guard stillAuthorized,\n                  self.sdkAccountLoggedIn,\n                  self.accountIdentityLeaseIsAuthorized,\n                  self.selectedID == candidate.id else {\n                self.failLocally("Exact scooter/account authority could not be re-verified immediately before BLE authentication.", "sdk_device_membership_recheck_failed")\n                return\n            }\n            self.beginOfficialConnection(candidate: candidate)\n''',
    '''            guard stillAuthorized,\n                  self.phase == .selected,\n                  self.targetCorrelationOperatorConfirmed,\n                  self.sdkAccountLoggedIn,\n                  self.sdkDeviceMembershipVerified,\n                  self.accountIdentityLeaseIsAuthorized,\n                  self.selectedID == candidate.id,\n                  self.pendingCorrelatedTargetID == nil,\n                  self.currentConnectionToken == nil else {\n                self.log("sdk_device_membership_recheck_stale", [\n                    "candidate": candidate.id.uuidString,\n                    "phase": self.phase.rawValue\n                ])\n                return\n            }\n            self.beginOfficialConnection(candidate: candidate)\n''',
    'async membership authority revalidation',
)
replace_once(
    '        guard phase == .selected || phase == .failed else { return }\n',
    '        guard phase == .selected else { return }\n',
    'connection start phase authority',
)
replace_once(
    '''        guard candidate.likely,\n              sdkDeviceMembershipVerified,\n              sdkAccountLoggedIn,\n              accountIdentityLeaseIsAuthorized else {\n''',
    '''        guard candidate.likely,\n              targetCorrelationOperatorConfirmed,\n              selectedID == candidate.id,\n              pendingCorrelatedTargetID == nil,\n              sdkDeviceMembershipVerified,\n              sdkAccountLoggedIn,\n              accountIdentityLeaseIsAuthorized else {\n''',
    'connection start confirmation authority',
)

# Durable assertions: close the known red contracts while preserving accepted simplification.
for forbidden in [
    'private var central: CBCentralManager',
    'CBCentralManager(delegate: self',
    'CBCentralManagerDelegate',
    'central.scanForPeripherals',
    'central.stopScan',
    'private func updateCandidate',
    'didDiscover peripheral',
    'CBAdvertisementDataServiceUUIDsKey',
    'CBAdvertisementDataManufacturerDataKey',
    'CBAdvertisementDataIsConnectableKey',
    'correlationProgressTask',
    'startCorrelationProgressObservation',
]:
    if forbidden in source:
        raise SystemExit(f'forbidden authority/polling surface survived: {forbidden}')

required = [
    'PassiveBluetoothPowerCycleObservationSession',
    'var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }',
    'var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }',
    'LabeledContent("Field build", value: test.fieldBuildIsAuthoritative',
    '!test.fieldBuildIsAuthoritative',
    'guard currentConnectionToken == nil else {',
    'await self.invalidateInternalLifecycle(',
    'self.phase == .selected',
    'self.targetCorrelationOperatorConfirmed',
    'self.selectedID == candidate.id',
    'guard phase == .selected else { return }',
    'markInternalLifecycleFailure(for: token)',
]
for needle in required:
    if needle not in source:
        raise SystemExit(f'missing required final authority contract: {needle}')

confirmation_start = source.index('func confirmCorrelatedTarget')
confirmation_end = source.index('func invalidateSDKMembership', confirmation_start)
confirmation = source[confirmation_start:confirmation_end]
active = confirmation[confirmation.index('currentConnectionToken == nil'):confirmation.index('return', confirmation.index('currentConnectionToken == nil')) + len('return')]
if 'failLocally' in active or 'invalidateInternalLifecycle' not in active:
    raise SystemExit('active-generation confirmation branch does not use canonical lifecycle terminal')

if 'phase == .selected || phase == .failed' in source:
    raise SystemExit('failed phase still authorizes official connection start')

path.write_text(source)
print('Capture final authority convergence assertions PASS')
