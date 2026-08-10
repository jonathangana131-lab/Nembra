import Foundation
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
