from pathlib import Path
import shutil
import subprocess

REPO = Path.cwd()
PRODUCT_PARENT = "bcea598c9a520064e1c4de9b47dcd0143685b3a1"
BRANCH = "repair/v14-capture-app-update-secret-redaction-bcea-sol"
WORKFLOW = Path(".github/workflows/materialize-capture-app-update-secret-redaction-sol.yml")
HELPER = Path(".github/materializers/capture_secret_redaction_sol.py")
ENTRYPOINT = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationUpdateSecretRedactionSourceTests.swift")


def run(*args: str) -> str:
    completed = subprocess.run(args, check=True, text=True, capture_output=True)
    return completed.stdout.strip()


head = run("git", "rev-parse", "HEAD")
ancestor = run("git", "rev-parse", "HEAD^^")
if ancestor != PRODUCT_PARENT:
    raise SystemExit(f"materializer ancestry mismatch: expected {PRODUCT_PARENT}, got {ancestor} at {head}")

scaffold_paths = set(run("git", "diff", "--name-only", PRODUCT_PARENT, "HEAD").splitlines())
expected_scaffold_paths = {str(HELPER), str(WORKFLOW)}
if scaffold_paths != expected_scaffold_paths:
    raise SystemExit(f"unexpected scaffold scope: {sorted(scaffold_paths)}")

source = ENTRYPOINT.read_text()
old = '''    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
        var sanitized: [String: String] = [:]
        for (key, value) in dps {
            sanitized[String(describing: key)] = String(describing: value)
        }
        onApplicationUpdate?(sanitized)
    }
'''
new = '''    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
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

    private static let secretKeyFragments = [
        "localkey",
        "accesstoken",
        "refreshtoken",
        "authkey",
        "seckey",
    ]

    private static func redactApplicationSecrets(_ object: Any) -> Any {
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
if source.count(old) != 1:
    raise SystemExit(f"expected exact SmartLifeDriver dpsUpdate block once, found {source.count(old)}")
ENTRYPOINT.write_text(source.replace(old, new, 1))

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated application update secret redaction source contract")
struct TuyaApplicationUpdateSecretRedactionSourceTests {
    @Test("authenticated application update details are recursively redacted before controller custody")
    func applicationUpdateCannotRetainCredentialShapedValues() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(driver.contains("private static func redactApplicationSecrets(_ object: Any) -> Any"))
        #expect(driver.contains("secretKeyFragments"))
        #expect(driver.contains("localkey"))
        #expect(driver.contains("accesstoken"))
        #expect(driver.contains("refreshtoken"))
        #expect(driver.contains("authkey"))
        #expect(driver.contains("seckey"))
        #expect(driver.contains("keyString.lowercased().filter"))
        #expect(driver.contains("$0.isLetter || $0.isNumber"))
        #expect(driver.contains("array.map(redactApplicationSecrets)"))
        #expect(driver.contains("String(describing: Self.redactApplicationSecrets(value))"))
        #expect(driver.contains("sanitized[keyString] = \"<redacted>\""))
        #expect(driver.contains("onApplicationUpdate?(sanitized)"))
        #expect(!driver.contains("sanitized[String(describing: key)] = String(describing: value)"))
    }

    @Test("export redaction claim remains coupled to the application-event path")
    func exportRedactionClaimIncludesApplicationEvents() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let export = String(try section(
            in: source,
            from: "private func makeExport(exportedAt:",
            to: "func prepareExport()"
        ))
        let updates = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(export.contains("secretsRedacted: true"))
        #expect(updates.contains("log(\"tuya_application_update\", update.merging(["))
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
''')

repaired = ENTRYPOINT.read_text()
required = [
    'private static func redactApplicationSecrets(_ object: Any) -> Any',
    '"localkey"',
    '"accesstoken"',
    '"refreshtoken"',
    '"authkey"',
    '"seckey"',
    'String(describing: Self.redactApplicationSecrets(value))',
    'sanitized[keyString] = "<redacted>"',
    'onApplicationUpdate?(sanitized)',
]
for needle in required:
    if needle not in repaired:
        raise SystemExit(f"missing repair anchor: {needle}")
if repaired.count('private static func redactApplicationSecrets(_ object: Any) -> Any') != 1:
    raise SystemExit("redaction helper must exist exactly once")
if 'sanitized[String(describing: key)] = String(describing: value)' in repaired:
    raise SystemExit("raw application update projection still present")

subprocess.run(["git", "diff", "--check"], check=True)
if shutil.which("swiftc"):
    subprocess.run(["swiftc", "-parse", str(ENTRYPOINT)], check=True)
    subprocess.run(["swiftc", "-parse", str(TEST)], check=True)

WORKFLOW.unlink()
HELPER.unlink()
subprocess.run(["git", "config", "user.name", "nembra-v14-sol"], check=True)
subprocess.run(["git", "config", "user.email", "actions@users.noreply.github.com"], check=True)
subprocess.run(["git", "add", str(ENTRYPOINT), str(TEST), str(WORKFLOW), str(HELPER)], check=True)
subprocess.run(["git", "diff", "--cached", "--check"], check=True)
subprocess.run(["git", "commit", "-m", "fix(capture): redact authenticated app update secrets"], check=True)
subprocess.run(["git", "push", "origin", f"HEAD:{BRANCH}"], check=True)
