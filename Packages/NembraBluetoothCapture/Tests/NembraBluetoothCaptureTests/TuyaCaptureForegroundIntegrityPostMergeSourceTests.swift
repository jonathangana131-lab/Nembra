import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture exact-current truth closure")
struct TuyaCaptureForegroundIntegrityPostMergeSourceTests {
    @Test("foreground loss preserves sealed acceptance and destroys correlated target authority")
    func foregroundLossCannotDemoteAcceptedOrReuseCorrelatedTarget() throws {
        let source = try entrypointSource()
        let controller = try secureLinkController(in: source)
        let cleanup = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        #expect(cleanup.contains("guard phase != .accepted else { return }"))
        #expect(cleanup.contains("phase == .correlated || phase == .selected"))
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
    }

    @Test("foreground loss revokes operator-facing membership proof copy before request rotation")
    func foregroundLossCannotDisplayRevokedMembershipAsVerified() throws {
        let source = try entrypointSource()
        let controller = try secureLinkController(in: source)
        let cleanup = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        try requireMembershipStatusRevocationOrdering(in: cleanup)
    }

    @Test("view exit revokes operator-facing membership proof copy before request rotation")
    func viewExitCannotDisplayRevokedMembershipAsVerified() throws {
        let source = try entrypointSource()
        let controller = try secureLinkController(in: source)
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))

        try requireMembershipStatusRevocationOrdering(in: cleanup)
    }

    @Test("application event custody keeps Nembra generation authoritative")
    func applicationPayloadCannotForgeGenerationProvenance() throws {
        let source = try entrypointSource()
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receiver.contains("log(\"tuya_application_update\""))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(!receiver.contains("{ current, _ in current }"))
        #expect(!receiver.contains("{ existing, _ in existing }"))
    }

    @Test("accepted application event custody binds the no-account-UID promise to the earned lease")
    func applicationEventCannotExportVerifiedAccountUID() throws {
        let source = try entrypointSource()
        let controller = try secureLinkController(in: source)
        let receiver = String(try section(
            in: controller,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let prepareExport = String(try section(
            in: controller,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(prepareExport.contains("No account UID"))
        #expect(receiver.contains("membershipAccountUID"))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))

        // Account identity is value-bound. A blanket generic UID key rule could erase legitimate
        // opaque device/protocol evidence merely because a field happens to be named "uid".
        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))

        // The exact account identifier must not survive malformed content merely because it was
        // supplied as a dictionary key rather than a value. The repair may centralize this in any
        // helper, but accepted-event custody must explicitly sanitize both dimensions.
        #expect(
            receiver.contains("redactedKey")
                || receiver.contains("sanitizedKey")
                || receiver.contains("redactApplicationAccountUIDKeys")
                || receiver.contains("redactAccountUIDKey")
        )
        #expect(
            receiver.contains("redactedValue")
                || receiver.contains("sanitizedValue")
                || receiver.contains("redactApplicationAccountUIDValues")
                || receiver.contains("redactAccountUIDValue")
        )
    }

    private func requireMembershipStatusRevocationOrdering(in cleanup: String) throws {
        let clearVerified = try requiredOffset(
            containing: "sdkDeviceMembershipVerified = false",
            in: cleanup
        )
        let resetStatus = try requiredOffset(
            containing: "membershipStatus =",
            in: cleanup
        )
        let rotateMembership = try requiredOffset(
            containing: "membershipRequestID = UUID()",
            in: cleanup
        )

        #expect(clearVerified < resetStatus)
        #expect(resetStatus < rotateMembership)
        #expect(
            cleanup.contains("must be verified again")
                || cleanup.contains("must be reverified")
                || cleanup.contains("re-verify")
                || cleanup.contains("verify membership again")
        )
    }

    private func secureLinkController(in source: String) throws -> String {
        String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw ContractError.missing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw ContractError.missing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func entrypointSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    private enum ContractError: Error { case missing }
}
