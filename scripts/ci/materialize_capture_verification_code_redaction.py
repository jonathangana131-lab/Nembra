#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")

old = 'Self.redactedError(error, submittedIdentity: identity)'
new = 'Self.redactedError(error, submittedIdentity: identity, submittedVerificationCode: "")'
if source.count(old) != 2:
    raise SystemExit(f"expected two send-code redaction calls, found {source.count(old)}")
source = source.replace(old, new)

old = 'finishLoginFailure(error, submittedIdentity: identity)'
new = 'finishLoginFailure(error, submittedIdentity: identity, submittedVerificationCode: code)'
if source.count(old) != 2:
    raise SystemExit(f"expected two login failure callbacks, found {source.count(old)}")
source = source.replace(old, new)

old = 'Self.redactedError(error, submittedIdentity: submittedIdentity)'
new = 'Self.redactedError(error, submittedIdentity: submittedIdentity, submittedVerificationCode: "")'
if source.count(old) != 2:
    raise SystemExit(f"expected sign-out plus login-helper redaction calls, found {source.count(old)}")
source = source.replace(old, new)

old = '''    private func finishLoginFailure(_ error: Error?, submittedIdentity: String) {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya SDK login failed: \\(Self.redactedError(error, submittedIdentity: submittedIdentity, submittedVerificationCode: \"\"))"
    }
'''
new = '''    private func finishLoginFailure(_ error: Error?, submittedIdentity: String, submittedVerificationCode: String) {
        busy = false
        verificationCode = ""
        loggedIn = OfficialTuyaFactory.accountLoggedIn
        status = "Tuya SDK login failed: \\(Self.redactedError(error, submittedIdentity: submittedIdentity, submittedVerificationCode: submittedVerificationCode))"
    }
'''
if source.count(old) != 1:
    raise SystemExit(f"expected one finishLoginFailure block, found {source.count(old)}")
source = source.replace(old, new, 1)

old = '''    private static func redactedError(_ error: Error?, submittedIdentity: String) -> String {
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
new = '''    private static func redactedError(_ error: Error?, submittedIdentity: String, submittedVerificationCode: String) -> String {
        var redacted = error?.localizedDescription ?? "unknown error"
        let identity = submittedIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !identity.isEmpty {
            redacted = redacted.replacingOccurrences(
                of: identity,
                with: "<redacted-account>",
                options: [.caseInsensitive, .literal]
            )
        }
        let verificationCode = submittedVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !verificationCode.isEmpty {
            redacted = redacted.replacingOccurrences(
                of: verificationCode,
                with: "<redacted-verification-code>",
                options: [.literal]
            )
        }
        return redacted
    }
'''
if source.count(old) != 1:
    raise SystemExit(f"expected one centralized redactedError helper, found {source.count(old)}")
source = source.replace(old, new, 1)
path.write_text(source, encoding="utf-8")

start = source.index("@MainActor\nprivate final class OfficialTuyaAccountAuthorizer")
end = source.index("#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe", start)
authorizer = source[start:end]
required = (
    "finishLoginFailure(error, submittedIdentity: identity, submittedVerificationCode: code)",
    "private func finishLoginFailure(_ error: Error?, submittedIdentity: String, submittedVerificationCode: String)",
    "Self.redactedError(error, submittedIdentity: submittedIdentity, submittedVerificationCode: submittedVerificationCode)",
    "private static func redactedError(_ error: Error?, submittedIdentity: String, submittedVerificationCode: String) -> String",
    'with: "<redacted-verification-code>"',
    'verificationCode = ""',
)
for needle in required:
    if needle not in authorizer:
        raise SystemExit(f"missing repaired custody contract: {needle}")
if authorizer.count("finishLoginFailure(error, submittedIdentity: identity, submittedVerificationCode: code)") != 2:
    raise SystemExit("email and phone login failures must both preserve the submitted code for scrubbing")
if authorizer.count('redactedError(error, submittedIdentity: identity, submittedVerificationCode: "")') != 2:
    raise SystemExit("send-code errors must preserve identity redaction without inventing a submitted code")
if authorizer.count('redactedError(error, submittedIdentity: submittedIdentity, submittedVerificationCode: "")') != 1:
    raise SystemExit("sign-out error must preserve identity redaction without a verification-code credential")
for forbidden in ("publishDps", "queryDps", "writeValue"):
    if forbidden in authorizer:
        raise SystemExit(f"credential-custody lane gained forbidden protocol authority: {forbidden}")
print("verification-code credential custody: PASS")
