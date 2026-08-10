import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Current Capture export secret promise")
struct TuyaExportSecretPromiseCurrentProductSourceTests {
    private let promisedSecretFragments = [
        "localkey",
        "sessionkey",
        "appkey",
        "appsecret",
        "password",
        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "authkey",
        "seckey",
    ]

    @Test("authenticated application update sanitizer covers every export-promised secret class")
    func applicationSanitizerMatchesExportPromise() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let makeExport = String(try section(
            in: source,
            from: "private func makeExport(exportedAt:",
            to: "func prepareExport()"
        ))
        let prepareExport = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))

        #expect(makeExport.contains("secretsRedacted: true"))
        #expect(prepareExport.contains("No account UID, AppKey/AppSecret, password, account token, local_key, session key"))
        for fragment in promisedSecretFragments {
            #expect(driver.contains("\"\(fragment)\""), "missing application secret classifier fragment: \(fragment)")
        }
        #expect(driver.contains("String(describing: Self.redactApplicationSecrets(value))"))
        #expect(driver.contains("onApplicationUpdate?(sanitized)"))
    }

    @Test("Tuya metadata sanitizer covers the same export-promised secret classes")
    func metadataSanitizerMatchesExportPromise() throws {
        let source = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let redactor = String(try section(
            in: source,
            from: "private static func redactSecrets(_ object: Any) -> Any",
            to: "private static func remoteMessage(_ object: [String: Any]) -> String"
        ))

        for fragment in promisedSecretFragments {
            #expect(redactor.contains("\"\(fragment)\""), "missing metadata secret classifier fragment: \(fragment)")
        }
        #expect(redactor.contains("key.lowercased().filter"))
        #expect(redactor.contains("redactSecrets(value)"))
        #expect(redactor.contains("array.map(redactSecrets)"))
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
