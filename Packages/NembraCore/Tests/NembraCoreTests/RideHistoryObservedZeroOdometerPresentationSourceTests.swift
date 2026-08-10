import Foundation
import Testing
@testable import NembraCore

@Suite("Ride History observed-zero odometer presentation")
struct RideHistoryObservedZeroOdometerPresentationSourceTests {
    @Test("completed ride evidence preserves an explicitly observed zero odometer delta")
    func completedEvidencePreservesObservedZeroOdometerDelta() throws {
        let evidence = try CompletedRideEvidence(
            sessionID: UUID(),
            beganAtDate: Date(timeIntervalSinceReferenceDate: 1),
            confirmedAtDate: Date(timeIntervalSinceReferenceDate: 2),
            endedAtDate: Date(timeIntervalSinceReferenceDate: 3),
            startingOdometerKilometers: 231.4,
            endingOdometerKilometers: 231.4,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
        )

        let start = try #require(evidence.startingOdometerKilometers)
        let end = try #require(evidence.endingOdometerKilometers)
        #expect(end - start == 0)
    }

    @Test("Ride History must not erase observed zero odometer evidence")
    func rideHistoryMustNotEraseObservedZeroOdometerEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/AppRootView.swift")

        // Both RideHistoryRowView and RideHistoryDetailView independently project
        // the same immutable completed-ride odometer pair. Equality is legitimate
        // observed zero evidence; only regression below start is invalid upstream.
        let strictPositiveGuards = source.components(separatedBy: "end > start").count - 1
        #expect(strictPositiveGuards == 0)

        let nonRegressingGuards = source.components(separatedBy: "end >= start").count - 1
        #expect(nonRegressingGuards >= 2)
    }

    @Test("GPS zero remains separate from observed odometer zero")
    func gpsZeroRemainsSeparateFromObservedOdometerZero() throws {
        let source = try readRepositoryFile("NembraApp/App/AppRootView.swift")

        // The current persisted GPS scalar cannot distinguish an observed zero
        // accumulation from no usable GPS contribution. This regression therefore
        // changes only odometer-pair handling and must not promote GPS zero.
        #expect(source.contains("qualityScreenedGPSDistanceMeters > 0"))
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
}
