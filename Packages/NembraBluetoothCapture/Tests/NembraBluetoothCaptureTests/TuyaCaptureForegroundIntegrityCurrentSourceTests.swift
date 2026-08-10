import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current foreground integrity")
struct TuyaCaptureForegroundIntegrityCurrentSourceTests {
    @Test("foreground loss preserves sealed acceptance while revoking mutable authority")
    func foregroundLossRevokesMutableAuthority() throws {
        let source = try entrypointSource()
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

        let acceptedGuard = try requiredOffset(
            containing: "guard phase != .accepted else { return }",
            in: cleanup
        )
        let handledFence = try requiredOffset(
            containing: "guard !foregroundIntegrityLossHandled else { return }",
            in: cleanup
        )
        let proofClear = try requiredOffset(
            containing: "sdkDeviceMembershipVerified = false",
            in: cleanup
        )
        #expect(acceptedGuard < handledFence)
        #expect(handledFence < proofClear)

        for proof in [
            "membershipAccountUID = nil",
            "membershipDeviceID = nil",
            "membershipRequestID = UUID()",
            "officialConnectionRequestID = UUID()"
        ] {
            #expect(cleanup.contains(proof), "foreground loss must revoke view/account authority: \(proof)")
        }

        #expect(cleanup.contains("watchdog?.cancel()"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection("))
        #expect(!cleanup.contains("disconnectBLE"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
    }

    @Test("foreground loss invalidates already-correlated target state before token fallthrough")
    func correlatedTargetCannotCrossForegroundBoundary() throws {
        let source = try entrypointSource()
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

        let liveCorrelationCheck = try requiredOffset(
            containing: "if processCorrelationLease != nil || correlationSession != nil",
            in: cleanup
        )
        let retainedTargetCheck = try requiredOffset(
            containing: "if phase == .correlated || phase == .selected",
            in: cleanup
        )
        let tokenCheck = try requiredOffset(
            containing: "guard let token = currentConnectionToken else",
            in: cleanup
        )

        #expect(liveCorrelationCheck < retainedTargetCheck)
        #expect(retainedTargetCheck < tokenCheck)
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
        #expect(cleanup.contains("pre-background target authority cannot be reused"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw ContractError.missing
        }
        return range.lowerBound
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw ContractError.missing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private enum ContractError: Error { case missing }
}
