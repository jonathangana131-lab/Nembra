import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Legacy TODAY field authority retirement")
struct TuyaLegacyTodayFieldAuthorityRetirementSourceTests {
    private let currentProcedure = "ES80-AUTHENTICATED-STATIONARY-v1"

    @Test("historical TODAY directive is an explicit no-authority tombstone")
    func historicalDirectiveCannotAuthorizeCurrentFieldWork() throws {
        let directive = try readRepositoryFile("CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md")

        #expect(directive.contains("Status: **SUPERSEDED / NO FIELD AUTHORITY / PHYSICAL NO-GO.**"))
        #expect(!directive.contains("ACTIVE TODAY OVERRIDE"))
        #expect(directive.contains(currentProcedure))
        #expect(directive.contains("scripts/field/install_one_time_capture.command"))
        #expect(directive.contains("ES80-FINGERPRINT-v1"))
        #expect(directive.contains("must not authorize"))
    }

    @Test("legacy TODAY wrapper fails closed instead of delegating to the fingerprint producer")
    func historicalWrapperCannotDelegate() throws {
        let wrapper = try readRepositoryFile("scripts/ci/xcode27_today_research_field_candidate.sh")

        #expect(wrapper.contains("SUPERSEDED:"))
        #expect(wrapper.contains(currentProcedure))
        #expect(wrapper.contains("scripts/field/install_one_time_capture.command"))
        #expect(wrapper.contains("exit 64"))
        #expect(!wrapper.contains("exec \"$CANONICAL_PRODUCER\""))
        #expect(!wrapper.contains("CANONICAL_PRODUCER="))
    }

    @Test("generic signed producer rejects the retired Research mode")
    func genericProducerRejectsRetiredResearchMode() throws {
        let producer = try readRepositoryFile("scripts/ci/xcode27_signed_field_candidate.sh")

        #expect(producer.contains("if [[ \"${1:-}\" == \"--nembra-today-research-build\" ]]; then"))
        #expect(producer.contains("SUPERSEDED: --nembra-today-research-build"))
        #expect(producer.contains("exit 64"))
        #expect(!producer.contains("TODAY_RESEARCH_BUILD_MODE=1"))
        #expect(!producer.contains("RESEARCH_COMPILE_AUTHORITY=\"canonical-producer-explicit-mode\""))
    }

    @Test("current installer, runtime identity, and provenance gate agree on authenticated stationary procedure")
    func currentFieldAuthorityAgreesOnOneProcedure() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let provenance = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")

        #expect(installer.contains("PROCEDURE_ID=\"\(currentProcedure)\""))
        #expect(identity.contains("static let requiredFieldProcedureIdentifier = \"\(currentProcedure)\""))
        #expect(provenance.contains("procedure='\(currentProcedure)'"))
        #expect(provenance.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier=$PROCEDURE_ID"))
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
