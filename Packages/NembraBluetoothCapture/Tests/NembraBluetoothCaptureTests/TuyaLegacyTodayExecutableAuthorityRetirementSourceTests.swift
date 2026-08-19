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

    @Test("every TODAY operator handoff is banner-retired before its preserved historical body")
    func allTodayOperatorDocumentsFailClosedAtFirstLine() throws {
        let docs = repositoryRoot.appendingPathComponent("docs", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: docs.path)
            .filter { $0.hasPrefix("ES80_TODAY_") && $0.hasSuffix(".md") }
            .sorted()
        #expect(!names.isEmpty)

        for name in names {
            let source = try readRepositoryFile("docs/\(name)")
            #expect(source.hasPrefix("# RETIRED / DO NOT USE"), "\(name) lacks a first-line retirement banner")
            let banner = source.components(separatedBy: "\n---\n").first ?? ""
            #expect(banner.contains("historical evidence only"), "\(name) does not demote its historical body")
            #expect(banner.contains("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"), "\(name) does not route to the canonical runbook")
            #expect(banner.contains("scripts/field/install_one_time_capture.command"), "\(name) does not route to the canonical installer")
            #expect(banner.contains("Physical Capture remains NO-GO"), "\(name) lacks a fail-closed physical status")
        }
    }

    @Test("current operator entrypoints never route to retired signed-candidate wrappers")
    func activeHandoffsCannotInvokeRetiredTodayExecutables() throws {
        let activePaths = [
            "CAPTURE_HARD_FREEZE_ACTIVE.md",
            "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md",
            "docs/CAPTURE_TUYA_OFFICIAL_SDK_PROVISIONING.md",
        ]
        let retiredExecutableNames = [
            "xcode27_today_research_field_candidate.sh",
            "xcode27_signed_field_candidate.sh",
        ]

        for path in activePaths {
            let source = try readRepositoryFile(path)
            for executable in retiredExecutableNames {
                #expect(!source.contains(executable), "\(path) routes to retired executable \(executable)")
            }
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
