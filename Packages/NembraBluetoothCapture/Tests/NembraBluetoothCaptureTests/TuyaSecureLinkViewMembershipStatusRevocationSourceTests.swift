import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link view-exit membership status revocation")
struct TuyaSecureLinkViewMembershipStatusRevocationSourceTests {
    @Test("view exit cannot retain verified membership copy after revoking the membership proof")
    func exitRevokesMembershipStatusWithProof() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))

        let clearVerified = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let statusReset = try requiredOffset(containing: "membershipStatus =", in: cleanup)
        let revokeMembershipRequest = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)

        #expect(clearVerified < statusReset)
        #expect(statusReset < revokeMembershipRequest)
        #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
    }

    @Test("the recovery panel cannot pair revoked authority with stale verified copy")
    func revokedMembershipRendersReverificationCopy() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))

        #expect(cleanup.contains("membershipStatus ="))
        #expect(cleanup.lowercased().contains("verif"))
        #expect(!cleanup.lowercased().contains("membership verified and leased"))
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
