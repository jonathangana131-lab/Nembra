import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture explicit correlated-target confirmation")
struct TuyaExplicitCorrelatedTargetConfirmationSourceTests {
    @Test("unique repeated correlation is offered for confirmation instead of auto-selected")
    func correlationResultCannotAutoSelectTarget() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let finish = try section(
            in: app,
            from: "private func finishCorrelationSeries",
            to: "func confirmCorrelatedTarget"
        )

        #expect(finish.contains("singleRepeatableCandidate"))
        #expect(!finish.contains("selectedID = id"))
        #expect(!finish.contains("phase = .selected"))
        #expect(!finish.contains("candidate_selected"))
    }

    @Test("operator action is the only bridge from correlated candidate to selected target")
    func explicitOperatorConfirmationOwnsSelection() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("func confirmCorrelatedTarget"))
        let confirmation = try section(
            in: app,
            from: "func confirmCorrelatedTarget",
            to: "func invalidateSDKMembership"
        )

        #expect(confirmation.contains("selectedID"))
        #expect(confirmation.contains("phase = .selected"))
        #expect(confirmation.contains("candidate_selected"))
        #expect(confirmation.contains("correlation"))
    }

    @Test("primary UI exposes explicit confirmation before authentication")
    func primaryUIRequiresConfirmation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let discoveryCard = try section(
            in: app,
            from: "private var discoveryCard: some View",
            to: "private func authenticationCard"
        )

        #expect(discoveryCard.contains("confirmCorrelatedTarget"))
        #expect(discoveryCard.localizedCaseInsensitiveContains("confirm"))
        #expect(discoveryCard.localizedCaseInsensitiveContains("correlat"))
    }

    @Test("authentication still requires the explicitly selected current-session candidate")
    func authenticationConsumesConfirmedSelection() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticate = try section(
            in: app,
            from: "func authenticate()",
            to: "private func beginOfficialConnection"
        )

        #expect(authenticate.contains("selected"))
        #expect(authenticate.contains("candidate.likely"))
        #expect(authenticate.contains("verifySDKMembership"))
        #expect(authenticate.contains("accountIdentityLeaseIsAuthorized"))
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
