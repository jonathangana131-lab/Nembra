import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Legacy TODAY executable authority retirement")
struct TuyaLegacyTodayExecutableAuthorityRetirementSourceTests {
    private let currentProcedure = "ES80-AUTHENTICATED-STATIONARY-v1"

    @Test("retired TODAY directive and executable wrapper cannot authorize current field work")
    func retiredTodayWrapperFailsClosed() throws {
        let directive = try readRepositoryFile("CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md")
        let wrapper = try readRepositoryFile("scripts/ci/xcode27_today_research_field_candidate.sh")

        #expect(directive.contains("RETIRED / NON-AUTHORITATIVE / PHYSICAL NO-GO"))
        #expect(directive.contains(currentProcedure))
        #expect(directive.contains("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"))
        #expect(directive.contains("Those historical mechanisms **must not** be used"))
        #expect(directive.contains("bypass, downgrade, or substitute for the current authenticated stationary gates"))
        #expect(wrapper.contains("SUPERSEDED:"))
        #expect(wrapper.contains(currentProcedure))
        #expect(wrapper.contains("scripts/field/install_one_time_capture.command"))
        #expect(wrapper.contains("exit 64"))
        #expect(!wrapper.contains("CANONICAL_PRODUCER="))
        #expect(!wrapper.contains("exec \"$CANONICAL_PRODUCER\""))
    }

    @Test("signed legacy producer cannot mint the retired Research compile capability")
    func signedProducerRejectsRetiredResearchMode() throws {
        let producer = try readRepositoryFile("scripts/ci/xcode27_signed_field_candidate.sh")

        #expect(producer.contains("if [[ \"${1:-}\" == \"--nembra-today-research-build\" ]]; then"))
        #expect(producer.contains("SUPERSEDED: --nembra-today-research-build"))
        #expect(producer.contains("exit 64"))
        #expect(!producer.contains("TODAY_RESEARCH_BUILD_MODE=1"))
        #expect(!producer.contains("canonical-producer-explicit-mode"))
        #expect(!producer.contains("RESEARCH_COMPILE_CONDITION=\"NEMBRA_ES80_TODAY_RESEARCH\""))
    }

    @Test("current field authority remains authenticated stationary end to end")
    func currentAuthorityAgreesOnProcedure() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let provenance = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(installer.contains("PROCEDURE_ID=\"\(currentProcedure)\""))
        #expect(identity.contains("requiredFieldProcedureIdentifier = \"\(currentProcedure)\""))
        #expect(provenance.contains("procedure='\(currentProcedure)'"))
        #expect(runbook.contains("PROCEDURE_ID: `\(currentProcedure)`"))
        #expect(runbook.contains("standalone Capture"))
        #expect(runbook.contains("official Tuya SDK"))
        #expect(runbook.contains("NO-GO"))
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