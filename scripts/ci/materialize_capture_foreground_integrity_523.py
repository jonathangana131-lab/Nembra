from pathlib import Path

app = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = app.read_text(encoding="utf-8")

if "func appDidLoseForeground()" in source or "@Environment(\\.scenePhase) private var scenePhase" in source:
    raise SystemExit("foreground-integrity repair already present; refuse replay")

method_marker = "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n"
if source.count(method_marker) != 1:
    raise SystemExit(f"controller insertion marker drifted: {source.count(method_marker)}")
method = """    func appDidLoseForeground() {
        // Foreground continuity is part of Capture evidence authority. Close the view-scoped
        // admission boundary first so no account callback can mint a new hidden membership probe.
        acceptsViewScopedMembershipRequests = false
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
        watchdog?.cancel()
        watchdog = nil

        if processCorrelationLease != nil || correlationSession != nil {
            abandonPackageCorrelation()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Restart from OFF1; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
            if phase == .authenticating {
                localBLESettlementToken = nil
                sdkLocalBLEOnline = false
                driver = nil
                phase = .failed
                message = "Capture left the foreground during authentication. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
                log("foreground_integrity_lost_before_observation")
            }
            return
        }

        let wasObserving = phase == .observing
        phase = .failed
        message = wasObserving
            ? "Capture left the foreground during authenticated observation. Restart from OFF1; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        // The disappearing/inactive view must not be the sole lifetime owner of terminal ledger
        // retirement. Retain the controller only for this bounded exact-token operation.
        Task { @MainActor [self] in
            if wasObserving {
                await self.invalidateObservationContinuity(
                    token: token,
                    message: "App foreground integrity was lost during authenticated observation. Restart from OFF1; background time is not accepted evidence and no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_during_observation"
                )
            } else {
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "App foreground integrity was lost before authenticated observation. Relaunch before another authenticated attempt; no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_before_observation"
                )
            }
        }
    }

"""
source = source.replace(method_marker, method + method_marker, 1)

env_marker = "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n"
if source.count(env_marker) != 1:
    raise SystemExit(f"dynamic-type environment marker drifted: {source.count(env_marker)}")
source = source.replace(env_marker, env_marker + "    @Environment(\\.scenePhase) private var scenePhase\n", 1)

view_marker = """        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
"""
if source.count(view_marker) != 1:
    raise SystemExit(f"Secure Link view lifecycle marker drifted: {source.count(view_marker)}")
source = source.replace(
    view_marker,
    view_marker + """        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                test.appDidLoseForeground()
            }
        }
""",
    1,
)

start = source.index("func appDidLoseForeground()")
end = source.index("var privateConfig: Bool", start)
cleanup = source[start:end]
for required in (
    "acceptsViewScopedMembershipRequests = false",
    "membershipRequestID = UUID()",
    "membershipBusy = false",
    "membershipProbe = nil",
    "officialConnectionRequestID = UUID()",
    "watchdog?.cancel()",
    "if processCorrelationLease != nil || correlationSession != nil",
    "abandonPackageCorrelation()",
    "invalidateObservationContinuity(",
    "invalidateInternalLifecycle(",
    "foreground_integrity_lost_during_target_correlation",
    "foreground_integrity_lost_during_observation",
    "foreground_integrity_lost_before_observation",
    "Task { @MainActor [self] in",
):
    if required not in cleanup:
        raise SystemExit(f"missing foreground contract: {required}")
for forbidden in ("releasePackageCorrelationLease()", "recordObservedTransportLoss", "endConnection", "disconnectBLE"):
    if forbidden in cleanup:
        raise SystemExit(f"foreground loss must not claim/force transport loss: {forbidden}")
if not (
    cleanup.index("acceptsViewScopedMembershipRequests = false")
    < cleanup.index("membershipRequestID = UUID()")
    < cleanup.index("officialConnectionRequestID = UUID()")
    < cleanup.index("if processCorrelationLease != nil || correlationSession != nil")
):
    raise SystemExit("foreground authority revocation ordering is wrong")
for inherited in (
    "func activateMembershipRequestsForView()",
    "Task { @MainActor [self] in\n                await self.invalidateInternalLifecycle(",
    "self.officialConnectionRequestID == connectionRequestID",
    "if dynamicTypeSize.isAccessibilitySize {",
    ".accessibilityLabel(\"Correlation progress\")",
    ".accessibilityLabel(\"Read-only observation progress\")",
):
    if inherited not in source:
        raise SystemExit(f"current-product invariant lost: {inherited}")
if "if newPhase == .active { test.activateMembershipRequestsForView()" in source:
    raise SystemExit("foreground return must not silently reopen view-scoped authority")

app.write_text(source, encoding="utf-8")
print("Capture foreground-integrity 523 transform: PASS")
