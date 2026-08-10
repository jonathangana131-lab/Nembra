import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground target and membership authority")
struct TuyaCaptureForegroundTargetAuthoritySourceTests {
    @Test("foreground loss retires correlated or selected target authority before token handling")
    func foregroundLossRetiresPostCorrelationTargetAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        let correlated = try requiredOffset(containing: ".correlated", in: cleanup)
        let selected = try requiredOffset(containing: ".selected", in: cleanup)
        let clearPending = try requiredOffset(containing: "pendingCorrelatedTargetID = nil", in: cleanup)
        let clearSelected = try requiredOffset(containing: "selectedID = nil", in: cleanup)
        let clearConfirmation = try requiredOffset(containing: "targetCorrelationOperatorConfirmed = false", in: cleanup)
        let failPhase = try requiredOffset(containing: "phase = .failed", in: cleanup)
        let tokenCheck = try requiredOffset(containing: "guard let token = currentConnectionToken else", in: cleanup)

        #expect(correlated < tokenCheck)
        #expect(selected < tokenCheck)
        #expect(clearPending < tokenCheck)
        #expect(clearSelected < tokenCheck)
        #expect(clearConfirmation < tokenCheck)
        #expect(failPhase < tokenCheck)
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
        #expect(cleanup.contains("Restart from OFF1"))
    }

    @Test("every view-lifetime membership revocation resets operator status with the proof")
    func membershipStatusCannotOutliveRevokedProof() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let viewExit = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))
        let foreground = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        try expectMembershipStatusRevocation(in: viewExit)
        try expectMembershipStatusRevocation(in: foreground)
    }

    private func expectMembershipStatusRevocation(in source: String) throws {
        let clearVerified = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: source)
        let resetStatus = try requiredOffset(containing: "membershipStatus =", in: source)
        let revokeRequest = try requiredOffset(containing: "membershipRequestID = UUID()", in: source)

        #expect(clearVerified < resetStatus)
        #expect(resetStatus < revokeRequest)
        #expect(source.lowercased().contains("verif"))
        #expect(!source.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
