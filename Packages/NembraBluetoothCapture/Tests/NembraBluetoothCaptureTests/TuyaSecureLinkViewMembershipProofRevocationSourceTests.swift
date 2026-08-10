import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link view-exit membership proof revocation")
struct TuyaSecureLinkViewMembershipProofRevocationSourceTests {
    @Test("view exit revokes the earned membership lease before async grants and transport inspection")
    func exitRevokesMembershipProofBeforeReturningOrInspectingTransport() throws {
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

        let closeAdmission = try requiredOffset(
            containing: "acceptsViewScopedMembershipRequests = false",
            in: cleanup
        )
        let clearVerified = try requiredOffset(
            containing: "sdkDeviceMembershipVerified = false",
            in: cleanup
        )
        let clearAccountLease = try requiredOffset(
            containing: "membershipAccountUID = nil",
            in: cleanup
        )
        let clearDeviceLease = try requiredOffset(
            containing: "membershipDeviceID = nil",
            in: cleanup
        )
        let revokeMembershipRequest = try requiredOffset(
            containing: "membershipRequestID = UUID()",
            in: cleanup
        )
        let revokeOfficialRequest = try requiredOffset(
            containing: "officialConnectionRequestID = UUID()",
            in: cleanup
        )
        let activeTransportInspection = try requiredOffset(
            containing: "if let token = currentConnectionToken",
            in: cleanup
        )

        #expect(closeAdmission < clearVerified)
        #expect(clearVerified < revokeMembershipRequest)
        #expect(clearAccountLease < revokeMembershipRequest)
        #expect(clearDeviceLease < revokeMembershipRequest)
        #expect(revokeMembershipRequest < revokeOfficialRequest)
        #expect(revokeOfficialRequest < activeTransportInspection)
    }

    @Test("reappearance must re-earn membership instead of relying on retained view state")
    func reappearanceStillStartsFreshMembershipVerification() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private var hero: some View"
        ))
        let task = String(try section(in: view, from: ".task {", to: ".onDisappear {"))

        let open = try requiredOffset(
            containing: "test.activateMembershipRequestsForView()",
            in: task
        )
        let bootstrap = try requiredOffset(
            containing: "sdkAccount.bootstrap()",
            in: task
        )
        let verify = try requiredOffset(
            containing: "test.verifySDKMembership()",
            in: task
        )

        #expect(open < bootstrap)
        #expect(bootstrap < verify)
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
