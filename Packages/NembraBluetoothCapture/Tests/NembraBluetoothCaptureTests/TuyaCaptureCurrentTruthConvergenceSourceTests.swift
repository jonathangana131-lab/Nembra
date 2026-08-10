import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current-truth convergence")
struct TuyaCaptureCurrentTruthConvergenceSourceTests {
    @Test("foreground reactivation remains closed after official Tuya handoff")
    func postHandoffReactivationStaysClosed() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try controller(in: source)
        let activation = String(try section(
            in: controller,
            from: "func activateMembershipRequestsForView()",
            to: "func abandonCorrelationForViewExit()"
        ))

        let processGate = try requiredOffset(containing: "OfficialTuyaFactory.packageCorrelationMayStart", in: activation)
        let tokenGate = try requiredOffset(containing: "currentConnectionToken == nil", in: activation)
        let resetFence = try requiredOffset(containing: "foregroundIntegrityLossHandled = false", in: activation)
        let reopenAdmission = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = true", in: activation)
        #expect(processGate < resetFence)
        #expect(tokenGate < resetFence)
        #expect(resetFence < reopenAdmission)
    }

    @Test("membership status is revoked with proof on view exit and foreground loss")
    func membershipStatusCannotOutliveAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try controller(in: source)
        for cleanup in [
            String(try section(in: controller, from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()")),
            String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool")),
        ] {
            let clearVerified = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
            let statusReset = try requiredOffset(containing: "membershipStatus =", in: cleanup)
            let revokeRequest = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
            #expect(clearVerified < statusReset)
            #expect(statusReset < revokeRequest)
            #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
        }
    }

    @Test("accepted application events scrub exact account UID and reserve Nembra generation")
    func applicationEventCustodyIsFailClosed() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try controller(in: source)
        let receiver = String(try section(
            in: controller,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        #expect(source.contains("<redacted-account-uid>"))
        #expect(receiver.contains("verifiedAccountUID"))
        #expect(receiver.contains("redactVerifiedAccountUID"))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
        #expect(!receiver.contains(") { current, _ in current })"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))

        let helper = String(try section(
            in: controller,
            from: "private func redactVerifiedAccountUID(",
            to: "private func startWatchdog"
        ))
        #expect(helper.contains("key.replacingOccurrences(of: verifiedAccountUID"))
        #expect(helper.contains("value.replacingOccurrences(of: verifiedAccountUID"))
        #expect(helper.contains("<redacted-account-uid>"))
    }

    @Test("application secret classifier is simplified without generic uid erasure")
    func secretClassifierHasOneSessionKeyAndNoGenericUIDRule() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        #expect(driver.components(separatedBy: "\"sessionkey\"").count - 1 == 1)
        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
    }

    private func controller(in source: String) throws -> String {
        String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
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
