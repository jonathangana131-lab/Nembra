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

    @Test("authenticated preflight exposes exact build metadata and signed attempt authority before OFF 1")
    func authenticatedPreflightShowsExactRunningBuildTuple() throws {
        let source = try Self.fieldEntrypointSource()

        #expect(source.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(source.contains("var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }"))
        #expect(source.contains("var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }"))
        #expect(source.contains("var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }"))
        #expect(source.contains("LabeledContent(\"Build\", value: test.fieldBuildIdentifier)"))
        #expect(source.contains("LabeledContent(\"Source commit\", value: test.fieldBuildSourceCommitSHA)"))
        #expect(source.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(source.contains("requirementRow(\"Capture build metadata\", ready: test.fieldBuildMetadataComplete)"))
        #expect(source.contains("requirementRow(\"One-time field authorization\", ready: test.fieldAuthorizationReady)"))
        #expect(source.contains("if authorityReady {"))
        #expect(source.contains("stationarySafetyLaunch = .begin"))
        #expect(source.contains("StationarySafetyConfirmationSheet(launch: launch)"))
        #expect(source.contains("test.recordFreshOperatorAttestationAndBegin()"))
        #expect(source.contains("Label(\"Review safety and begin\", systemImage: \"checkmark.shield.fill\")"))
        #expect(source.contains("\"I confirm — begin at OFF1\""))
    }

    @Test("field rendezvous consumes the signed attempt gate while legacy build authority stays non-authorizing")
    func rendezvousConsumesSignedAttemptAuthority() throws {
        let source = try Self.fieldEntrypointSource()

        #expect(source.contains("var fieldBuildMetadataComplete: Bool { buildIdentity.hasCompleteFieldBuildMetadata }"))
        #expect(source.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(!source.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader"))
        #expect(!source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.ResearchBuild("))
        #expect(!source.contains("permitsPhysicalProcedure = true"))
        #expect(!source.contains("UserDefaults"))

        let startRange = try #require(source.range(of: "private func beginBaselineAfterCurrentOperatorAttestation()"))
        let correlationRange = try #require(
            source.range(
                of: "private func beginCorrelationSeries()",
                range: startRange.upperBound..<source.endIndex
            )
        )
        let start = source[startRange.lowerBound..<correlationRange.lowerBound]
        #expect(!start.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(start.contains("fieldAuthorization.admitOFF1Start()"))
        #expect(start.contains("guard privateConfig, sdkAccountLoggedIn"))
        #expect(start.contains("verifySDKMembership"))
        #expect(start.contains("TuyaSDKAccountIdentityLeaseGate.verdict"))
        #expect(start.contains("beginCorrelationSeries()"))

        let authorizationAdmission = try #require(start.range(of: "fieldAuthorization.admitOFF1Start()"))
        let correlationStart = try #require(start.range(of: "beginCorrelationSeries()"))
        #expect(authorizationAdmission.lowerBound < correlationStart.lowerBound)
    }

    @Test("well-formed caller-constructible metadata remains mechanically locked before OFF 1")
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
        #expect(ready.contains("test.fieldAuthorizationReady"))
        #expect(!ready.contains("test.fieldBuildIsAuthoritative"))
        #expect(ready.contains("test.privateConfig"))
        #expect(ready.contains("test.sdkAccountLoggedIn"))
        #expect(ready.contains("test.sdkDeviceMembershipVerified"))
        #expect(ready.contains("test.accountIdentityLeaseIsAuthorized"))

        // The tuple is still validated and retained as useful provenance, and its runtime-facing
        // keys/label exactly match the package verifier and external build-record contract.
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

        // But self-described plist/build-setting metadata is not an independent trust anchor.
        #expect(identity.contains("var isAuthoritativeFieldBuild: Bool {\n        false\n    }"))
        #expect(identity.contains("independent physical-build authorization is not available yet"))
    }
}
