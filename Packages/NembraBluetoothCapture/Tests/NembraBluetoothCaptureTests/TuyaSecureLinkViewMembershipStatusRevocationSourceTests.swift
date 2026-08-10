import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link revoked membership presentation")
struct TuyaSecureLinkViewMembershipStatusRevocationSourceTests {
    @Test("both view exit and foreground loss revoke positive membership copy with proof")
    func revokedMembershipStatusTracksAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let viewExit = String(try section(in: source, from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()"))
        let foreground = String(try section(in: source, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        for cleanup in [viewExit, foreground] {
            let clearProof = try #require(cleanup.range(of: "sdkDeviceMembershipVerified = false"))
            let resetStatus = try #require(cleanup.range(of: "membershipStatus = \"Exact scooter membership must be verified again for this Secure Link session.\""))
            let revokeRequest = try #require(cleanup.range(of: "membershipRequestID = UUID()"))
            #expect(clearProof.lowerBound < resetStatus.lowerBound)
            #expect(resetStatus.lowerBound < revokeRequest.lowerBound)
            #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
        }
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
