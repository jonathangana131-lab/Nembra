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
    "    private var sealedAcceptedEventPrefix: [Event]?\n    private var watchdog: Task<Void, Never>?\n",
    "    private var sealedAcceptedEventPrefix: [Event]?\n    private var applicationAdmissionInFlightCount = 0\n    private var acceptanceSealInProgress = false\n    private var watchdog: Task<Void, Never>?\n",
    "application admission/seal latch storage",
)

replace_once(
    "        guard driver.isLocallyConnected(uuid: tuyaUUID) else {\n            await recordObservedTransportLoss(token: token)\n            return\n        }\n\n        do {\n            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n",
    "        guard driver.isLocallyConnected(uuid: tuyaUUID) else {\n            await recordObservedTransportLoss(token: token)\n            return\n        }\n        guard !acceptanceSealInProgress else {\n            log(\"application_update_during_acceptance_seal_ignored\", [\n                \"generation\": String(token.diagnosticGeneration)\n            ])\n            return\n        }\n\n        // MainActor serialization makes the guard + increment atomic with respect to the watchdog.\n        // The counter stays non-zero across every suspension in this handler, so canonical sealing\n        // cannot overtake a package-admitted receipt whose structured values are not settled yet.\n        applicationAdmissionInFlightCount += 1\n        defer { applicationAdmissionInFlightCount -= 1 }\n\n        do {\n            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n",
    "application admission latch",
)

replace_once(
    "                    // The ledger actor can admit an application receipt before the corresponding\n                    // MainActor continuation copies its structured values into `events`. A ready\n                    // ledger snapshot therefore cannot seal until the current generation's\n                    // structured evidence count has caught up exactly.\n                    guard self.acceptedApplicationEventCount(for: token) == self.applicationUpdateCount else {\n                        self.message = \"Synchronizing accepted application evidence before canonical seal…\"\n                        break\n                    }\n                    guard self.buildIdentity.isAuthoritativeFieldBuild else {\n",
    "                    // The ledger actor can admit an application receipt before the corresponding\n                    // MainActor continuation copies its structured values into `events`. A ready\n                    // ledger snapshot therefore cannot seal until no admission is in flight and the\n                    // current generation's structured evidence count has caught up exactly.\n                    guard self.applicationAdmissionInFlightCount == 0 else {\n                        self.message = \"Settling accepted application evidence before canonical seal…\"\n                        break\n                    }\n                    guard self.acceptedApplicationEventCount(for: token) == self.applicationUpdateCount else {\n                        self.message = \"Synchronizing accepted application evidence before canonical seal…\"\n                        break\n                    }\n                    guard self.buildIdentity.isAuthoritativeFieldBuild else {\n",
    "in-flight seal fence",
)

replace_once(
    "                    do {\n                        try await sessionLedger.sealAcceptedObservation(for: token)\n",
    "                    // Close application admission synchronously on MainActor before the seal await.\n                    // New SDK callbacks may remain diagnostic, but they cannot race a ledger mutation\n                    // against the package-owned immutable horizon.\n                    self.acceptanceSealInProgress = true\n                    do {\n                        try await sessionLedger.sealAcceptedObservation(for: token)\n",
    "seal latch activation",
)

replace_once(
    "    private func resetDiscoverySessionOnly() {\n        sealedAcceptedEventPrefix = nil\n",
    "    private func resetDiscoverySessionOnly() {\n        sealedAcceptedEventPrefix = nil\n        acceptanceSealInProgress = false\n",
    "fresh life seal latch reset",
)

APP.write_text(app)

tests = TEST.read_text()
anchor = "\n    private func section(in source: String, from start: String, to end: String) throws -> Substring {\n"
if tests.count(anchor) != 1:
    raise SystemExit("test helper anchor changed")
addition = r'''
    @Test("canonical seal closes new application admission before awaiting package seal")
    func canonicalSealUsesMainActorAdmissionLatch() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = try section(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        )
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let receiveBody = String(receive)
        let watchdogBody = String(watchdog)

        guard let sealGuard = receiveBody.range(of: "guard !acceptanceSealInProgress else"),
              let increment = receiveBody.range(of: "applicationAdmissionInFlightCount += 1"),
              let record = receiveBody.range(of: "try await sessionLedger.recordApplicationUpdate", range: increment.upperBound..<receiveBody.endIndex) else {
            Issue.record("Application admission must be latched before package mutation.")
            throw SourceContractError.sectionMissing
        }
        #expect(sealGuard.lowerBound < increment.lowerBound)
        #expect(increment.lowerBound < record.lowerBound)
        #expect(receiveBody.contains("defer { applicationAdmissionInFlightCount -= 1 }"))

        guard let readyCase = watchdogBody.range(of: "case .readyForStationaryMapping:"),
              let inFlightFence = watchdogBody.range(of: "applicationAdmissionInFlightCount == 0", range: readyCase.upperBound..<watchdogBody.endIndex),
              let latch = watchdogBody.range(of: "acceptanceSealInProgress = true", range: inFlightFence.upperBound..<watchdogBody.endIndex),
              let packageSeal = watchdogBody.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: latch.upperBound..<watchdogBody.endIndex) else {
            Issue.record("Canonical seal must fence in-flight admission and close the latch before awaiting package seal.")
            throw SourceContractError.sectionMissing
        }
        #expect(inFlightFence.lowerBound < latch.lowerBound)
        #expect(latch.lowerBound < packageSeal.lowerBound)
    }

    @Test("fresh correlation life reopens application admission only after the prior life is retired")
    func freshCorrelationResetsSealLatch() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        )
        #expect(reset.contains("acceptanceSealInProgress = false"))
    }
'''
tests = tests.replace(anchor, "\n" + addition + anchor, 1)
TEST.write_text(tests)

app = APP.read_text()
receive = app[app.index("private func receivedApplicationUpdate("):app.index("private func startWatchdog")]
watchdog = app[app.index("private func startWatchdog"):app.index("private func recordObservedTransportLoss")]
assert receive.index("guard !acceptanceSealInProgress else") < receive.index("applicationAdmissionInFlightCount += 1") < receive.index("try await sessionLedger.recordApplicationUpdate")
assert "defer { applicationAdmissionInFlightCount -= 1 }" in receive
ready = watchdog.index("case .readyForStationaryMapping:")
in_flight = watchdog.index("applicationAdmissionInFlightCount == 0", ready)
parity = watchdog.index("acceptedApplicationEventCount(for: token) == self.applicationUpdateCount", ready)
latch = watchdog.index("acceptanceSealInProgress = true", parity)
seal = watchdog.index("try await sessionLedger.sealAcceptedObservation(for: token)", latch)
assert in_flight < parity < latch < seal
