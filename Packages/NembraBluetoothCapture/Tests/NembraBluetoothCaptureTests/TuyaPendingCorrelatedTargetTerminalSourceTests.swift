import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture pending correlated-target terminal custody")
struct TuyaPendingCorrelatedTargetTerminalSourceTests {
    @Test("explicit confirmation rechecks current source authority and consumes pending target")
    func confirmationConsumesOnlyCurrentAttemptAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let confirmation = try section(
            in: app,
            from: "func confirmCorrelatedTarget()",
            to: "private func finishCorrelationSeries"
        )

        #expect(confirmation.contains("pendingCorrelatedTargetID"))
        #expect(confirmation.contains("sdkAccountLoggedIn"))
        #expect(confirmation.contains("sdkDeviceMembershipVerified"))
        #expect(confirmation.contains("accountIdentityLeaseIsAuthorized"))
        #expect(confirmation.contains("currentConnectionToken == nil"))
        #expect(confirmation.contains("selectedID = id"))
        #expect(confirmation.contains("pendingCorrelatedTargetID = nil"))
        #expect(confirmation.contains("phase = .selected"))
        #expect(confirmation.contains("candidate_selected"))
    }

    @Test("every generic local failure destroys unconfirmed target authority")
    func localTerminalCannotLeavePendingConfirmationReusable() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let failure = try section(
            in: app,
            from: "private func failLocally",
            to: "private func log"
        )

        #expect(failure.contains("pendingCorrelatedTargetID = nil"))
        #expect(failure.contains("phase = .failed"))
    }

    @Test("reset and SDK identity invalidation destroy pending target authority")
    func retryAndIdentityBoundariesCannotCarryPendingTarget() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(
            in: app,
            from: "private func resetDiscoverySessionOnly",
            to: "private func failLocally"
        )
        let invalidation = try section(
            in: app,
            from: "func invalidateSDKMembership()",
            to: "func verifySDKMembership"
        )
        let begin = try section(
            in: app,
            from: "private func beginCorrelationSeries()",
            to: "func startNextCorrelationWindow"
        )

        #expect(reset.contains("pendingCorrelatedTargetID = nil"))
        #expect(invalidation.contains("pendingCorrelatedTargetID = nil"))
        #expect(begin.contains("resetDiscoverySessionOnly()"))
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
