from pathlib import Path

root = Path(__file__).resolve().parents[2]
app_path = root / "NembraApp/App/NembraCaptureEntrypoint.swift"
test_path = root / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaBidirectionalBLEOwnershipLeaseSourceTests.swift"
app = app_path.read_text(encoding="utf-8")
test = test_path.read_text(encoding="utf-8")

old = '''        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
'''
new = '''        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
            releasePackageCorrelationOwnership()
        }
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
'''
if app.count(old) != 1:
    raise SystemExit(f"membership invalidation anchor count: {app.count(old)}")
app = app.replace(old, new, 1)

old_test = '''        let finish = try section(in: source, from: "private func finishCorrelationSeries", to: "func confirmCorrelatedTarget")
        #expect(finish.contains("releasePackageCorrelationOwnership()"))
        let failure = try section(in: source, from: "private func failLocally", to: "private func log")
        #expect(failure.contains("releasePackageCorrelationOwnership()"))
'''
new_test = '''        let finish = try section(in: source, from: "private func finishCorrelationSeries", to: "func confirmCorrelatedTarget")
        #expect(finish.contains("releasePackageCorrelationOwnership()"))
        let membershipInvalidation = try section(in: source, from: "func invalidateSDKMembership()", to: "func verifySDKMembership")
        let abandon = membershipInvalidation.range(of: "correlationSession?.abandonCurrentWindow()")
        let release = membershipInvalidation.range(of: "releasePackageCorrelationOwnership()")
        #expect(abandon != nil)
        #expect(release != nil)
        if let abandon, let release {
            #expect(abandon.lowerBound < release.lowerBound)
        }
        let failure = try section(in: source, from: "private func failLocally", to: "private func log")
        #expect(failure.contains("releasePackageCorrelationOwnership()"))
'''
if test.count(old_test) != 1:
    raise SystemExit(f"test anchor count: {test.count(old_test)}")
test = test.replace(old_test, new_test, 1)

app_path.write_text(app, encoding="utf-8")
test_path.write_text(test, encoding="utf-8")
print("Capture bidirectional lease membership-release repair: PASS")
