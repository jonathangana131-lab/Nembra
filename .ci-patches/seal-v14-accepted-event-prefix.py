from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift")
source = APP.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    source = source.replace(old, new, 1)


replace_once(
    "    private var events: [Event] = []\n    private var watchdog: Task<Void, Never>?",
    "    private var events: [Event] = []\n    // Immutable app-side export prefix captured synchronously after the package seal.\n    // Post-seal callback diagnostics may continue in `events` but cannot rewrite accepted evidence.\n    private var sealedAcceptedEventPrefix: [Event]?\n    private var watchdog: Task<Void, Never>?",
    "sealed prefix storage",
)
replace_once(
    "                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        self.currentConnectionToken = nil\n                        await self.refreshLedgerSnapshot()",
    "                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        // Freeze before the next suspension point. Delayed callbacks can append only\n                        // to the live diagnostic log after this exact accepted prefix is captured.\n                        self.sealedAcceptedEventPrefix = self.events\n                        self.currentConnectionToken = nil\n                        await self.refreshLedgerSnapshot()",
    "synchronous accepted prefix freeze",
)
replace_once(
    "    func prepareExport() {\n        let envelope = Export(",
    '''    func prepareExport() {
        let exportEvents: [Event]
        if phase == .accepted {
            guard let sealedAcceptedEventPrefix else {
                exportData = nil
                message = "Accepted evidence export is blocked because the immutable app event prefix is unavailable. Preserve diagnostics and relaunch before another attempt."
                return
            }
            exportEvents = sealedAcceptedEventPrefix
        } else {
            exportEvents = events
        }

        let envelope = Export(''',
    "accepted export selector",
)
replace_once(
    "            candidates: candidates,\n            events: events\n        )",
    "            candidates: candidates,\n            events: exportEvents\n        )",
    "export frozen events",
)
replace_once(
    "        targetCorrelationOperatorConfirmed = false\n        watchdog?.cancel()",
    "        targetCorrelationOperatorConfirmed = false\n        sealedAcceptedEventPrefix = nil\n        watchdog?.cancel()",
    "fresh correlation clears accepted prefix",
)
APP.write_text(source)

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted application evidence export seal")
struct TuyaAcceptedApplicationEvidenceSealSourceTests {
    @Test("successful package seal freezes exportable events before the next suspension point")
    func acceptanceSealFreezesExportPrefixSynchronously() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let seal = try section(
            in: String(watchdog),
            from: "try await sessionLedger.sealAcceptedObservation(for: token)",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed"
        )
        let body = String(seal)
        guard let packageSeal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)"),
              let frozenPrefix = body.range(of: "self.sealedAcceptedEventPrefix = self.events", range: packageSeal.upperBound..<body.endIndex) else {
            Issue.record("Successful package seal must synchronously snapshot the accepted app event prefix.")
            throw SourceContractError.sectionMissing
        }
        if let nextAwait = body.range(of: "await ", range: packageSeal.upperBound..<body.endIndex) {
            #expect(frozenPrefix.lowerBound < nextAwait.lowerBound)
        }
    }

    @Test("accepted export consumes frozen events while diagnostic preflight export can use live events")
    func acceptedExportUsesFrozenEventPrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("private var sealedAcceptedEventPrefix: [Event]?"))
        let export = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")
        let body = String(export)
        #expect(body.contains("if phase == .accepted"))
        #expect(body.contains("exportEvents = sealedAcceptedEventPrefix"))
        #expect(body.contains("events: exportEvents"))
        #expect(!body.contains("events: events\n"))
    }

    @Test("fresh correlation life clears the prior accepted prefix")
    func freshCorrelationClearsPriorAcceptedPrefix() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(in: app, from: "private func resetDiscoverySessionOnly()", to: "private func failLocally")
        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
''')

final = APP.read_text()
for marker in (
    "private var sealedAcceptedEventPrefix: [Event]?",
    "self.sealedAcceptedEventPrefix = self.events",
    "exportEvents = sealedAcceptedEventPrefix",
    "events: exportEvents",
    "sealedAcceptedEventPrefix = nil",
):
    if marker not in final:
        raise SystemExit(f"missing accepted evidence marker: {marker}")

seal_start = final.index("try await sessionLedger.sealAcceptedObservation(for: token)")
freeze = final.index("self.sealedAcceptedEventPrefix = self.events", seal_start)
next_await = final.find("await ", seal_start + len("try await sessionLedger.sealAcceptedObservation(for: token)"))
if next_await != -1 and not freeze < next_await:
    raise SystemExit("accepted event prefix is not frozen before the next suspension point")

print("accepted application evidence export prefix sealed")
