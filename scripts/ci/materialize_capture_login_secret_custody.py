from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaLoginSecretCustodySourceTests.swift"

OLD_EMAIL_FAILURE = 'failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error, submittedIdentity: identity) } }'
NEW_EMAIL_FAILURE = 'failure: { [weak self] error in Task { @MainActor in self?.finishLoginFailure(error, submittedIdentity: identity, submittedVerificationCode: code) } }'

OLD_FINISH = '''    private func finishLoginFailure(_ error: Error?, submittedIdentity: String) {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya SDK login failed: \\(Self.redactedError(error, submittedIdentity: submittedIdentity))"
    }
'''
NEW_FINISH = '''    private func finishLoginFailure(
        _ error: Error?,
        submittedIdentity: String,
        submittedVerificationCode: String
    ) {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya SDK login failed: \\(Self.redactedError(
            error,
            submittedIdentity: submittedIdentity,
            submittedVerificationCode: submittedVerificationCode
        ))"
    }
'''

OLD_REDACTOR = '''    private static func redactedError(_ error: Error?, submittedIdentity: String) -> String {
        let raw = error?.localizedDescription ?? "unknown error"
        let identity = submittedIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty else { return raw }
        return raw.replacingOccurrences(
            of: identity,
            with: "<redacted-account>",
            options: [.caseInsensitive, .literal]
        )
    }
'''
NEW_REDACTOR = '''    private static func redactedError(
        _ error: Error?,
        submittedIdentity: String,
        submittedVerificationCode: String? = nil
    ) -> String {
        var redacted = error?.localizedDescription ?? "unknown error"
        let identity = submittedIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identity.isEmpty {
            redacted = redacted.replacingOccurrences(
                of: identity,
                with: "<redacted-account>",
                options: [.caseInsensitive, .literal]
            )
        }
        if let submittedVerificationCode {
            let verificationCode = submittedVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !verificationCode.isEmpty {
                redacted = redacted.replacingOccurrences(
                    of: verificationCode,
                    with: "<redacted-verification-code>",
                    options: [.caseInsensitive, .literal]
                )
            }
        }
        return redacted
    }
'''

TEST_CONTENT = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya login secret custody source contract")
struct TuyaLoginSecretCustodySourceTests {
    @Test("verification-code login failures redact both submitted secrets")
    func verificationCodeFailureCarriesBothSecretsIntoRedactor() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = String(try section(
            in: source,
            from: "private final class OfficialTuyaAccountAuthorizer",
            to: "@MainActor\nprivate struct SecureLinkView"
        ))
        let login = String(try section(in: authorizer, from: "func login()", to: "func signOut()"))
        let finish = String(try section(in: authorizer, from: "private func finishLoginFailure", to: "private func finishAppleLoginFailure"))

        #expect(login.components(separatedBy: "submittedVerificationCode: code").count - 1 == 2)
        #expect(finish.contains("submittedVerificationCode: String"))
        #expect(finish.contains("verificationCode = \"\""))
        #expect(finish.contains("submittedVerificationCode: submittedVerificationCode"))
        #expect(!login.contains("finishLoginFailure(error, submittedIdentity: identity)"))
    }

    @Test("error redactor scrubs account and verification code independently")
    func redactorCoversBothSecretClasses() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = String(try section(
            in: source,
            from: "private final class OfficialTuyaAccountAuthorizer",
            to: "@MainActor\nprivate struct SecureLinkView"
        ))
        let redactor = String(try section(
            in: authorizer,
            from: "private static func redactedError",
            to: "}\n}\n\n@MainActor\nprivate struct SecureLinkView"
        ))

        #expect(redactor.contains("submittedVerificationCode: String? = nil"))
        #expect(redactor.contains("with: \"<redacted-account>\""))
        #expect(redactor.contains("with: \"<redacted-verification-code>\""))
        #expect(redactor.contains("return redacted"))
        #expect(!redactor.contains("guard !identity.isEmpty else { return raw }"))
    }

    @Test("Apple failure path still avoids raw localized error text")
    func appleFailureRemainsGeneric() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = String(try section(
            in: source,
            from: "private final class OfficialTuyaAccountAuthorizer",
            to: "@MainActor\nprivate struct SecureLinkView"
        ))
        let failure = String(try section(
            in: authorizer,
            from: "private func finishAppleLoginFailure",
            to: "private static func redactedError"
        ))
        #expect(failure.contains("(error as NSError?)?.code"))
        #expect(!failure.contains("localizedDescription"))
        #expect(!failure.contains("identityToken"))
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

    private enum SourceContractError: Error { case sectionMissing }
}
'''


def require_count(source: str, token: str, count: int, label: str) -> None:
    actual = source.count(token)
    if actual != count:
        raise SystemExit(f"{label}: expected {count} match(es), found {actual}")


def apply() -> None:
    app = APP.read_text(encoding="utf-8")
    require_count(app, OLD_EMAIL_FAILURE, 2, "verification-code login failure callbacks")
    require_count(app, OLD_FINISH, 1, "login failure handler")
    require_count(app, OLD_REDACTOR, 1, "current account-only redactor")
    require_count(app, "private var acceptsViewScopedMembershipRequests = false", 1, "current screen-lifetime membership fence")
    require_count(app, "private var officialConnectionRequestID = UUID()", 1, "current official-auth fence")

    app = app.replace(OLD_EMAIL_FAILURE, NEW_EMAIL_FAILURE)
    app = app.replace(OLD_FINISH, NEW_FINISH, 1)
    app = app.replace(OLD_REDACTOR, NEW_REDACTOR, 1)
    APP.write_text(app, encoding="utf-8")

    if TEST.exists():
        raise SystemExit("login secret-custody regression already exists")
    TEST.write_text(TEST_CONTENT, encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    for token in (
        "submittedVerificationCode: code",
        "submittedVerificationCode: String",
        "submittedVerificationCode: String? = nil",
        "<redacted-account>",
        "<redacted-verification-code>",
        "private var acceptsViewScopedMembershipRequests = false",
        "private var officialConnectionRequestID = UUID()",
    ):
        if token not in app:
            raise SystemExit(f"required login-custody/current-product token missing: {token}")
    if app.count("submittedVerificationCode: code") != 2:
        raise SystemExit("both email and phone verification-code login failures must pass the submitted code to redaction")
    if app.count("finishLoginFailure(error, submittedIdentity: identity)") != 0:
        raise SystemExit("identity-only verification-code login failure redaction survived")

    if not TEST.exists():
        raise SystemExit("login secret-custody source regression missing")
    test = TEST.read_text(encoding="utf-8")
    for token in (
        "verificationCodeFailureCarriesBothSecretsIntoRedactor",
        "redactorCoversBothSecretClasses",
        "appleFailureRemainsGeneric",
    ):
        if token not in test:
            raise SystemExit(f"login secret-custody regression missing: {token}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
