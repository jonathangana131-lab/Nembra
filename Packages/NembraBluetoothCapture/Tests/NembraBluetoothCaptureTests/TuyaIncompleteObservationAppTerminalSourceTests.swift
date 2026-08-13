import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture app incomplete-observation terminal integration")
struct TuyaIncompleteObservationAppTerminalSourceTests {
    @Test("real app classifies the package incomplete horizon explicitly at both admission sites")
    func incompleteHorizonDoesNotFallThroughGenericLifecycleFailure() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let explicitCatch = "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached"
        let explicitCatchCount = source.components(separatedBy: explicitCatch).count - 1

        // Both package entry points can throw this expected physical-preflight terminal:
        // application-payload admission and watchdog liveness admission. Neither may fall through
        // the generic internal-lifecycle classifier, which would mislabel a bounded observation
        // outcome as an internal chronology failure.
        #expect(explicitCatchCount >= 2)
        #expect(source.contains("markApplicationObservationTimedOut(for: token)"))
    }

    @Test("package-owned deadline remains the authoritative 60 second observation boundary")
    func appDoesNotReplaceTheCanonicalDeadlineWithASecondAcceptanceClock() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds"))
        #expect(source.contains("sessionLedger.observeCurrentConnection(for: token)"))
        #expect(source.contains("sessionLedger.recordApplicationUpdate(isNonEmpty:"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
