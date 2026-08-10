from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift")

app = APP.read_text()
old = '''    private var acceptedApplicationEventCount: Int {
        events.lazy.filter { $0.kind == "tuya_application_update" }.count
    }
'''
new = '''    private func acceptedApplicationEventCount(for token: TuyaReadOnlyConnectionToken) -> Int {
        let generation = String(token.diagnosticGeneration)
        return events.lazy.filter {
            $0.kind == "tuya_application_update" && $0.details["generation"] == generation
        }.count
    }
'''
if app.count(old) != 1:
    raise SystemExit("accepted application event counter anchor changed")
app = app.replace(old, new, 1)
old_guard = "guard self.acceptedApplicationEventCount == self.applicationUpdateCount else {"
new_guard = "guard self.acceptedApplicationEventCount(for: token) == self.applicationUpdateCount else {"
if app.count(old_guard) != 1:
    raise SystemExit("parity guard anchor changed")
app = app.replace(old_guard, new_guard, 1)
APP.write_text(app)

tests = TEST.read_text()
tests = tests.replace(
    'let parity = body.range(of: "acceptedApplicationEventCount == self.applicationUpdateCount", range: readyCase.upperBound..<body.endIndex),',
    'let parity = body.range(of: "acceptedApplicationEventCount(for: token) == self.applicationUpdateCount", range: readyCase.upperBound..<body.endIndex),',
    1,
)
tests = tests.replace(
    '#expect(app.contains("events.lazy.filter { $0.kind == \\"tuya_application_update\\" }.count"))',
    '#expect(app.contains("$0.kind == \\"tuya_application_update\\" && $0.details[\\"generation\\"] == generation"))',
    1,
)
if 'acceptedApplicationEventCount(for: token) == self.applicationUpdateCount' not in tests:
    raise SystemExit("generation-scoped parity test was not updated")
TEST.write_text(tests)

app = APP.read_text()
assert 'private func acceptedApplicationEventCount(for token: TuyaReadOnlyConnectionToken) -> Int' in app
assert '$0.kind == "tuya_application_update" && $0.details["generation"] == generation' in app
assert 'guard self.acceptedApplicationEventCount(for: token) == self.applicationUpdateCount else {' in app
