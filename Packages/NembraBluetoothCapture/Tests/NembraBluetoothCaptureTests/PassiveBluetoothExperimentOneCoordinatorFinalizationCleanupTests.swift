import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One coordinator finalization cleanup truth")
struct PassiveBluetoothExperimentOneCoordinatorFinalizationCleanupTests {
    private typealias Coordinator = PassiveBluetoothExperimentOneCoordinator

    private static func coordinatorSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneCoordinator.swift"),
            encoding: .utf8
        )
    }

    @Test("fresh coordinator exposes cleanup as not attempted")
    @MainActor
    func initialCleanupStatusIsExplicit() throws {
        let coordinator = try Coordinator()
        #expect(coordinator.status.finalizationCleanup == .notAttempted)
        #expect(coordinator.finalizedArtifact == nil)
    }

    @Test("sealed artifact is published before fallible cleanup and cleanup is never try-question suppressed")
    func finalizationKeepsArtifactAndCleanupTruthSeparate() throws {
        let source = try Self.coordinatorSource()
        let start = try #require(
            source.range(of: "    public func finalizeObservationHorizon() async throws")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "    /// Destructive safety paths remain available",
                range: start..<source.endIndex
            )?.lowerBound
        )
        let finalization = source[start..<end]

        let artifactPublication = try #require(
            finalization.range(of: "finalizedArtifactStorage = artifact")
        )
        let cleanup = try #require(
            finalization.range(of: "try controller.teardownActiveConnectionAfterFinalization()")
        )
        let success = try #require(
            finalization.range(of: "finalizationCleanupStatusStorage = .complete")
        )
        let failure = try #require(
            finalization.range(of: "finalizationCleanupStatusStorage = .failed")
        )

        #expect(artifactPublication.lowerBound < cleanup.lowerBound)
        #expect(cleanup.lowerBound < success.lowerBound)
        #expect(success.lowerBound < failure.lowerBound)
        #expect(!finalization.contains("try? controller.teardownActiveConnectionAfterFinalization()"))
        #expect(!finalization.contains("finalizedArtifactStorage = nil"))
    }

    @Test("cleanup status vocabulary cannot imply that cleanup failure invalidated the artifact")
    func cleanupStatusIsNarrow() throws {
        let source = try Self.coordinatorSource()
        let start = try #require(
            source.range(of: "    public enum FinalizationCleanupStatus")?.lowerBound
        )
        let end = try #require(
            source.range(of: "    public struct Status", range: start..<source.endIndex)?.lowerBound
        )
        let declaration = String(source[start..<end])

        #expect(declaration.contains("case notAttempted"))
        #expect(declaration.contains("case complete"))
        #expect(declaration.contains("case failed"))
        #expect(!declaration.localizedCaseInsensitiveContains("artifact failed"))
        #expect(!declaration.localizedCaseInsensitiveContains("seal failed"))
    }
}
