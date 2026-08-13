import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture app incomplete observation handling")
struct TuyaIncompleteObservationHorizonAppSourceTests {
    @Test("application receipt has typed incomplete-horizon handling")
    func applicationReceiptHasTypedHandling() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let body = try catchBody(
            in: app,
            functionStart: "private func receivedApplicationUpdate",
            errorCase: "MutationError.incompleteObservationHorizonReached"
        )
        #expect(body.contains("message:"))
        #expect(body.contains("kind:"))
    }

    @Test("watchdog has typed incomplete-horizon handling")
    func watchdogHasTypedHandling() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let body = try catchBody(
            in: String(watchdog),
            functionStart: "sessionLedger.observeCurrentConnection(for: token)",
            errorCase: "MutationError.incompleteObservationHorizonReached"
        )
        #expect(body.contains("message:"))
        #expect(body.contains("kind:"))
    }

    private func catchBody(in source: String, functionStart: String, errorCase: String) throws -> Substring {
        guard let functionRange = source.range(of: functionStart),
              let catchRange = source.range(
                of: "catch TuyaAuthenticatedReadOnlySessionLedger.\(errorCase) {",
                range: functionRange.lowerBound..<source.endIndex
              ),
              let nextCatch = source.range(of: "} catch", range: catchRange.upperBound..<source.endIndex) else {
            Issue.record("Expected typed catch missing: \(errorCase)")
            throw SourceContractError.sectionMissing
        }
        return source[catchRange.lowerBound..<nextCatch.lowerBound]
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
