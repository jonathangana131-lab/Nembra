import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture official Tuya SDK account gate")
struct TuyaSDKAccountGateSourceTests {
    @Test("Bluetooth discovery is impossible until the official SDK account is authorized")
    func discoveryRequiresCurrentSDKAccountAuthorization() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let startBaseline = try sourceSection(
            in: source,
            from: "func startBaseline()",
            to: "func saveBaseline()"
        )

        #expect(
            startBaseline.contains("guard sdkAccountAuthorized"),
            "The field controller must fail closed before even the scooter-OFF CoreBluetooth scan when the official Tuya SDK account session is not currently authorized. UI-only disabling is not sufficient authority."
        )
    }

    @Test("SDK account failures redact the entered email or phone before presentation")
    func accountIdentifierIsRedactedFromSDKFailureText() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = try sourceSection(
            in: source,
            from: "private final class OfficialTuyaAccountAuthorizer",
            to: "private struct SecureLinkView"
        )

        #expect(
            authorizer.contains("redactAccountIdentifier"),
            "The account authorizer needs one explicit redaction boundary for Tuya error text because SDK errors may echo the submitted email or phone number."
        )
        #expect(
            !authorizer.contains("Tuya could not send the verification code: \\(error?.localizedDescription"),
            "Do not interpolate the SDK error directly into verification-code UI state before removing the submitted account identifier."
        )
        #expect(
            !authorizer.contains("Tuya SDK login failed: \\(error?.localizedDescription"),
            "Do not interpolate the SDK error directly into login UI state before removing the submitted account identifier."
        )
    }

    private func sourceSection(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected field-source section markers were not found: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NembraBluetoothCapture
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repository root

        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
