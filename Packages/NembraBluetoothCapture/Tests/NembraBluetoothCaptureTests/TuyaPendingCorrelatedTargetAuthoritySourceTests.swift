import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture pending correlated-target authority")
struct TuyaPendingCorrelatedTargetAuthoritySourceTests {
    @Test("fresh correlation remains pending until the operator explicitly confirms it")
    func repeatedCorrelationCannotMintSelectionAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let finish = try function(in: app, startingAt: "private func finishCorrelationSeries")

        #expect(app.contains("pendingCorrelatedTargetID"))
        #expect(finish.contains("singleRepeatableCandidate"))
        #expect(finish.contains("pendingCorrelatedTargetID = id"))
        #expect(!finish.contains("selectedID = id"))
        #expect(!finish.contains("phase = .selected"))
        #expect(!finish.contains("candidate_selected"))
    }

    @Test("confirmation rechecks live source authority and consumes the pending candidate")
    func confirmationCannotPromoteStaleCorrelation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let confirmation = try function(in: app, startingAt: "func confirmCorrelatedTarget")

        #expect(confirmation.contains("pendingCorrelatedTargetID"))
        #expect(confirmation.contains("sdkAccountLoggedIn"))
        #expect(confirmation.contains("sdkDeviceMembershipVerified"))
        #expect(confirmation.contains("accountIdentityLeaseIsAuthorized"))
        #expect(confirmation.contains("selectedID"))
        #expect(confirmation.contains("phase = .selected"))
        #expect(confirmation.contains("candidate_selected"))
        #expect(clearsPendingCorrelation(in: confirmation))
    }

    @Test("all authority-reset boundaries retire an unconfirmed correlated candidate")
    func stalePendingCandidateCannotCrossAttemptOrAccountBoundary() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try function(in: app, startingAt: "private func resetDiscoverySessionOnly")
        let membershipInvalidation = try function(in: app, startingAt: "func invalidateSDKMembership")
        let localFailure = try function(in: app, startingAt: "private func failLocally")

        #expect(clearsPendingCorrelation(in: reset))
        #expect(clearsPendingCorrelation(in: membershipInvalidation))
        #expect(clearsPendingCorrelation(in: localFailure))
    }

    @Test("starting a new OFF1 attempt necessarily crosses the reset boundary")
    func newCorrelationAttemptCannotReusePriorPendingAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = try function(in: app, startingAt: "private func beginCorrelationSeries")
        let reset = try function(in: app, startingAt: "private func resetDiscoverySessionOnly")

        #expect(begin.contains("resetDiscoverySessionOnly()"))
        #expect(clearsPendingCorrelation(in: reset))
    }

    private func clearsPendingCorrelation(in source: Substring) -> Bool {
        source.contains("pendingCorrelatedTargetID = nil") ||
            source.contains("clearPendingCorrelatedTarget")
    }

    private func function(in source: String, startingAt marker: String) throws -> Substring {
        guard let markerRange = source.range(of: marker),
              let openingBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("Expected source function missing: \(marker)")
            throw SourceContractError.functionMissing
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return source[markerRange.lowerBound...index]
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        Issue.record("Expected balanced source function body: \(marker)")
        throw SourceContractError.functionMissing
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
        case functionMissing
    }
}
