import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link membership status revocation")
struct TuyaSecureLinkViewMembershipStatusRevocationSourceTests {
    @Test("view exit revokes status with membership proof")
    func viewExitRevokesStatus() throws {
        let source = try repositorySource()
        let cleanup = String(try section(source, "func abandonCorrelationForViewExit()", "func appDidLoseForeground()"))
        try assertOrdering(cleanup)
        #expect(cleanup.contains("membershipStatus = \"Secure Link left this view."))
    }

    @Test("foreground loss revokes status with membership proof")
    func foregroundLossRevokesStatus() throws {
        let source = try repositorySource()
        let cleanup = String(try section(source, "func appDidLoseForeground()", "var privateConfig: Bool"))
        try assertOrdering(cleanup)
        #expect(cleanup.contains("membershipStatus = \"Capture left the foreground."))
    }

    private func assertOrdering(_ text: String) throws {
        let clear = try offset("sdkDeviceMembershipVerified = false", text)
        let status = try offset("membershipStatus =", text)
        let revoke = try offset("membershipRequestID = UUID()", text)
        #expect(clear < status)
        #expect(status < revoke)
        #expect(!text.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
    }

    private func offset(_ token: String, _ text: String) throws -> String.Index {
        guard let range = text.range(of: token) else { throw SourceError.missing }
        return range.lowerBound
    }

    private func section(_ text: String, _ start: String, _ end: String) throws -> Substring {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { throw SourceError.missing }
        return text[a.lowerBound..<b.lowerBound]
    }

    private func repositorySource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private enum SourceError: Error { case missing }
}
