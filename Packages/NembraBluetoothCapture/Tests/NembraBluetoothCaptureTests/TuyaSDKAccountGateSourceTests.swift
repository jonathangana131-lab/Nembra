import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture official Tuya SDK account authority")
struct TuyaSDKAccountGateSourceTests {
    @Test("Bluetooth discovery is impossible before current SDK account authority")
    func discoveryRequiresCurrentSDKAccountAuthorization() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let startBaseline = try sourceSection(
            in: source,
            from: "func startBaseline()",
            to: "func saveBaseline()"
        )

        #expect(
            startBaseline.contains("guard sdkAccountLoggedIn"),
            "The field controller must fail closed before the scooter-OFF CoreBluetooth scan when the official Tuya SDK account session is not currently logged in. UI-only disabling is not sufficient authority."
        )
    }

    @Test("login success is re-read from the official SDK session")
    func loginSuccessRechecksOfficialSDKAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = try sourceSection(
            in: source,
            from: "private final class OfficialTuyaAccountAuthorizer",
            to: "private struct SecureLinkView"
        )
        let success = try sourceSection(
            in: authorizer,
            from: "private func finishLoginSuccess()",
            to: "private func finishLoginFailure"
        )

        #expect(
            success.contains("OfficialTuyaFactory.accountLoggedIn"),
            "A transport success callback must not mint SDK account authority by itself; re-read the official SDK session before promoting loggedIn."
        )
        #expect(
            !success.contains("loggedIn = true"),
            "Caller-local success must not be the source of SDK account authority."
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
            "The account authorizer needs one explicit redaction boundary because SDK errors may echo the submitted email or phone number."
        )
        #expect(
            !authorizer.contains("Tuya could not send the verification code: \\(error?.localizedDescription"),
            "Do not interpolate verification-code SDK error text into UI before removing the submitted account identifier."
        )
        #expect(
            !authorizer.contains("Tuya SDK login failed: \\(error?.localizedDescription"),
            "Do not interpolate login SDK error text into UI before removing the submitted account identifier."
        )
    }

    private func sourceSection(in source: String, from start: String, to end: String) throws -> Substring {
        try sourceSection(in: source[...], from: start, to: end)
    }

    private func sourceSection(in source: Substring, from start: String, to end: String) throws -> Substring {
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
