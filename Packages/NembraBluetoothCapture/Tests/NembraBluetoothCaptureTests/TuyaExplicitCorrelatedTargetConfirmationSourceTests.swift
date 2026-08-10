import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture explicit correlated-target confirmation")
struct TuyaExplicitCorrelatedTargetConfirmationSourceTests {
    @Test("unique repeated correlation is offered for confirmation instead of auto-selected")
    func correlationResultCannotAutoSelectTarget() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let finish = try section(in: app, from: "private func finishCorrelationSeries", to: "func confirmCorrelatedTarget")
        #expect(finish.contains("singleRepeatableCandidate"))
        #expect(!finish.contains("selectedID = id"))
        #expect(!finish.contains("phase = .selected"))
        #expect(!finish.contains("candidate_selected"))
    }

    @Test("operator action is the only bridge from correlated candidate to selected target")
    func explicitOperatorConfirmationOwnsSelection() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let confirmation = try section(in: app, from: "func confirmCorrelatedTarget", to: "func invalidateSDKMembership")
        #expect(confirmation.contains("selectedID"))
        #expect(confirmation.contains("phase = .selected"))
        #expect(confirmation.contains("candidate_selected"))
        #expect(confirmation.contains("correlation"))
    }

    @Test("primary UI exposes explicit confirmation before authentication")
    func primaryUIRequiresConfirmation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let card = try section(in: app, from: "private var discoveryCard: some View", to: "private func authenticationCard")
        #expect(card.contains("confirmCorrelatedTarget"))
        #expect(card.localizedCaseInsensitiveContains("confirm"))
        #expect(card.localizedCaseInsensitiveContains("correlat"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
