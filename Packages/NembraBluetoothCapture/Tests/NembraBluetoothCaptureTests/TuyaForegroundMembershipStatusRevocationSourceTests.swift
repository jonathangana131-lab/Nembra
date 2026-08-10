import Foundation
import Testing
@testable import NembraBluetoothCapture
@Suite("Secure Link foreground membership status revocation")
struct TuyaForegroundMembershipStatusRevocationSourceTests {
    @Test("foreground loss revokes operator-facing membership truth with the proof")
    func foregroundLossRevokesMembershipStatusWithProof() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        let a=try requiredOffset(containing:"sdkDeviceMembershipVerified = false",in:cleanup)
        let b=try requiredOffset(containing:"membershipAccountUID = nil",in:cleanup)
        let c=try requiredOffset(containing:"membershipDeviceID = nil",in:cleanup)
        let d=try requiredOffset(containing:"membershipStatus =",in:cleanup)
        let e=try requiredOffset(containing:"membershipRequestID = UUID()",in:cleanup)
        #expect(a < d); #expect(b < d); #expect(c < d); #expect(d < e)
        #expect(cleanup.lowercased().contains("verif"))
        #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
    }
    private func requiredOffset(containing token:String,in source:String)throws->String.Index{guard let r=source.range(of:token)else{Issue.record("Expected source token missing: \(token)");throw E.missing};return r.lowerBound}
    private func section(in source:String,from start:String,to end:String)throws->Substring{guard let a=source.range(of:start),let b=source.range(of:end,range:a.upperBound..<source.endIndex)else{Issue.record("Expected source section missing: \(start) ... \(end)");throw E.missing};return source[a.lowerBound..<b.lowerBound]}
    private func readRepositoryFile(_ relativePath:String)throws->String{let r=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent();return try String(contentsOf:r.appendingPathComponent(relativePath),encoding:.utf8)}
    private enum E:Error{case missing}
}
