import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlated-target export provenance")
struct TuyaCorrelatedTargetExportProvenanceSourceTests {
    @Test("diagnostic schema distinguishes correlation method from selected UUID")
    func exportCarriesStructuredCorrelationProvenance() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let export = try section(in: app, from: "struct Export", to: "struct Event")

        #expect(export.contains("selectedPeripheralID"))
        #expect(export.contains("targetCorrelationMethod"))
        #expect(export.contains("targetCorrelationWindowCount"))
        #expect(export.contains("targetCorrelationOperatorConfirmed"))
    }

    @Test("four-window result records method and window count without self-confirming")
    func correlationResultDoesNotMintOperatorConfirmation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let finish = try section(
            in: app,
            from: "private func finishCorrelationSeries",
            to: "func invalidateSDKMembership"
        )

        #expect(finish.contains("singleRepeatableCandidate"))
        #expect(finish.contains("targetCorrelationMethod"))
        #expect(finish.contains("targetCorrelationWindowCount"))
        #expect(!finish.contains("targetCorrelationOperatorConfirmed = true"))
    }

    @Test("only explicit target confirmation records operator confirmation")
    func confirmationIsRecordedAtTheAuthorityBoundary() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let confirmation = try section(
            in: app,
            from: "func confirmCorrelatedTarget",
            to: "func invalidateSDKMembership"
        )

        #expect(confirmation.contains("targetCorrelationOperatorConfirmed = true"))
        #expect(confirmation.contains("candidate_selected"))
    }

    @Test("prepared artifact embeds correlation provenance and reset cannot leak it into another attempt")
    func exportAndResetPreserveSessionBoundary() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let prepare = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")
        #expect(prepare.contains("targetCorrelationMethod:"))
        #expect(prepare.contains("targetCorrelationWindowCount:"))
        #expect(prepare.contains("targetCorrelationOperatorConfirmed:"))

        let reset = try section(in: app, from: "private func resetDiscoverySessionOnly", to: "private func failLocally")
        #expect(reset.contains("targetCorrelationMethod = nil"))
        #expect(reset.contains("targetCorrelationWindowCount = nil"))
        #expect(reset.contains("targetCorrelationOperatorConfirmed = false"))
    }

    @Test("artifact wording never upgrades current-session correlation to permanent scooter identity")
    func exportLanguageStaysAtEarnedAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let prepare = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")

        #expect(!prepare.localizedCaseInsensitiveContains("verified AOVOPRO ES80 identity"))
        #expect(!prepare.localizedCaseInsensitiveContains("durable scooter identity"))
        #expect(!prepare.localizedCaseInsensitiveContains("permanent scooter identity"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
