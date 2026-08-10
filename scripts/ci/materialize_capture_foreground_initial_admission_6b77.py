from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureForegroundIntegritySourceTests.swift")

app = APP.read_text(encoding="utf-8")
test = TEST.read_text(encoding="utf-8")

old_task = '''        .task {
            test.activateMembershipRequestsForView()
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
                test.consumeCorrelationAsyncInvalidation()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
'''
new_task = '''        .task {
            // SwiftUI may instantiate this view while the scene is already inactive/backgrounded.
            // Never open membership authority until the scene itself is active.
            if scenePhase == .active {
                test.activateMembershipRequestsForView()
            } else {
                test.appDidLoseForeground()
            }
            sdkAccount.bootstrap()
            if scenePhase == .active, sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
                test.consumeCorrelationAsyncInvalidation()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
'''
if app.count(old_task) != 1:
    raise SystemExit(f"Secure Link initial task anchor drifted: {app.count(old_task)}")
app = app.replace(old_task, new_task, 1)

old_assertions = '''        #expect(view.contains("@Environment(\\\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("test.appDidLoseForeground()"))
        #expect(view.contains("test.appDidRegainForeground()"))
'''
new_assertions = old_assertions + '''
        // Initial view construction is also a foreground boundary. A task that unconditionally
        // opens membership authority before scenePhase is known would recreate the hidden-start race.
        let initialTask = String(try section(in: view, from: ".task {", to: ".onDisappear {"))
        let activeGuard = try requiredOffset(containing: "if scenePhase == .active", in: initialTask)
        let admissionOpen = try requiredOffset(containing: "test.activateMembershipRequestsForView()", in: initialTask)
        #expect(activeGuard < admissionOpen)
        #expect(initialTask.contains("else {"))
        #expect(initialTask.contains("test.appDidLoseForeground()"))
        #expect(initialTask.contains("if scenePhase == .active, sdkAccount.loggedIn { test.verifySDKMembership() }"))
'''
if test.count(old_assertions) != 1:
    raise SystemExit(f"Foreground regression assertion anchor drifted: {test.count(old_assertions)}")
test = test.replace(old_assertions, new_assertions, 1)

# Preserve the stronger exact-current foreground contract.
for needle in (
    "private var lifecycleRetirementToken: TuyaReadOnlyConnectionToken?",
    "sdkDeviceMembershipVerified = false",
    "membershipAccountUID = nil",
    "membershipDeviceID = nil",
    "OfficialTuyaFactory.packageCorrelationMayStart",
    "Task { @MainActor [self] in",
    "Relaunch before another authenticated stationary read-only attempt",
    "invalidateObservationContinuity(",
    "invalidateInternalLifecycle(",
):
    if needle not in app:
        raise SystemExit(f"Required foreground invariant missing after initial-admission repair: {needle}")

APP.write_text(app, encoding="utf-8")
TEST.write_text(test, encoding="utf-8")
print("Capture foreground initial-admission fence: PASS")
