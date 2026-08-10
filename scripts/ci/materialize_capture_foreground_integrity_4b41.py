from pathlib import Path

p=Path('NembraApp/App/NembraCaptureEntrypoint.swift')
s=p.read_text(encoding='utf-8')
if 'func appDidLoseForeground()' in s or '@Environment(\.scenePhase) private var scenePhase' in s:
    raise SystemExit('foreground repair already present')
marker='    var privateConfig: Bool { OfficialTuyaFactory.configured }\n'
assert s.count(marker)==1
method='''    func appDidLoseForeground() {
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
s=s.replace(marker,method+marker,1)
env='    @Environment(\.dynamicTypeSize) private var dynamicTypeSize\n'
assert s.count(env)==1
s=s.replace(env,env+'    @Environment(\.scenePhase) private var scenePhase\n',1)
life='''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
'''
assert s.count(life)==1
s=s.replace(life,life+'''        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                test.appDidLoseForeground()
            }
        }
''',1)
start=s.index('func appDidLoseForeground()'); end=s.index('var privateConfig: Bool',start); c=s[start:end]
req=['acceptsViewScopedMembershipRequests = false','membershipRequestID = UUID()','membershipBusy = false','membershipProbe = nil','officialConnectionRequestID = UUID()','watchdog?.cancel()','if processCorrelationLease != nil || correlationSession != nil','abandonPackageCorrelation()','invalidateObservationContinuity(','invalidateInternalLifecycle(','Task { @MainActor [self] in']
for x in req:
    assert x in c,x
assert c.index('acceptsViewScopedMembershipRequests = false') < c.index('membershipRequestID = UUID()') < c.index('officialConnectionRequestID = UUID()') < c.index('if processCorrelationLease != nil || correlationSession != nil')
for x in ['releasePackageCorrelationLease()','recordObservedTransportLoss','endConnection','disconnectBLE']:
    assert x not in c,x
for x in ['func activateMembershipRequestsForView()','if dynamicTypeSize.isAccessibilitySize {','.accessibilityLabel("Correlation progress")','.accessibilityLabel("Read-only observation progress")','self.officialConnectionRequestID == connectionRequestID','"sessionkey"']:
    assert x in s,x
p.write_text(s,encoding='utf-8')
print('foreground 4b41 transform PASS')
