import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture secret custody convergence")
struct TuyaCaptureSecretCustodyConvergenceSourceTests {
    @Test("Nembra generation provenance wins application key collisions")
    func trustedGenerationWins() throws {
        let source = try entrypointSource()
        let receipt = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receipt.contains("let custodySafeUpdate = Self.redactVerifiedAccountUID("))
        #expect(receipt.contains("log(\"tuya_application_update\", custodySafeUpdate.merging(["))
        #expect(receipt.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(receipt.contains("]) { _, trusted in trusted })"))
        #expect(!receipt.contains("{ current, _ in current }"))
        #expect(!receipt.contains("log(\"tuya_application_update\", update.merging(["))
    }

    @Test("verified account UID is scrubbed from application keys and values before event custody")
    func verifiedAccountUIDCannotEnterAcceptedEvent() throws {
        let source = try entrypointSource()
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let receipt = String(try section(
            in: controller,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let secretFragments = String(try section(
            in: driver,
            from: "private static let secretKeyFragments = [",
            to: "private static func redactApplicationSecrets"
        ))

        #expect(controller.contains("<redacted-account-uid>"))
        #expect(controller.contains("private static func redactVerifiedAccountUID("))
        #expect(controller.contains("redactAccountUIDOccurrences(in: key, accountUID: accountUID)"))
        #expect(controller.contains("redactAccountUIDOccurrences(in: value, accountUID: accountUID)"))
        #expect(receipt.contains("let verifiedAccountUID = membershipAccountUID"))
        #expect(receipt.contains("let custodySafeUpdate = Self.redactVerifiedAccountUID("))
        #expect(!receipt.contains("log(\"tuya_application_update\", update.merging(["))

        // Account identity is value-bound. Generic device UID keys remain legitimate evidence.
        #expect(!secretFragments.contains("\"uid\""))
        #expect(secretFragments.components(separatedBy: "\"sessionkey\"").count - 1 == 1)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw ContractError.missing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    private enum ContractError: Error { case missing }
}
