#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")

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
        // while an authenticated generation is terminalizing. Once the official Tuya driver has
        // been handed out, package correlation is permanently retired for this process and the
        // foreground-loss recovery contract is relaunch rather than silently reopening authority.
        guard currentConnectionToken == nil,
              OfficialTuyaFactory.packageCorrelationMayStart else { return }
        foregroundIntegrityLossHandled = false
        acceptsViewScopedMembershipRequests = true
    }
'''
if source.count(old) != 1:
    raise SystemExit(f"expected one current membership activation block, found {source.count(old)}")
source = source.replace(old, new, 1)

status_anchor = '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
'''
status_replacement = '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Exact scooter membership must be verified again after Capture leaves Secure Link authority."
        membershipRequestID = UUID()
'''
# Both view-exit and foreground-loss must couple operator copy to proof revocation.
if source.count(status_anchor) != 2:
    raise SystemExit(f"expected two view/foreground membership revocation blocks, found {source.count(status_anchor)}")
source = source.replace(status_anchor, status_replacement)

old = '''    func appDidLoseForeground() {
        guard !foregroundIntegrityLossHandled else { return }
        foregroundIntegrityLossHandled = true
'''
new = '''    func appDidLoseForeground() {
        // A sealed accepted artifact is immutable and already closed to new evidence. Backgrounding
        // after acceptance must not downgrade or rebuild that frozen result.
        guard phase != .accepted else { return }
        guard !foregroundIntegrityLossHandled else { return }
        foregroundIntegrityLossHandled = true
'''
if source.count(old) != 1:
    raise SystemExit(f"expected one foreground entry block, found {source.count(old)}")
source = source.replace(old, new, 1)

old = '''        if processCorrelationLease != nil || correlationSession != nil {
            // Existing helper stops package transport before releasing this controller's lease.
            abandonPackageCorrelation()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
'''
new = '''        if processCorrelationLease != nil || correlationSession != nil {
            // The full discovery reset preserves scanner-first lease retirement and also erases
            // every actionable target-selection bit earned by the interrupted correlation.
            resetDiscoverySessionOnly()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        if phase == .correlated || phase == .selected {
            // Final-window sealing already retires the package scanner/lease. These phases can
            // therefore hold actionable target authority with no live transport object to inspect.
            // Foreground loss must invalidate that authority explicitly before a retry.
            resetDiscoverySessionOnly()
            phase = .failed
            message = "Capture left the foreground after Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; the prior correlated/selected target cannot cross a foreground-integrity break."
            log("foreground_integrity_lost_after_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
'''
if source.count(old) != 1:
    raise SystemExit(f"expected one foreground correlation branch, found {source.count(old)}")
source = source.replace(old, new, 1)

path.write_text(source, encoding="utf-8")

controller_start = source.index("private final class SecureLinkController")
controller_end = source.index("@MainActor\nprivate protocol OfficialTuyaDriver", controller_start)
controller = source[controller_start:controller_end]
activation_start = controller.index("func activateMembershipRequestsForView()")
exit_start = controller.index("func abandonCorrelationForViewExit()", activation_start)
activation = controller[activation_start:exit_start]
foreground_start = controller.index("func appDidLoseForeground()")
private_config = controller.index("var privateConfig: Bool", foreground_start)
foreground = controller[foreground_start:private_config]
view_exit_start = controller.index("func abandonCorrelationForViewExit()")
view_exit = controller[view_exit_start:foreground_start]

if "guard currentConnectionToken == nil," not in activation or "OfficialTuyaFactory.packageCorrelationMayStart else { return }" not in activation:
    raise SystemExit("foreground reactivation must remain closed after official driver handoff")
if "guard phase != .accepted else { return }" not in foreground:
    raise SystemExit("sealed accepted artifacts need an explicit foreground-loss exemption")
if foreground.count("resetDiscoverySessionOnly()") != 2:
    raise SystemExit("both active correlation and already-correlated/selected foreground loss must use full discovery reset")
if "if phase == .correlated || phase == .selected" not in foreground or "foreground_integrity_lost_after_target_correlation" not in foreground:
    raise SystemExit("already-sealed correlation target authority can still cross foreground loss")
for cleanup_name, cleanup in (("view-exit", view_exit), ("foreground", foreground)):
    required = (
        "sdkDeviceMembershipVerified = false",
        "membershipStatus = \"Exact scooter membership must be verified again",
        "membershipRequestID = UUID()",
    )
    for needle in required:
        if needle not in cleanup:
            raise SystemExit(f"{cleanup_name} missing membership-status revocation invariant: {needle}")
    if cleanup.index("sdkDeviceMembershipVerified = false") > cleanup.index("membershipStatus = \"Exact scooter membership must be verified again"):
        raise SystemExit(f"{cleanup_name} must clear proof before resetting operator copy")
    if cleanup.index("membershipStatus = \"Exact scooter membership must be verified again") > cleanup.index("membershipRequestID = UUID()"):
        raise SystemExit(f"{cleanup_name} must reset operator copy before rotating request authority")
for forbidden in ("recordObservedTransportLoss", "endConnection(", "disconnectBLE", "publishDps", "queryDps", "writeValue"):
    if forbidden in foreground:
        raise SystemExit(f"foreground integrity lane gained forbidden inferred/command authority: {forbidden}")
print("foreground target + membership authority revocation: PASS")
