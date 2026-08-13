import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya verification-code credential redaction source contract")
struct TuyaVerificationCodeRedactionSourceTests {
    @Test("both email and phone login failures redact account identity and submitted verification code")
    func loginFailureCannotEchoVerificationCode() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = String(try section(
            in: source,
            from: "@MainActor\nprivate final class OfficialTuyaAccountAuthorizer",
            to: "@MainActor\nprivate struct SecureLinkView"
        ))

        #expect(authorizer.contains("let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)"))

        let forwardedFailure = "finishLoginFailure(error, submittedIdentity: identity, submittedVerificationCode: code)"
        #expect(
            authorizer.components(separatedBy: forwardedFailure).count - 1 == 2,
            "both email and phone failure closures must forward the snapshotted verification code"
        )

        #expect(authorizer.contains("private func finishLoginFailure(_ error: Error?, submittedIdentity: String, submittedVerificationCode: String)"))
        #expect(authorizer.contains("Self.redactedError(error, submittedIdentity: submittedIdentity, submittedVerificationCode: submittedVerificationCode)"))
        #expect(authorizer.contains("private static func redactedError(_ error: Error?, submittedIdentity: String, submittedVerificationCode: String) -> String"))

        let scrubber = String(try section(
            in: authorizer,
            from: "private static func redactedError(",
            to: "\n    }\n}"
        ))
        #expect(scrubber.contains("let verificationCode = submittedVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)"))
        #expect(scrubber.contains("of: verificationCode"))
        #expect(scrubber.contains("with: \"<redacted-verification-code>\""))
    }

    @Test("clearing the UI field does not erase the snapshot needed for error scrubbing")
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
