from pathlib import Path
p=Path('NembraApp/App/NembraCaptureEntrypoint.swift'); s=p.read_text()
if 'func appDidLoseForeground()' in s: raise SystemExit('already repaired')
m='    var privateConfig: Bool { OfficialTuyaFactory.configured }\n'; assert s.count(m)==1
f='''    func appDidLoseForeground() {
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
        message = wasObserving ? "Capture left the foreground during authenticated observation. Restart from OFF1; background time is not accepted evidence and no BLE disconnect is claimed." : "Capture left the foreground before authenticated observation. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
        log(wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation", ["generation": String(token.diagnosticGeneration)])
        Task { @MainActor [self] in
            if wasObserving {
                await self.invalidateObservationContinuity(token: token, message: "App foreground integrity was lost during authenticated observation. Restart from OFF1; background time is not accepted evidence and no BLE disconnect is claimed.", kind: "foreground_integrity_lost_during_observation")
            } else {
                await self.invalidateInternalLifecycle(token: token, message: "App foreground integrity was lost before authenticated observation. Relaunch before another authenticated attempt; no BLE disconnect is claimed.", kind: "foreground_integrity_lost_before_observation")
            }
        }
    }

'''
s=s.replace(m,f+m,1)
e='    @Environment(\.dynamicTypeSize) private var dynamicTypeSize\n'; assert s.count(e)==1; s=s.replace(e,e+'    @Environment(\.scenePhase) private var scenePhase\n',1)
l='''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
'''; assert s.count(l)==1; s=s.replace(l,l+'''        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { test.appDidLoseForeground() }
        }
''',1)
c=s[s.index('func appDidLoseForeground()'):s.index('var privateConfig: Bool',s.index('func appDidLoseForeground()'))]
for x in ['acceptsViewScopedMembershipRequests = false','membershipRequestID = UUID()','officialConnectionRequestID = UUID()','abandonPackageCorrelation()','invalidateObservationContinuity(','invalidateInternalLifecycle(','Task { @MainActor [self] in']: assert x in c,x
for x in ['releasePackageCorrelationLease()','recordObservedTransportLoss','endConnection','disconnectBLE']: assert x not in c,x
for x in ['"appsecret"','"accounttoken"','func activateMembershipRequestsForView()','self.officialConnectionRequestID == connectionRequestID']: assert x in s,x
p.write_text(s)
