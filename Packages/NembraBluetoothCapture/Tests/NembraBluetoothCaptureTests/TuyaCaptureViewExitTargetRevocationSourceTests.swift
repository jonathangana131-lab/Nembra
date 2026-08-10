import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture view-exit target-authority revocation")
struct TuyaCaptureViewExitTargetRevocationSourceTests {
    @Test("navigation exit owns one lifecycle terminal")
    func viewExitSuppressesLaterSceneTerminal() throws {
        let cleanup = try cleanupSource()
        let alreadyOwned = try #require(cleanup.range(of: "if foregroundIntegrityLossHandled { return }"))
        let claim = try #require(cleanup.range(of: "foregroundIntegrityLossHandled = true"))
        let token = try #require(cleanup.range(of: "if let token = currentConnectionToken"))
        #expect(alreadyOwned.lowerBound < claim.lowerBound)
        #expect(claim.lowerBound < token.lowerBound)
        #expect(cleanup.contains("Task { @MainActor [self] in"))
    }

    @Test("active and already-finished target correlation are both fully retired")
    func viewExitErasesAllCurrentAttemptTargetAuthority() throws {
        let cleanup = try cleanupSource()
        #expect(cleanup.contains("if processCorrelationLease != nil || correlationSession != nil"))
        #expect(cleanup.contains("if phase == .correlated || phase == .selected"))
        #expect(cleanup.components(separatedBy: "resetDiscoverySessionOnly()").count - 1 == 2)
        #expect(cleanup.contains("target_correlation_abandoned_on_view_exit"))
        #expect(cleanup.contains("target_correlation_retired_on_view_exit"))
        #expect(!cleanup.contains("guard processCorrelationLease != nil || correlationSession != nil else { return }"))
    }

    @Test("view exit preserves current proof revocation and does not manufacture transport state")
    func viewExitKeepsTruthBoundaries() throws {
        let cleanup = try cleanupSource()
        let proof = try #require(cleanup.range(of: "sdkDeviceMembershipVerified = false"))
        let status = try #require(cleanup.range(of: "membershipStatus ="))
        let request = try #require(cleanup.range(of: "membershipRequestID = UUID()"))
        #expect(proof.lowerBound < status.lowerBound)
        #expect(status.lowerBound < request.lowerBound)
        for forbidden in ["disconnectBLE", "recordObservedTransportLoss", "endConnection(", "writeValue", "publishDps", "queryDps"] {
            #expect(!cleanup.contains(forbidden))
        }
    }

    private func cleanupSource() throws -> String {
        let source = try entrypointSource()
        let controller = try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver")
        return String(try section(in: String(controller), from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()"))
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a=source.range(of:start), let b=source.range(of:end,range:a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceError.missing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private enum SourceError: Error { case missing }
}
