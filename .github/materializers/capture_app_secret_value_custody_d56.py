#!/usr/bin/env python3
from pathlib import Path
import subprocess

BASE = "d56a30c699fbdecec6130537d3f3f4f4232f5c47"
WORKFLOW = ".github/workflows/capture-app-secret-value-custody-d56-materializer.yml"
SCRIPT = ".github/materializers/capture_app_secret_value_custody_d56.py"
SOURCE = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationSecretValueCustodySourceTests.swift")


def out(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one exact match, got {count}")
    return text.replace(old, new, 1)


setup_delta = set(out("git", "diff", "--name-only", BASE, "HEAD").splitlines())
if setup_delta != {WORKFLOW, SCRIPT}:
    raise SystemExit(f"unexpected construction delta: {sorted(setup_delta)}")

source = SOURCE.read_text(encoding="utf-8")
old_callback = '''    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                sanitized[keyString] = "<redacted>"
            } else {
                sanitized[keyString] = String(describing: Self.redactApplicationSecrets(value))
            }
        }
        onApplicationUpdate?(sanitized)
    }
'''
new_callback = '''    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        let exactSecretValues = Self.exactSecretValues
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            let keyString = String(describing: key)
            let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
            let redactedKey = Self.redactExactSecretValues(in: keyString, secretValues: exactSecretValues)
            var custodyKey = redactedKey
            var collisionOrdinal = 2
            while sanitized[custodyKey] != nil {
                custodyKey = "\\(redactedKey)#\\(collisionOrdinal)"
                collisionOrdinal += 1
            }
            if Self.secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                sanitized[custodyKey] = "<redacted>"
            } else {
                sanitized[custodyKey] = Self.applicationValueDescription(
                    value,
                    exactSecretValues: exactSecretValues
                )
            }
        }
        onApplicationUpdate?(sanitized)
    }
'''
source = replace_once(source, old_callback, new_callback, "dps callback")

old_sanitizer = '''    private static func redactApplicationSecrets(_ object: Any) -> Any {
        if let dictionary = object as? [AnyHashable: Any] {
            var sanitized: [String: Any] = [:]
            for (key, value) in dictionary {
                let keyString = String(describing: key)
                let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
                if secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                    sanitized[keyString] = "<redacted>"
                } else {
                    sanitized[keyString] = redactApplicationSecrets(value)
                }
            }
            return sanitized
        }
        if let array = object as? [Any] {
            return array.map(redactApplicationSecrets)
        }
        return object
    }
'''
new_sanitizer = '''    private static var exactSecretValues: [String] {
#if canImport(NembraTuyaPrivateConfig)
        Array(Set([
            NembraTuyaPrivateIdentity.appKey,
            NembraTuyaPrivateIdentity.appSecret,
        ].filter { !$0.isEmpty })).sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs < rhs }
            return lhs.count > rhs.count
        }
#else
        []
#endif
    }

    private static func redactExactSecretValues(
        in text: String,
        secretValues: [String]
    ) -> String {
        var redacted = text
        for secret in secretValues where !secret.isEmpty {
            redacted = redacted.replacingOccurrences(of: secret, with: "<redacted>")
        }
        return redacted
    }

    private static func applicationValueDescription(
        _ object: Any,
        exactSecretValues: [String]
    ) -> String {
        let structurallyRedacted = redactApplicationSecrets(
            object,
            exactSecretValues: exactSecretValues
        )
        return redactExactSecretValues(
            in: String(describing: structurallyRedacted),
            secretValues: exactSecretValues
        )
    }

    private static func redactApplicationSecrets(
        _ object: Any,
        exactSecretValues: [String]
    ) -> Any {
        if let dictionary = object as? [AnyHashable: Any] {
            var sanitized: [String: Any] = [:]
            for (key, value) in dictionary.sorted(by: {
                String(describing: $0.key) < String(describing: $1.key)
            }) {
                let keyString = String(describing: key)
                let normalizedKey = keyString.lowercased().filter { $0.isLetter || $0.isNumber }
                let redactedKey = redactExactSecretValues(in: keyString, secretValues: exactSecretValues)
                var custodyKey = redactedKey
                var collisionOrdinal = 2
                while sanitized[custodyKey] != nil {
                    custodyKey = "\\(redactedKey)#\\(collisionOrdinal)"
                    collisionOrdinal += 1
                }
                if secretKeyFragments.contains(where: { normalizedKey.contains($0) }) {
                    sanitized[custodyKey] = "<redacted>"
                } else {
                    sanitized[custodyKey] = redactApplicationSecrets(
                        value,
                        exactSecretValues: exactSecretValues
                    )
                }
            }
            return sanitized
        }
        if let array = object as? [Any] {
            return array.map { redactApplicationSecrets($0, exactSecretValues: exactSecretValues) }
        }
        if let string = object as? String {
            return redactExactSecretValues(in: string, secretValues: exactSecretValues)
        }
        return object
    }
'''
source = replace_once(source, old_sanitizer, new_sanitizer, "recursive secret sanitizer")
SOURCE.write_text(source, encoding="utf-8")

if TEST.exists():
    raise SystemExit(f"refusing to overwrite existing regression: {TEST}")
TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application secret-value export custody")
struct TuyaApplicationSecretValueCustodySourceTests {
    @Test("private AppKey/AppSecret values cannot survive under innocuous SDK keys")
    func privateApplicationIdentityIsValueBoundBeforeEventCustody() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let callback = String(try section(
            in: driver,
            from: "func device(_ device: ThingSmartDevice?, dpsUpdate",
            to: "private static let secretKeyFragments"
        ))
        let sanitizer = String(try section(
            in: driver,
            from: "private static let secretKeyFragments",
            to: "}\n#endif"
        ))

        #expect(driver.contains("NembraTuyaPrivateIdentity.appKey"))
        #expect(driver.contains("NembraTuyaPrivateIdentity.appSecret"))
        #expect(driver.contains("private static var exactSecretValues: [String]"))
        #expect(driver.contains("].filter { !$0.isEmpty }"))
        #expect(callback.contains("let exactSecretValues = Self.exactSecretValues"))
        #expect(callback.contains("Self.applicationValueDescription("))
        #expect(callback.contains("Self.redactExactSecretValues(in: keyString"))
        #expect(sanitizer.contains("replacingOccurrences(of: secret, with: \"<redacted>\")"))
        #expect(sanitizer.contains("String(describing: structurallyRedacted)"))
        #expect(!callback.contains("String(describing: Self.redactApplicationSecrets(value))"))
    }

    @Test("credential-shaped keys and redaction collisions remain fail-safe")
    func keyBasedRedactionIsPreservedWithoutDroppingOpaqueEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        for fragment in [
            "localkey", "sessionkey", "appkey", "appsecret", "password",
            "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey",
        ] {
            #expect(driver.contains("\"\(fragment)\""))
        }
        #expect(driver.contains("secretKeyFragments.contains"))
        #expect(driver.contains("while sanitized[custodyKey] != nil"))
        #expect(driver.contains("collisionOrdinal += 1"))
    }

    @Test("recursive sanitizer binds nested strings to exact secret values")
    func nestedApplicationValuesCannotBypassFinalDescriptionScrub() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        #expect(driver.contains("redactApplicationSecrets($0, exactSecretValues: exactSecretValues)"))
        #expect(driver.contains("redactExactSecretValues(in: string, secretValues: exactSecretValues)"))
        #expect(driver.contains("redactExactSecretValues(\n            in: String(describing: structurallyRedacted)"))
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
''', encoding="utf-8")

subprocess.run(["git", "diff", "--check"], check=True)
materialized = SOURCE.read_text(encoding="utf-8")
assert 'NembraTuyaPrivateIdentity.appKey' in materialized
assert 'NembraTuyaPrivateIdentity.appSecret' in materialized
assert 'let exactSecretValues = Self.exactSecretValues' in materialized
assert 'String(describing: Self.redactApplicationSecrets(value))' not in materialized
assert 'applicationValueDescription(' in materialized
assert 'replacingOccurrences(of: secret, with: "<redacted>")' in materialized

# Parse-only validation catches Swift syntax drift without requiring the private SDK on Linux.
if shutil := __import__('shutil'):
    swiftc = shutil.which("swiftc")
    if swiftc:
        subprocess.run([swiftc, "-parse", str(SOURCE)], check=True)

Path(WORKFLOW).unlink()
Path(SCRIPT).unlink()
subprocess.run(["git", "diff", "--check"], check=True)
subprocess.run(["git", "config", "user.name", "github-actions[bot]"], check=True)
subprocess.run(["git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"], check=True)
subprocess.run(["git", "add", "-A"], check=True)
subprocess.run(["git", "commit", "-m", "fix(capture): bind private app secrets to event custody"], check=True)
subprocess.run(["git", "push", "origin", "HEAD:fix/v14-capture-app-secret-value-custody-d56-sol"], check=True)
