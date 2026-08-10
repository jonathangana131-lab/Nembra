from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift")

app = APP.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global app
    if app.count(old) != 1:
        raise SystemExit(f"{label}: expected one anchor, found {app.count(old)}")
    app = app.replace(old, new, 1)


replace_once(
    "    private var driver: OfficialTuyaDriver?\n    private var events: [Event] = []\n    private var sealedAcceptedEventPrefix: [Event]?\n",
    "    private var driver: OfficialTuyaDriver?\n    private var events: [Event] = []\n    private var captureAttemptEventStartIndex = 0\n    private var sealedAcceptedEventPrefix: [Event]?\n",
    "current capture attempt event boundary storage",
)

replace_once(
    "        // Every physical attempt receives a fresh complete current-account membership verdict\n        // before the package-owned four-window Bluetooth correlation series may start.\n        verifySDKMembership { [weak self] authorized in\n",
    "        // Start a new app-owned diagnostic/evidence lifetime before membership verification so\n        // retries cannot leak older correlation/authentication events into a later accepted export.\n        captureAttemptEventStartIndex = events.count\n        sealedAcceptedEventPrefix = nil\n\n        // Every physical attempt receives a fresh complete current-account membership verdict\n        // before the package-owned four-window Bluetooth correlation series may start.\n        verifySDKMembership { [weak self] authorized in\n",
    "attempt event boundary activation",
)

replace_once(
    "                    self.acceptanceSealInProgress = true\n                    do {\n                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.sealedAcceptedEventPrefix = self.events\n",
    "                    self.acceptanceSealInProgress = true\n                    // Snapshot the current attempt before the package-seal suspension. Callbacks that\n                    // arrive while sealing are diagnostic-only and must not enter accepted evidence.\n                    let eventsAtSealBarrier = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))\n                    do {\n                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.sealedAcceptedEventPrefix = eventsAtSealBarrier\n",
    "pre-suspension current-attempt event barrier",
)

APP.write_text(app)

tests = TEST.read_text()
anchor = "\n    private func section(in source: String, from start: String, to end: String) throws -> Substring {\n"
if tests.count(anchor) != 1:
    raise SystemExit("test helper anchor changed")
addition = r'''
    @Test("accepted prefix snapshots the current attempt before the package-seal suspension")
    func acceptedPrefixUsesPreSuspensionCurrentAttemptBarrier() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let latch = body.range(of: "acceptanceSealInProgress = true"),
              let barrier = body.range(of: "let eventsAtSealBarrier = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))", range: latch.upperBound..<body.endIndex),
              let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: barrier.upperBound..<body.endIndex),
              let frozen = body.range(of: "sealedAcceptedEventPrefix = eventsAtSealBarrier", range: packageSeal.upperBound..<body.endIndex) else {
            Issue.record("Accepted event custody must snapshot the current attempt before suspension and publish that exact snapshot only after package seal succeeds.")
            throw SourceContractError.sectionMissing
        }

        #expect(latch.lowerBound < barrier.lowerBound)
        #expect(barrier.lowerBound < packageSeal.lowerBound)
        #expect(packageSeal.lowerBound < frozen.lowerBound)
    }

    @Test("a new physical attempt advances the event boundary before membership verification")
    func newAttemptCannotExportOlderLifecycleEvents() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let start = try section(in: app, from: "func startBaseline()", to: "private func beginCorrelationSeries")
        let body = String(start)

        guard let boundary = body.range(of: "captureAttemptEventStartIndex = events.count"),
              let membership = body.range(of: "verifySDKMembership", range: boundary.upperBound..<body.endIndex) else {
            Issue.record("A fresh physical attempt must establish its app-owned event boundary before membership/correlation evidence begins.")
            throw SourceContractError.sectionMissing
        }
        #expect(boundary.lowerBound < membership.lowerBound)
        #expect(app.contains("private var captureAttemptEventStartIndex = 0"))
    }
'''
tests = tests.replace(anchor, "\n" + addition + anchor, 1)
TEST.write_text(tests)

app = APP.read_text()
start = app[app.index("func startBaseline()"):app.index("private func beginCorrelationSeries")]
assert start.index("captureAttemptEventStartIndex = events.count") < start.index("verifySDKMembership")
watchdog = app[app.index("private func startWatchdog"):app.index("private func recordObservedTransportLoss")]
latch = watchdog.index("acceptanceSealInProgress = true")
barrier = watchdog.index("let eventsAtSealBarrier = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))", latch)
seal = watchdog.index("try await sessionLedger.sealAcceptedObservation(for: token)", barrier)
frozen = watchdog.index("sealedAcceptedEventPrefix = eventsAtSealBarrier", seal)
assert latch < barrier < seal < frozen
