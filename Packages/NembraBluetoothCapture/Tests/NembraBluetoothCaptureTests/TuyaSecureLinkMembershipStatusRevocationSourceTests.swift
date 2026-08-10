import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link membership status revocation")
struct TuyaSecureLinkMembershipStatusRevocationSourceTests {
    @Test("view exit revokes verified membership copy with the proof")
    func viewExitRevokesMembershipStatus() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))

        try requireTruthfulStatusRevocation(in: cleanup, context: "view exit")
    }

    @Test("foreground loss revokes verified membership copy with the proof")
    func foregroundLossRevokesMembershipStatus() throws {
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

        try requireTruthfulStatusRevocation(in: cleanup, context: "foreground loss")
        #expect(cleanup.contains("foregroundIntegrityLossHandled = true"))
    }

    private func requireTruthfulStatusRevocation(in cleanup: String, context: String) throws {
        let clearVerified = try requiredOffset(
            containing: "sdkDeviceMembershipVerified = false",
            in: cleanup,
            context: context
        )
        let clearAccount = try requiredOffset(
            containing: "membershipAccountUID = nil",
            in: cleanup,
            context: context
        )
        let clearDevice = try requiredOffset(
            containing: "membershipDeviceID = nil",
            in: cleanup,
            context: context
        )
        let statusReset = try requiredOffset(
            containing: "membershipStatus =",
            in: cleanup,
            context: context
        )
        let revokeMembershipRequest = try requiredOffset(
            containing: "membershipRequestID = UUID()",
            in: cleanup,
            context: context
        )

        #expect(clearVerified < statusReset)
        #expect(clearAccount < statusReset)
        #expect(clearDevice < statusReset)
        #expect(statusReset < revokeMembershipRequest)
        #expect(cleanup.lowercased().contains("verif"))
        #expect(cleanup.lowercased().contains("again"))
        #expect(!cleanup.lowercased().contains("membership verified and leased"))
    }

    private func requiredOffset(
        containing token: String,
        in source: String,
        context: String
    ) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing during \(context): \(token)")
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
