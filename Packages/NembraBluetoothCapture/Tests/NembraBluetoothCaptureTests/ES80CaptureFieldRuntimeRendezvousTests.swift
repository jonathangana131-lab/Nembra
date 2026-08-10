import Foundation
import Testing

@Suite("ES80 Capture field runtime rendezvous")
struct ES80CaptureFieldRuntimeRendezvousTests {
    private static func fieldEntrypointSource() throws -> String {
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

    @Test("authenticated stationary preflight exposes exact field-build provenance before OFF1")
    func authenticatedStationaryPreflightShowsExactFieldBuildTuple() throws {
        let source = try Self.fieldEntrypointSource()

        #expect(source.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(source.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(source.contains("var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }"))
        #expect(source.contains("var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }"))
        #expect(source.contains("var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }"))

        #expect(source.contains("test.fieldBuildIsAuthoritative ? \"Field build\" : \"Build blocked\""))
        #expect(source.contains("LabeledContent(\"Build\", value: test.fieldBuildIdentifier)"))
        #expect(source.contains("LabeledContent(\"Source commit\", value: test.fieldBuildSourceCommitSHA)"))
        #expect(source.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(source.contains("Label(\"Start with scooter OFF\", systemImage: \"power\")"))
    }

    @Test("OFF1 admission consumes composed current authority instead of minting a permissive app flag")
    func off1ConsumesCurrentComposedAuthority() throws {
        let source = try Self.fieldEntrypointSource()

        #expect(source.contains("private var authorityReady: Bool {"))
        #expect(source.contains("test.fieldBuildIsAuthoritative\n            && test.privateConfig\n            && test.sdkAccountLoggedIn\n            && test.sdkDeviceMembershipVerified\n            && test.accountIdentityLeaseIsAuthorized"))
        #expect(source.contains("if authorityReady {\n                    Button {\n                        test.startBaseline()"))
        #expect(source.contains("requirementRow(\"Capture build\", ready: test.fieldBuildIsAuthoritative)"))
        #expect(!source.contains("fieldBuildIsAuthoritative = true"))
        #expect(!source.contains("permitsPhysicalProcedure = true"))
        #expect(!source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.ResearchBuild("))
        #expect(!source.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader"))
    }

    @Test("authenticated stationary field entrypoint has no Simulator-only authority bypass")
    func authenticatedStationaryEntrypointHasNoSimulatorAuthorityBypass() throws {
        let source = try Self.fieldEntrypointSource()

        #expect(!source.contains("#if DEBUG && targetEnvironment(simulator)"))
        #expect(!source.contains("simulatorQASnapshot"))
        #expect(!source.contains("SYNTHETIC SOFTWARE STATE"))
        #expect(source.contains("Capture stays locked until this Capture build, your Tuya account, and this scooter in that account are all confirmed."))
        #expect(source.contains("Confirm this Capture build and the Tuya account that owns the scooter before Bluetooth starts."))
        #expect(source.contains(".disabled(!authorityReady || test.membershipBusy)"))
    }
}
