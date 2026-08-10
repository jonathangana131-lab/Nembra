import Foundation
import Testing

@Suite("ES80 Capture field runtime rendezvous")
struct ES80CaptureFieldRuntimeRendezvousTests {
    private static func captureSource() throws -> String {
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
                .appendingPathComponent("NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    @Test("authorized Capture exposes the exact stamped field rendezvous before OFF1")
    func authorizedCaptureShowsExactFieldTuple() throws {
        let source = try Self.captureSource()

        #expect(source.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(source.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(source.contains("var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }"))
        #expect(source.contains("var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }"))
        #expect(source.contains("var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }"))

        #expect(source.contains("LabeledContent(\"Build\", value: test.fieldBuildIdentifier)"))
        #expect(source.contains("LabeledContent(\"Source commit\", value: test.fieldBuildSourceCommitSHA)"))
        #expect(source.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(source.contains("requirementRow(\"Capture build\", ready: test.fieldBuildIsAuthoritative)"))

        let authority = try #require(source.range(of: "private var authorityReady: Bool"))
        let off1 = try #require(source.range(of: "Label(\"Start with scooter OFF\", systemImage: \"power\")"))
        #expect(authority.lowerBound < off1.lowerBound)
    }

    @Test("field rendezvous consumes stamped authority without minting a second runtime build authority")
    func rendezvousConsumesBuildIdentityOnly() throws {
        let source = try Self.captureSource()

        #expect(!source.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader"))
        #expect(!source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.ResearchBuild("))
        #expect(!source.contains("permitsPhysicalProcedure = true"))
        #expect(!source.contains("makeResearchAuthorizedES80ForCurrentApplication()"))

        let start = try #require(source.range(of: "func startBaseline()"))
        let buildGate = try #require(
            source.range(
                of: "guard buildIdentity.isAuthoritativeFieldBuild else",
                range: start.lowerBound..<source.endIndex
            )
        )
        let membership = try #require(
            source.range(
                of: "verifySDKMembership",
                range: buildGate.upperBound..<source.endIndex
            )
        )
        let begin = try #require(
            source.range(
                of: "self.beginCorrelationSeries()",
                range: membership.upperBound..<source.endIndex
            )
        )
        #expect(buildGate.lowerBound < membership.lowerBound)
        #expect(membership.lowerBound < begin.lowerBound)
    }

    @Test("synthetic Simulator fixtures cannot satisfy authenticated stationary admission")
    func simulatorFixtureCannotPretendToBeFieldAdmission() throws {
        let source = try Self.captureSource()

        #expect(!source.contains("simulatorQASnapshot"))
        #expect(!source.contains("PassiveBluetoothExperimentOneSimulatorQAFixture"))
        #expect(!source.contains("es80PassiveCaptureSimulatorQA"))

        #expect(source.contains("guard buildIdentity.isAuthoritativeFieldBuild else"))
        #expect(source.contains("guard privateConfig, sdkAccountLoggedIn else"))
        #expect(source.contains("TuyaSDKAccountIdentityLeaseGate.verdict"))
        #expect(source.contains("OfficialTuyaFactory.packageCorrelationMayStart"))
    }
}
