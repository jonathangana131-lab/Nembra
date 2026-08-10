from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift")

app = APP.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global app
    count = app.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    app = app.replace(old, new, 1)


replace_once(
    "    private var driver: OfficialTuyaDriver?\n    private var events: [Event] = []\n    private var applicationUpdateAdmissionsInFlight = 0\n",
    "    private var driver: OfficialTuyaDriver?\n    private var events: [Event] = []\n    private var captureAttemptEventStartIndex = 0\n    private var applicationUpdateAdmissionsInFlight = 0\n",
    "capture attempt event boundary storage",
)

replace_once(
    "        // Every physical attempt receives a fresh complete current-account membership verdict\n        // before the package-owned four-window Bluetooth correlation series may start.\n        verifySDKMembership { [weak self] authorized in\n",
    "        // Accepted app evidence belongs to this physical attempt only. The controller's\n        // diagnostic log intentionally survives failures for troubleshooting, so establish an\n        // explicit custody boundary before fresh membership/correlation evidence can begin.\n        captureAttemptEventStartIndex = events.count\n        sealedAcceptedEventPrefix = nil\n\n        // Every physical attempt receives a fresh complete current-account membership verdict\n        // before the package-owned four-window Bluetooth correlation series may start.\n        verifySDKMembership { [weak self] authorized in\n",
    "fresh physical attempt boundary",
)

replace_once(
    "                    self.acceptanceCutIsClosed = true\n                    let acceptedEventPrefixAtCut = self.events\n                    do {\n",
    "                    self.acceptanceCutIsClosed = true\n                    // Freeze only the current physical attempt. Older failed-attempt diagnostics stay\n                    // available in the live controller log but cannot contaminate accepted evidence.\n                    let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))\n                    do {\n",
    "current-attempt accepted prefix freeze",
)

APP.write_text(app)

tests = TEST.read_text()
old_freeze = 'let frozenPrefix = body.range(of: "let acceptedEventPrefixAtCut = self.events", range: closeCut.upperBound..<body.endIndex),'
new_freeze = 'let frozenPrefix = body.range(of: "let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))", range: closeCut.upperBound..<body.endIndex),'
if tests.count(old_freeze) != 1:
    raise SystemExit("existing freeze contract anchor changed")
tests = tests.replace(old_freeze, new_freeze, 1)

anchor = "\n    private func section(in source: String, from start: String, to end: String) throws -> Substring {\n"
if tests.count(anchor) != 1:
    raise SystemExit("test helper anchor changed")
addition = r'''
    @Test("accepted export starts at the current physical attempt boundary")
    func acceptedExportCannotInheritOlderFailedAttemptEvents() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let start = try section(in: app, from: "func startBaseline()", to: "private func beginCorrelationSeries")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let startBody = String(start)
        let watchdogBody = String(watchdog)

        guard let boundary = startBody.range(of: "captureAttemptEventStartIndex = events.count"),
              let membership = startBody.range(of: "verifySDKMembership", range: boundary.upperBound..<startBody.endIndex),
              let closeCut = watchdogBody.range(of: "self.acceptanceCutIsClosed = true"),
              let freeze = watchdogBody.range(of: "let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))", range: closeCut.upperBound..<watchdogBody.endIndex),
              let packageSeal = watchdogBody.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: freeze.upperBound..<watchdogBody.endIndex) else {
            Issue.record("Accepted evidence must establish a fresh-attempt boundary before membership and freeze only that suffix before package seal.")
            throw SourceContractError.sectionMissing
        }

        #expect(app.contains("private var captureAttemptEventStartIndex = 0"))
        #expect(boundary.lowerBound < membership.lowerBound)
        #expect(closeCut.lowerBound < freeze.lowerBound)
        #expect(freeze.lowerBound < packageSeal.lowerBound)
    }
'''
tests = tests.replace(anchor, "\n" + addition + anchor, 1)
TEST.write_text(tests)

# Portable source contract. Apple-framework compilation/runtime remains the exact-head Xcode gate.
app = APP.read_text()
start = app[app.index("func startBaseline()"):app.index("private func beginCorrelationSeries")]
assert start.index("captureAttemptEventStartIndex = events.count") < start.index("verifySDKMembership")
watchdog = app[app.index("private func startWatchdog"):app.index("private func recordObservedTransportLoss")]
cut = watchdog.index("self.acceptanceCutIsClosed = true")
freeze = watchdog.index("let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))", cut)
seal = watchdog.index("try await sessionLedger.sealAcceptedObservation(for: token)", freeze)
assert cut < freeze < seal
assert "guard self.applicationUpdateAdmissionsInFlight == 0" in watchdog
assert "guard !acceptanceCutIsClosed" in app
assert "func consumeCorrelationAsyncInvalidation()" in app
