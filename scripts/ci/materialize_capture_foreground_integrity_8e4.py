from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")

method_marker = "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n"
if source.count(method_marker) != 1:
    raise SystemExit(f"expected one controller insertion marker, found {source.count(method_marker)}")
method = """    func appDidLoseForeground() {
        // Capture evidence is foreground-only. Revoke pending membership/official-start grants
        // before inspecting current transport state so backgrounding cannot begin hidden work.
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

        Task { @MainActor [weak self] in
            guard let self, self.currentConnectionToken == token else { return }
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
    raise SystemExit(f"expected one scene environment marker, found {source.count(env_marker)}")
source = source.replace(
    env_marker,
    env_marker + "    @Environment(\\.scenePhase) private var scenePhase\n",
    1,
)

view_marker = """        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
"""
if source.count(view_marker) != 1:
    raise SystemExit(f"expected one view lifecycle marker, found {source.count(view_marker)}")
source = source.replace(
    view_marker,
    view_marker
    + """        .onChange(of: scenePhase) { _, newPhase in
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
    "membershipRequestID = UUID()",
    "membershipBusy = false",
    "membershipProbe = nil",
    "officialConnectionRequestID = UUID()",
    "watchdog?.cancel()",
    "if processCorrelationLease != nil || correlationSession != nil",
    "abandonPackageCorrelation()",
    "foreground_integrity_lost_during_target_correlation",
    "invalidateObservationContinuity(",
    "foreground_integrity_lost_during_observation",
    "invalidateInternalLifecycle(",
    "foreground_integrity_lost_before_observation",
):
    if required not in cleanup:
        raise SystemExit(f"missing foreground contract: {required}")
if cleanup.index("membershipRequestID = UUID()") >= cleanup.index("if processCorrelationLease"):
    raise SystemExit("membership grant not revoked before transport inspection")
if cleanup.index("officialConnectionRequestID = UUID()") >= cleanup.index("if processCorrelationLease"):
    raise SystemExit("official connection grant not revoked before transport inspection")
for forbidden in ("releasePackageCorrelationLease()", "recordObservedTransportLoss", "endConnection", "disconnectBLE"):
    if forbidden in cleanup:
        raise SystemExit(f"foreground cleanup must not claim/force transport loss: {forbidden}")
for inherited in (
    "self.officialConnectionRequestID == connectionRequestID",
    "self.currentConnectionToken == token",
    "if dynamicTypeSize.isAccessibilitySize {",
    ".accessibilityLabel(\"Correlation progress\")",
    ".accessibilityLabel(\"Read-only observation progress\")",
    "test.abandonCorrelationForViewExit()",
):
    if inherited not in source:
        raise SystemExit(f"current product invariant missing after transform: {inherited}")

path.write_text(source, encoding="utf-8")
print("Capture foreground-integrity current-product transform: PASS")
