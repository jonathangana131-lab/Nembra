import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link view membership-status revocation")
struct TuyaSecureLinkViewMembershipStatusRevocationSourceTests {
    @Test("revoked membership proof cannot retain verified-and-leased copy")
    func viewExitResetsMembershipStatusBeforeRequestRotation() throws {
        let source = try entrypointSource()
        let cleanup = String(try section(in: source, from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()"))
        let clear = try offset("sdkDeviceMembershipVerified = false", in: cleanup)
        let status = try offset("membershipStatus =", in: cleanup)
        let rotate = try offset("membershipRequestID = UUID()", in: cleanup)
        #expect(clear < status)
        #expect(status < rotate)
        #expect(cleanup.lowercased().contains("verif"))
        #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
    }

    @Test("foreground loss revokes the same operator-facing membership claim")
    func foregroundLossResetsMembershipStatusBeforeRequestRotation() throws {
        let source = try entrypointSource()
        let cleanup = String(try section(in: source, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        let clear = try offset("sdkDeviceMembershipVerified = false", in: cleanup)
        let status = try offset("membershipStatus =", in: cleanup)
        let rotate = try offset("membershipRequestID = UUID()", in: cleanup)
        #expect(clear < status)
        #expect(status < rotate)
        #expect(cleanup.lowercased().contains("verif"))
    }

    private func offset(_ token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else { Issue.record("Missing token: \(token)"); throw ContractError.missing }
        return range.lowerBound
    }
    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { Issue.record("Missing section"); throw ContractError.missing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath); for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }
    private enum ContractError: Error { case missing }
}
