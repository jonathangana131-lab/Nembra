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
    "    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }\n    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n",
    "    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }\n    private func acceptedApplicationEventCount(for token: TuyaReadOnlyConnectionToken) -> Int {\n        let generation = String(token.diagnosticGeneration)\n        return events.lazy.filter {\n            $0.kind == \"tuya_application_update\" && $0.details[\"generation\"] == generation\n        }.count\n    }\n    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n",
    "generation-scoped structured evidence count",
)

replace_once(
    "            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n            await refreshLedgerSnapshot()\n            log(\"tuya_application_update\", update.merging([\n                \"generation\": String(token.diagnosticGeneration)\n            ]) { current, _ in current })\n",
    "            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n            // The package must admit the receipt before its structured values enter accepted\n            // evidence. Once admitted, copy them before this MainActor task suspends again.\n            log(\"tuya_application_update\", update.merging([\n                \"generation\": String(token.diagnosticGeneration)\n            ]) { current, _ in current })\n            await refreshLedgerSnapshot()\n",
    "accepted structured update chronology",
)

replace_once(
    "                case .readyForStationaryMapping:\n                    guard self.buildIdentity.isAuthoritativeFieldBuild else {\n",
    "                case .readyForStationaryMapping:\n                    // The ledger actor can admit an application receipt before the corresponding\n                    // MainActor continuation copies its structured values into `events`. A ready\n                    // ledger snapshot therefore cannot seal until the current generation's\n                    // structured evidence count has caught up exactly.\n                    guard self.acceptedApplicationEventCount(for: token) == self.applicationUpdateCount else {\n                        self.message = \"Synchronizing accepted application evidence before canonical seal…\"\n                        break\n                    }\n                    guard self.buildIdentity.isAuthoritativeFieldBuild else {\n",
    "canonical seal parity fence",
)

APP.write_text(app)

tests = TEST.read_text()
anchor = "\n    private func section(in source: String, from start: String, to end: String) throws -> Substring {\n"
if tests.count(anchor) != 1:
    raise SystemExit("test helper anchor changed")
addition = r'''
    @Test("package-admitted structured values are copied before the callback suspends again")
    func acceptedApplicationValuesAreCopiedBeforeNextSuspension() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receive = try section(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        )
        let body = String(receive)

        guard let admission = body.range(of: "try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)"),
              let valueLog = body.range(of: "log(\"tuya_application_update\"", range: admission.upperBound..<body.endIndex),
              let nextAwait = body.range(of: "await ", range: admission.upperBound..<body.endIndex) else {
            Issue.record("Accepted application-value chronology anchors are missing.")
            throw SourceContractError.sectionMissing
        }

        #expect(valueLog.lowerBound < nextAwait.lowerBound)
    }

    @Test("canonical seal waits for current-generation structured evidence parity")
    func canonicalSealRequiresCurrentGenerationStructuredEvidenceParity() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let body = String(watchdog)

        guard let readyCase = body.range(of: "case .readyForStationaryMapping:"),
              let parity = body.range(of: "acceptedApplicationEventCount(for: token) == self.applicationUpdateCount", range: readyCase.upperBound..<body.endIndex),
              let seal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: readyCase.upperBound..<body.endIndex) else {
            Issue.record("Canonical seal must prove current-generation structured evidence parity first.")
            throw SourceContractError.sectionMissing
        }

        #expect(parity.lowerBound < seal.lowerBound)
        #expect(app.contains("$0.kind == \"tuya_application_update\" && $0.details[\"generation\"] == generation"))
    }
'''
tests = tests.replace(anchor, "\n" + addition + anchor, 1)
TEST.write_text(tests)

# Portable source contract used by the branch materializer. Apple-framework compilation and runtime
# are deliberately left to the exact-head Xcode 27 acceptance workflow.
app = APP.read_text()
receive = app[app.index("private func receivedApplicationUpdate("):app.index("private func startWatchdog")]
admission = receive.index("try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)")
value_log = receive.index('log("tuya_application_update"', admission)
next_await = receive.index("await ", admission + len("try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)"))
assert value_log < next_await

watchdog = app[app.index("private func startWatchdog"):app.index("private func recordObservedTransportLoss")]
ready = watchdog.index("case .readyForStationaryMapping:")
parity = watchdog.index("acceptedApplicationEventCount(for: token) == self.applicationUpdateCount", ready)
seal = watchdog.index("try await sessionLedger.sealAcceptedObservation(for: token)", ready)
assert parity < seal
assert '$0.kind == "tuya_application_update" && $0.details["generation"] == generation' in app
