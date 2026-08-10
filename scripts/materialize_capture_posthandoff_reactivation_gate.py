from pathlib import Path

SOURCE = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = SOURCE.read_text()

old = '''    func activateMembershipRequestsForView() {
        // A fast inactive -> active transition must not reset the duplicate-retirement fence
        // while the exact authenticated generation from foreground loss is still terminalizing.
        guard currentConnectionToken == nil else { return }
        foregroundIntegrityLossHandled = false
        acceptsViewScopedMembershipRequests = true
    }
'''
new = '''    func activateMembershipRequestsForView() {
        // A fast inactive -> active transition must not reset the duplicate-retirement fence
        // while the exact authenticated generation from foreground loss is still terminalizing.
        // `make()` retires package correlation before the async package token exists, so token-nil
        // alone is insufficient: foreground return may reopen admission only pre-handoff.
        guard OfficialTuyaFactory.packageCorrelationMayStart,
              currentConnectionToken == nil else { return }
        foregroundIntegrityLossHandled = false
        acceptsViewScopedMembershipRequests = true
    }
'''

if text.count(old) != 1:
    raise SystemExit(f"activation anchor drifted: {text.count(old)}")
text = text.replace(old, new, 1)
SOURCE.write_text(text)

updated = SOURCE.read_text()
controller = updated[updated.index('private final class SecureLinkController'):updated.index('@MainActor\nprivate protocol OfficialTuyaDriver')]
activation = controller[controller.index('func activateMembershipRequestsForView()'):controller.index('func abandonCorrelationForViewExit()')]
assert 'OfficialTuyaFactory.packageCorrelationMayStart' in activation
assert activation.index('OfficialTuyaFactory.packageCorrelationMayStart') < activation.index('foregroundIntegrityLossHandled = false')
assert activation.index('currentConnectionToken == nil') < activation.index('foregroundIntegrityLossHandled = false')
print('materialized post-handoff foreground reactivation gate')
