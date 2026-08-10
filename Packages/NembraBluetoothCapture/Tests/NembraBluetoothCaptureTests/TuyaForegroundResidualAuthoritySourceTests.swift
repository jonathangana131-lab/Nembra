import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground residual authority")
struct TuyaForegroundResidualAuthoritySourceTests {
    @Test("view exit resets operator-facing membership status before rotating callback authority")
    func viewExitCannotRetainVerifiedMembershipCopy() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = String(try section(
            in: source,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))

        let clearProof = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let resetStatus = try requiredOffset(
            containing: "membershipStatus = \"Scooter membership must be verified again for this Secure Link view.\"",
            in: cleanup
        )
        let rotateRequest = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)

        #expect(clearProof < resetStatus)
        #expect(resetStatus < rotateRequest)
        #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased"))
    }

    @Test("foreground loss revokes already-correlated target authority without invalidating accepted artifacts")
    func correlatedTargetCannotCrossForegroundBoundary() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = String(try section(
            in: source,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        let closeAdmission = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let clearProof = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let resetStatus = try requiredOffset(
            containing: "membershipStatus = \"Scooter membership must be verified again for this Secure Link view.\"",
            in: cleanup
        )
        let targetSnapshot = try requiredOffset(
            containing: "let foregroundTargetAuthorityWasLive = phase == .correlated || phase == .selected",
            in: cleanup
        )
        let acceptedGuard = try requiredOffset(containing: "if phase != .accepted", in: cleanup)
        let clearConfirmation = try requiredOffset(containing: "targetCorrelationOperatorConfirmed = false", in: cleanup)
        let clearPending = try requiredOffset(containing: "pendingCorrelatedTargetID = nil", in: cleanup)
        let clearSelected = try requiredOffset(containing: "selectedID = nil", in: cleanup)
        let tokenGate = try requiredOffset(containing: "guard let token = currentConnectionToken else", in: cleanup)
        let correlatedFailure = try requiredOffset(containing: "if foregroundTargetAuthorityWasLive", in: cleanup)

        #expect(closeAdmission < clearProof)
        #expect(clearProof < resetStatus)
        #expect(resetStatus < targetSnapshot)
        #expect(targetSnapshot < acceptedGuard)
        #expect(acceptedGuard < clearConfirmation)
        #expect(clearConfirmation < clearPending)
        #expect(clearPending < clearSelected)
        #expect(clearSelected < tokenGate)
        #expect(tokenGate < correlatedFailure)

        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
        #expect(cleanup.contains("prior correlated target authority was revoked"))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
    }

    @Test("foreground residual closure never manufactures physical or command authority")
    func residualClosureIsObservationOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = String(try section(
            in: source,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        for forbidden in [
            "disconnectBLE",
            "publishDps",
            "queryDps",
            "writeValue",
            "recordObservedTransportLoss",
            "endConnection(",
        ] {
            #expect(!cleanup.contains(forbidden))
        }
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
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

    private enum SourceContractError: Error { case sectionMissing }
}
