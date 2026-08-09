import Foundation
import Testing

@Suite("ES80 Capture field runtime rendezvous")
struct ES80CaptureFieldRuntimeRendezvousTests {
    private static func appSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraApp.swift"),
            encoding: .utf8
        )
    }

    private static func preflightSource(_ source: String) throws -> Substring {
        let start = try #require(
            source.range(of: "private struct ES80ExperimentOneStationaryPreflightView: View")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "private struct ES80ExperimentOneFieldNoGoView: View",
                range: start..<source.endIndex
            )?.lowerBound
        )
        return source[start..<end]
    }

    @Test("authorized preflight exposes the package-owned runtime rendezvous before OFF 1")
    func authorizedPreflightShowsExactResearchTuple() throws {
        let preflight = try Self.preflightSource(Self.appSource())

        #expect(preflight.contains("coordinator.status.fieldExecutionStatus"))
        #expect(preflight.contains("case let .goPrivateResearchBuild(build)"))
        #expect(preflight.contains("PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue"))
        #expect(preflight.contains("build.buildIdentifier"))
        #expect(preflight.contains("build.sourceCommitSHA"))
        #expect(preflight.contains("build.buildInstanceID"))
        #expect(preflight.contains("es80.capture.preflight.field-rendezvous"))
        #expect(preflight.contains("es80.capture.preflight.field-build-identifier"))
        #expect(preflight.contains("es80.capture.preflight.field-source-sha"))
        #expect(preflight.contains("es80.capture.preflight.field-build-instance"))
        #expect(preflight.contains("es80.capture.preflight.field-recipe"))
        #expect(preflight.contains("Final GO is still required"))
    }

    @Test("preflight rendezvous does not mint or reread authority in the app")
    func preflightConsumesCoordinatorAuthorityOnly() throws {
        let preflight = try Self.preflightSource(Self.appSource())

        #expect(!preflight.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader"))
        #expect(!preflight.contains("ResearchBuild("))
        #expect(!preflight.contains("permitsPhysicalProcedure = true"))
        #expect(preflight.contains("hasAcceptedPreflightAuthority"))
        #expect(preflight.contains("selectedChargerState?.rawValue"))
    }

    @Test("synthetic Simulator preflight remains non-authorizing")
    func simulatorFixtureDoesNotPretendToBeResearchAdmission() throws {
        let preflight = try Self.preflightSource(Self.appSource())

        #expect(preflight.contains("if simulatorQASnapshot != nil"))
        #expect(preflight.contains("return true"))
        #expect(preflight.contains("case .noGo:"))
        #expect(preflight.contains("return nil"))
    }

    @Test("preflight accessibility distinguishes synthetic Simulator authority from a Research Field Build")
    func accessibilityHintPreservesAuthorityBoundary() throws {
        let preflight = try Self.preflightSource(Self.appSource())

        #expect(preflight.contains("preflightContinueAccessibilityHint"))
        #expect(preflight.contains("Simulator QA only. Select Charger Disconnected to continue through synthetic software setup. This does not authorize physical scooter capture."))
        #expect(preflight.contains("this running build has package-owned research authority"))
    }
}
