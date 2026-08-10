#!/usr/bin/env bash
set -euo pipefail
parent='b59cd71272b465bcad70fcc3425382bb29541b2e'
git merge-base --is-ancestor "$parent" HEAD
git diff --quiet "$parent" HEAD -- NembraApp/App/NembraCaptureEntrypoint.swift Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaNavigationBLELeaseRetirementSourceTests.swift

python3 - <<'PY'
from pathlib import Path
app = Path('NembraApp/App/NembraCaptureEntrypoint.swift')
source = app.read_text()
start_token = '    func abandonCorrelationForViewExit() {'
end_token = '\n\n    var privateConfig: Bool'
assert source.count(start_token) == 1
start = source.index(start_token)
end = source.index(end_token, start)
replacement = '''    func abandonCorrelationForViewExit() {
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif

        guard processCorrelationLease != nil || correlationSession != nil else { return }
        abandonPackageCorrelation()
        phase = .failed
        message = "Bluetooth correlation was interrupted when Capture left Secure Link. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series."
        log("target_correlation_abandoned_on_view_exit")
    }'''
app.write_text(source[:start] + replacement + source[end:])

test = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaNavigationBLELeaseRetirementSourceTests.swift')
contract = test.read_text()
contract = contract.replace('to: "private extension SecureLinkView"', 'to: "private var hero: some View"')
old = '''        #expect(controller.contains("func abandonCorrelationForViewExit()"))
        #expect(controller.contains("guard processCorrelationLease != nil || correlationSession != nil else { return }"))
        #expect(controller.contains("abandonPackageCorrelation()"))
        #expect(controller.contains("target_correlation_abandoned_on_view_exit"))
        #expect(view.contains(".onDisappear"))
        #expect(view.contains("test.abandonCorrelationForViewExit()"))'''
assert contract.count(old) == 1
new = '''        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))
        #expect(cleanup.contains("membershipRequestID = UUID()"))
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("guard processCorrelationLease != nil || correlationSession != nil else { return }"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("target_correlation_abandoned_on_view_exit"))
        #expect(!cleanup.contains("releasePackageCorrelationLease"))
        #expect(cleanup.range(of: "membershipRequestID = UUID()")!.lowerBound < cleanup.range(of: "guard processCorrelationLease")!.lowerBound)
        #expect(view.contains(".onDisappear"))
        #expect(view.contains("test.abandonCorrelationForViewExit()"))'''
test.write_text(contract.replace(old, new, 1))
PY

python3 - <<'PY'
from pathlib import Path
s = Path('NembraApp/App/NembraCaptureEntrypoint.swift').read_text()
start = s.index('func abandonCorrelationForViewExit()')
end = s.index('var privateConfig: Bool', start)
cleanup = s[start:end]
for needle in ('membershipRequestID = UUID()', 'membershipBusy = false', 'membershipProbe = nil', 'abandonPackageCorrelation()'):
    assert needle in cleanup
assert cleanup.index('membershipRequestID = UUID()') < cleanup.index('guard processCorrelationLease')
assert cleanup.index('membershipProbe = nil') < cleanup.index('guard processCorrelationLease')
for forbidden in ('releasePackageCorrelationLease', 'connectBLE(', 'disconnectBLE', 'queryDps', 'publishDps', 'writeValue'):
    assert forbidden not in cleanup
PY

git diff --check
swiftc -parse NembraApp/App/NembraCaptureEntrypoint.swift
swiftc -parse Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaNavigationBLELeaseRetirementSourceTests.swift
rm .github/workflows/materialize-capture-view-exit-membership-b59.yml
rm .github/materializers/view-exit-membership-b59.sh
git add -A
git reset --soft "$parent"
git reset
git add NembraApp/App/NembraCaptureEntrypoint.swift Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaNavigationBLELeaseRetirementSourceTests.swift
test "$(git diff --cached --name-only | wc -l | tr -d ' ')" = 2
git diff --cached --check
git config user.name 'nembra-sol'
git config user.email 'nembra-sol@users.noreply.github.com'
git commit -m 'fix(capture): cancel hidden OFF1 start on view exit'
git push --force-with-lease origin HEAD:fix/v14-capture-view-exit-membership-b59-sol
