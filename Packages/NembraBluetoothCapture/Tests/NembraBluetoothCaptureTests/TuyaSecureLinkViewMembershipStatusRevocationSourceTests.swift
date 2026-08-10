import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link membership status revocation")
struct TuyaSecureLinkViewMembershipStatusRevocationSourceTests {
    @Test("view exit and foreground loss revoke verified copy with the membership proof")
    func lifecycleRevocationsResetMembershipStatusWithProof() throws {
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
        let foregroundLoss = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        for cleanup in [viewExit, foregroundLoss] {
            let clearVerified = try requiredOffset(
                containing: "sdkDeviceMembershipVerified = false",
                in: cleanup
            )
            let statusReset = try requiredOffset(
                containing: "membershipStatus = \"Exact scooter membership must be verified again for this Secure Link attempt.\"",
                in: cleanup
            )
            let revokeMembershipRequest = try requiredOffset(
                containing: "membershipRequestID = UUID()",
                in: cleanup
            )

            #expect(clearVerified < statusReset)
            #expect(statusReset < revokeMembershipRequest)
            #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
        }
    }

    @Test("revoked authority exposes explicit re-verification copy")
    func revokedMembershipRendersReverificationCopy() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        #expect(controller.contains("membershipStatus = \"Exact scooter membership must be verified again for this Secure Link attempt.\""))
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
