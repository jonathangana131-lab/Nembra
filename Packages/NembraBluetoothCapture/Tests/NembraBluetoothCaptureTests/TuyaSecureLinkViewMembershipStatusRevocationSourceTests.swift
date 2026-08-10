import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link membership status revocation")
struct TuyaSecureLinkViewMembershipStatusRevocationSourceTests {
    @Test("view exit resets membership copy between proof clear and request revocation")
    func exitRevokesMembershipStatusWithProof() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = try controllerFunction("func abandonCorrelationForViewExit()", in: source)
        try assertRevocationOrdering(in: cleanup)
    }

    @Test("foreground loss resets membership copy between proof clear and request revocation")
    func foregroundLossRevokesMembershipStatusWithProof() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = try controllerFunction("func appDidLoseForeground()", in: source)
        try assertRevocationOrdering(in: cleanup)
    }

    private func assertRevocationOrdering(in cleanup: String) throws {
        let clearVerified = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let statusReset = try requiredOffset(containing: "membershipStatus =", in: cleanup)
        let revokeMembershipRequest = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)

        #expect(clearVerified < statusReset)
        #expect(statusReset < revokeMembershipRequest)
        #expect(cleanup.contains("membershipStatus = \"Exact scooter membership must be verified again for this Secure Link session.\""))
        #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
    }

    private func controllerFunction(_ signature: String, in source: String) throws -> String {
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        guard let startRange = controller.range(of: signature),
              let openBrace = controller[startRange.lowerBound...].firstIndex(of: "{") else {
            Issue.record("Expected controller function missing: \(signature)")
            throw SourceContractError.sectionMissing
        }

        var depth = 0
        var index = openBrace
        while index < controller.endIndex {
            if controller[index] == "{" {
                depth += 1
            } else if controller[index] == "}" {
                depth -= 1
                if depth == 0 {
                    let end = controller.index(after: index)
                    return String(controller[startRange.lowerBound..<end])
                }
            }
            index = controller.index(after: index)
        }

        Issue.record("Expected closing brace missing: \(signature)")
        throw SourceContractError.sectionMissing
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
