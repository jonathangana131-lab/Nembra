import Foundation
import Testing

@Suite("ES80 Capture field runtime rendezvous")
struct ES80CaptureFieldRuntimeRendezvousTests {
    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func fieldEntrypointSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    private static func buildIdentitySource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraCaptureBuildIdentity.swift"),
            encoding: .utf8
        )
    }

    @Test("authenticated preflight exposes the exact running-build rendezvous before OFF 1")
    func authenticatedPreflightShowsExactRunningBuildTuple() throws {
        let source = try Self.fieldEntrypointSource()

        #expect(source.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(source.contains("var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }"))
        #expect(source.contains("var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }"))
        #expect(source.contains("var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }"))
        #expect(source.contains("LabeledContent(\"Build\", value: test.fieldBuildIdentifier)"))
        #expect(source.contains("LabeledContent(\"Source commit\", value: test.fieldBuildSourceCommitSHA)"))
        #expect(source.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(source.contains("requirementRow(\"Capture build\", ready: test.fieldBuildIsAuthoritative)"))
        #expect(source.contains("if authorityReady {"))
        #expect(source.contains("test.startBaseline()"))
        #expect(source.contains("Label(\"Start with scooter OFF\", systemImage: \"power\")"))
    }

    @Test("field rendezvous consumes compiled build identity without minting replacement authority in the view")
    func rendezvousConsumesCurrentBuildIdentityOnly() throws {
        let source = try Self.fieldEntrypointSource()

        #expect(source.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(!source.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader"))
        #expect(!source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.ResearchBuild("))
        #expect(!source.contains("permitsPhysicalProcedure = true"))
        #expect(!source.contains("UserDefaults"))

        let start = try #require(source.range(of: "func startBaseline()"))
        let guardRange = try #require(
            source.range(
                of: "guard buildIdentity.isAuthoritativeFieldBuild else",
                range: start.lowerBound..<source.endIndex
            )
        )
        let configRange = try #require(
            source.range(
                of: "guard privateConfig, sdkAccountLoggedIn else",
                range: guardRange.upperBound..<source.endIndex
            )
        )
        #expect(start.lowerBound < guardRange.lowerBound)
        #expect(guardRange.lowerBound < configRange.lowerBound)
        #expect(source.contains("field_build_identity_unavailable"))
    }

    @Test("non-authoritative build remains mechanically locked before OFF 1")
    func nonAuthoritativeBuildCannotReachOFF1() throws {
        let source = try Self.fieldEntrypointSource()
        let identity = try Self.buildIdentitySource()

        let readyStart = try #require(source.range(of: "private var authorityReady: Bool {"))
        let readyEnd = try #require(
            source.range(
                of: "private var currentStageIndex: Int",
                range: readyStart.upperBound..<source.endIndex
            )
        )
        let ready = source[readyStart.lowerBound..<readyEnd.lowerBound]
        #expect(ready.contains("test.fieldBuildIsAuthoritative"))
        #expect(ready.contains("test.privateConfig"))
        #expect(ready.contains("test.sdkAccountLoggedIn"))
        #expect(ready.contains("test.sdkDeviceMembershipVerified"))
        #expect(ready.contains("test.accountIdentityLeaseIsAuthorized"))

        #expect(identity.contains("static let requiredFieldProcedureIdentifier = \"ES80-AUTHENTICATED-STATIONARY-v1\""))
        #expect(identity.contains("guard sourceCommitSHA.count == 40"))
        #expect(identity.contains("tuyaDependencyLockSHA256.count == 64"))
        #expect(identity.contains("procedureIdentifier == Self.requiredFieldProcedureIdentifier"))
        #expect(identity.contains("let expectedIdentifier = \"capture-v14-\\(sourceCommitSHA.prefix(12))\""))
        #expect(identity.contains("return buildIdentifier == expectedIdentifier"))
    }
}
