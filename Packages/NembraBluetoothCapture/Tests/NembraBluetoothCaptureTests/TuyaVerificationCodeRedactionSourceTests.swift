import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya verification-code credential redaction source contract")
struct TuyaVerificationCodeRedactionSourceTests {
    @Test("login failures redact both account identity and submitted verification code")
    func loginFailureCannotEchoVerificationCode() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = String(try section(
            in: source,
            from: "@MainActor\nprivate final class OfficialTuyaAccountAuthorizer",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe"
        ))

        #expect(authorizer.contains("let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)"))
        #expect(authorizer.contains("finishLoginFailure(error, submittedIdentity: identity, submittedVerificationCode: code)"))
        #expect(authorizer.contains("private func finishLoginFailure(_ error: Error?, submittedIdentity: String, submittedVerificationCode: String)"))
        #expect(authorizer.contains("Self.redactedError(error, submittedIdentity: submittedIdentity, submittedVerificationCode: submittedVerificationCode)"))
        #expect(authorizer.contains("private static func redactedError(_ error: Error?, submittedIdentity: String, submittedVerificationCode: String) -> String"))
        #expect(authorizer.contains("with: \"<redacted-verification-code>\""))
    }

    @Test("clearing the UI field does not erase the value needed for error scrubbing")
    func loginFailureScrubsBeforeForgettingCredential() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let failure = String(try section(
            in: source,
            from: "private func finishLoginFailure(",
            to: "private func finishAppleLoginFailure"
        ))

        #expect(failure.contains("submittedVerificationCode"))
        #expect(failure.contains("verificationCode = \"\""))
        #expect(failure.contains("redactedError(error, submittedIdentity: submittedIdentity, submittedVerificationCode: submittedVerificationCode)"))
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
