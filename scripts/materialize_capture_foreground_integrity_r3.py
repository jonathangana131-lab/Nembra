from pathlib import Path

SOURCE = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = SOURCE.read_text()

property_anchor = "    private var officialConnectionRequestID = UUID()\n"
property_replacement = property_anchor + "    private var lifecycleRetirementToken: TuyaReadOnlyConnectionToken?\n"
if text.count(property_anchor) != 1:
    raise SystemExit("official connection request property anchor drifted")
if "lifecycleRetirementToken" in text:
    raise SystemExit("lifecycle retirement token already exists")
text = text.replace(property_anchor, property_replacement, 1)

exit_old = '''        if let token = currentConnectionToken {
            phase = .failed
            message = "Authenticated observation stopped because Capture left Secure Link. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
            log("authenticated_session_abandoned_on_view_exit", ["generation": String(token.diagnosticGeneration)])
            Task { @MainActor [self] in
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "Authenticated observation stopped because Capture left Secure Link. Relaunch before another authenticated attempt; no BLE disconnect is claimed.",
                    kind: "authenticated_session_abandoned_on_view_exit"
                )
            }
            return
        }
'''
exit_new = '''        if let token = currentConnectionToken {
            guard lifecycleRetirementToken != token else {
                log("duplicate_lifecycle_retirement_request_ignored", ["generation": String(token.diagnosticGeneration)])
                return
            }
            lifecycleRetirementToken = token
            phase = .failed
            message = "Authenticated observation stopped because Capture left Secure Link. Relaunch before another authenticated stationary read-only attempt; no BLE disconnect is claimed."
            log("authenticated_session_abandoned_on_view_exit", ["generation": String(token.diagnosticGeneration)])
            Task { @MainActor [self] in
                guard self.lifecycleRetirementToken == token,
                      self.currentConnectionToken == token else { return }
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "Authenticated observation stopped because Capture left Secure Link. Relaunch before another authenticated stationary read-only attempt; no BLE disconnect is claimed.",
                    kind: "authenticated_session_abandoned_on_view_exit"
                )
            }
            return
        }
'''
if text.count(exit_old) != 1:
    raise SystemExit("view-exit token retirement anchor drifted")
text = text.replace(exit_old, exit_new, 1)

method_anchor = '''        log("target_correlation_abandoned_on_view_exit")
    }

    var privateConfig: Bool { OfficialTuyaFactory.configured }
'''
method_replacement = '''        log("target_correlation_abandoned_on_view_exit")
    }

    func appDidLoseForeground() {
        // Foreground integrity is an evidence boundary. Close membership admission and revoke
        // already-earned account/device proof before inspecting any radio/session ownership.
        acceptsViewScopedMembershipRequests = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
        watchdog?.cancel()
        watchdog = nil

        if processCorrelationLease != nil || correlationSession != nil {
            // No official Tuya driver has been handed out on this path. Stop package transport
            // before releasing its process lease; the next attempt must start from a fresh OFF1.
            abandonPackageCorrelation()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Return to Capture, re-verify exact scooter membership, and Restart from OFF1; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
            if phase == .authenticating {
                // Official driver handoff can precede package token creation. Revoked request IDs
                // force the pending generation to retire before SDK connect; process relaunch is
                // required because package correlation is now retired for this process.
                localBLESettlementToken = nil
                sdkLocalBLEOnline = false
                driver = nil
                phase = .failed
                message = "Capture left the foreground during authentication. Relaunch before another authenticated stationary read-only attempt; no BLE disconnect is claimed."
                log("foreground_integrity_lost_before_observation")
            }
            return
        }

        // iOS may deliver inactive → background and onDisappear for one transition. Admit one
        // exact-token lifecycle terminal so those hooks cannot race two package retirements.
        guard lifecycleRetirementToken != token else {
            log("duplicate_lifecycle_retirement_request_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        lifecycleRetirementToken = token
        let wasObserving = phase == .observing
        phase = .failed
        message = wasObserving
            ? "Capture left the foreground during authenticated observation. Relaunch before another authenticated stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch before another authenticated stationary read-only attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        Task { @MainActor [self] in
            guard self.lifecycleRetirementToken == token,
                  self.currentConnectionToken == token else { return }
            if wasObserving {
                await self.invalidateObservationContinuity(
                    token: token,
                    message: "App foreground integrity was lost during authenticated observation. Relaunch before another authenticated stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_during_observation"
                )
            } else {
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "App foreground integrity was lost before authenticated observation. Relaunch before another authenticated stationary read-only attempt; no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_before_observation"
                )
            }
        }
    }

    func appDidRegainForeground() {
        // Reopen only the pre-handoff package path. Once OfficialTuyaFactory.make() has retired
        // package correlation for this process, foreground return cannot manufacture new authority.
        guard OfficialTuyaFactory.packageCorrelationMayStart,
              currentConnectionToken == nil,
              localBLESettlementToken == nil,
              driver == nil else { return }
        acceptsViewScopedMembershipRequests = true
        membershipStatus = "Foreground restored. Exact scooter membership must be freshly verified before a new stationary attempt."
    }

    var privateConfig: Bool { OfficialTuyaFactory.configured }
'''
if text.count(method_anchor) != 1:
    raise SystemExit("foreground method insertion anchor drifted")
text = text.replace(method_anchor, method_replacement, 1)

environment_anchor = "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n"
environment_replacement = environment_anchor + "    @Environment(\\.scenePhase) private var scenePhase\n"
if text.count(environment_anchor) != 1:
    raise SystemExit("Secure Link environment anchor drifted")
text = text.replace(environment_anchor, environment_replacement, 1)

lifecycle_anchor = '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
'''
lifecycle_replacement = '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                test.appDidRegainForeground()
                if sdkAccount.loggedIn { test.verifySDKMembership() }
            } else {
                test.appDidLoseForeground()
            }
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
'''
if text.count(lifecycle_anchor) != 1:
    raise SystemExit("Secure Link lifecycle anchor drifted")
text = text.replace(lifecycle_anchor, lifecycle_replacement, 1)

SOURCE.write_text(text)
print("materialized foreground-integrity r3 repair")
