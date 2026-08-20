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

    @Test("authenticated preflight exposes exact running-build metadata and one-time authority before OFF1")
    func authenticatedPreflightShowsExactRunningBuildTuple() throws {
        let source = try Self.fieldEntrypointSource()

        #expect(source.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(source.contains("var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }"))
        #expect(source.contains("var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }"))
        #expect(source.contains("var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }"))
        #expect(source.contains("LabeledContent(\"Build\", value: test.fieldBuildIdentifier)"))
        #expect(source.contains("LabeledContent(\"Source commit\", value: test.fieldBuildSourceCommitSHA)"))
        #expect(source.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(source.contains("requirementRow(\"Capture build metadata\", ready: test.fieldBuildMetadataReady)"))
        #expect(source.contains("requirementRow(\"One-time field authorization\", ready: test.fieldAuthorizationReady)"))
        #expect(source.contains("if authorityReady {"))
        #expect(source.contains("stationarySafetyLaunch = .begin"))
        #expect(source.contains("StationarySafetyConfirmationSheet(launch: launch)"))
        #expect(source.contains("test.recordFreshOperatorAttestationAndBegin()"))
        #expect(source.contains("Label(\"Review safety and begin\", systemImage: \"checkmark.shield.fill\")"))
        #expect(source.contains("\"I confirm — begin at OFF1\""))
    }

    @Test("field rendezvous treats build tuple as prerequisite and verifier-owned session as authority")
    func rendezvousConsumesMetadataAndIndependentSessionAuthority() throws {
        let source = try Self.fieldEntrypointSource()

        #expect(source.contains("var fieldBuildMetadataReady: Bool { buildIdentity.hasCompleteFieldBuildMetadata }"))
        #expect(source.contains("var fieldAuthorizationReady: Bool { fieldAuthorization.stage == .armed }"))
        #expect(!source.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(!source.contains("fieldBuildIsAuthoritative"))
        #expect(!source.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader"))
        #expect(!source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.ResearchBuild("))
        #expect(!source.contains("permitsPhysicalProcedure = true"))
        #expect(!source.contains("UserDefaults"))

        let start = try #require(source.range(of: "private func beginBaselineAfterCurrentOperatorAttestation()"))
        let metadataRange = try #require(
            source.range(
                of: "guard buildIdentity.hasCompleteFieldBuildMetadata else",
                range: start.lowerBound..<source.endIndex
            )
        )
        let admissionRange = try #require(
            source.range(
                of: "try self.fieldAuthorization.admitOFF1Start()",
                range: metadataRange.upperBound..<source.endIndex
            )
        )
        let correlationRange = try #require(
            source.range(
                of: "self.beginCorrelationSeries()",
                range: admissionRange.upperBound..<source.endIndex
            )
        )
        #expect(start.lowerBound < metadataRange.lowerBound)
        #expect(metadataRange.lowerBound < admissionRange.lowerBound)
        #expect(admissionRange.lowerBound < correlationRange.lowerBound)
        #expect(source.contains("field_build_identity_unavailable"))
    }

    @Test("caller-constructible metadata never mints physical authority without signed one-time session")
    func callerConstructibleMetadataCannotMintPhysicalAuthority() throws {
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
        #expect(ready.contains("test.fieldBuildMetadataReady"))
        #expect(ready.contains("test.fieldAuthorizationReady"))
        #expect(ready.contains("test.privateConfig"))
        #expect(ready.contains("test.sdkAccountLoggedIn"))
        #expect(ready.contains("test.sdkDeviceMembershipVerified"))
        #expect(ready.contains("test.accountIdentityLeaseIsAuthorized"))

        #expect(identity.contains("var hasCompleteFieldBuildMetadata: Bool"))
        #expect(identity.contains("static let buildInstanceIDInfoKey = \"NembraCaptureBuildInstanceID\""))
        #expect(identity.contains("static let sourceCommitSHAInfoKey = \"NembraCaptureBuildCommitSHA\""))
        #expect(identity.contains("static let requiredFieldProcedureIdentifier = \"ES80-AUTHENTICATED-STATIONARY-v1\""))
        #expect(identity.contains("guard sourceCommitSHA.count == 40"))
        #expect(identity.contains("Self.isCanonicalBuildInstanceID(buildInstanceID)"))
        #expect(identity.contains("tuyaDependencyLockSHA256.count == 64"))
        #expect(identity.contains("procedureIdentifier == Self.requiredFieldProcedureIdentifier"))
        #expect(identity.contains("let expectedIdentifier = \"Capture Build V14-\\(sourceCommitSHA.prefix(12))\""))
        #expect(identity.contains("return buildIdentifier == expectedIdentifier"))

        // The legacy self-authority predicate remains deliberately hard false; app runtime no longer
        // consumes it. Independent authority is the package verifier-owned one-time session.
        #expect(identity.contains("var isAuthoritativeFieldBuild: Bool {\n        false\n    }"))
        #expect(!source.contains("buildIdentity.isAuthoritativeFieldBuild"))
    }
}
