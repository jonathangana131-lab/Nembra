import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current app truth convergence")
struct TuyaCaptureAppTruthConvergenceSourceTests {
    @Test("foreground loss revokes sealed correlation and never reopens accepted authority")
    func foregroundBoundaryClosesEveryMutableStage() throws {
        let source = try entrypointSource()
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let activation = String(try section(
            in: controller,
            from: "func activateMembershipRequestsForView()",
            to: "func abandonCorrelationForViewExit()"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        #expect(activation.contains("guard phase != .accepted else"))
        #expect(cleanup.contains("guard phase != .accepted else { return }"))
        #expect(cleanup.contains("phase == .correlated || phase == .selected"))
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection("))
        #expect(!cleanup.contains("disconnectBLE"))
    }

    @Test("revoked membership proof cannot retain positive operator copy")
    func membershipStatusRevokesWithProof() throws {
        let source = try entrypointSource()
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        for (start, end) in [
            ("func abandonCorrelationForViewExit()", "func appDidLoseForeground()"),
            ("func appDidLoseForeground()", "var privateConfig: Bool")
        ] {
            let cleanup = String(try section(in: controller, from: start, to: end))
            let clear = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
            let status = try requiredOffset(containing: "membershipStatus =", in: cleanup)
            let rotate = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
            #expect(clear < status)
            #expect(status < rotate)
            #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
        }
    }

    @Test("application event custody scrubs leased account UID and reserves Nembra generation")
    func applicationEventCustodyIsTrusted() throws {
        let source = try entrypointSource()
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(source.contains("<redacted-account-uid>"))
        #expect(receiver.contains("applicationUpdateForEventCustody(update)"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
        #expect(!receiver.contains(") { current, _ in current })"))
    }

    @Test("account UID scrub is value-bound and secret classifier has one session-key rule")
    func custodySimplificationPreservesGenericUIDEvidence() throws {
        let source = try entrypointSource()
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let classifier = String(try section(
            in: driver,
            from: "private static let secretKeyFragments = [",
            to: "]\n\n    private static func redactApplicationSecrets"
        ))

        #expect(!driver.contains("\"uid\","))
        #expect(classifier.components(separatedBy: "\"sessionkey\"").count - 1 == 1)
        #expect(source.contains("key.replacingOccurrences(of: leasedAccountUID"))
        #expect(source.contains("value.replacingOccurrences(of: leasedAccountUID"))
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
