import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya Secure Link membership status revocation")
struct TuyaSecureLinkViewMembershipStatusRevocationSourceTests {
    @Test("view exit clears positive membership copy before request authority rotates")
    func viewExitCannotRetainVerifiedAndLeasedStatus() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = String(try section(
            in: source,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))

        let clearVerified = try requiredOffset(
            containing: "sdkDeviceMembershipVerified = false",
            in: cleanup
        )
        let resetStatus = try requiredOffset(
            containing: "membershipStatus = \"Exact scooter membership must be verified again for this Secure Link session.\"",
            in: cleanup
        )
        let revokeRequest = try requiredOffset(
            containing: "membershipRequestID = UUID()",
            in: cleanup
        )

        #expect(clearVerified < resetStatus)
        #expect(resetStatus < revokeRequest)
        #expect(cleanup.contains("membershipAccountUID = nil"))
        #expect(cleanup.contains("membershipDeviceID = nil"))
        #expect(!cleanup.contains("Exact scooter membership verified and leased to this current SDK account."))
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
