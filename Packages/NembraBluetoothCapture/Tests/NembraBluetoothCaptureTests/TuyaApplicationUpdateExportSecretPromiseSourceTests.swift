import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application-update export secret promise")
struct TuyaApplicationUpdateExportSecretPromiseSourceTests {
    @Test("SmartLife delegate uses one canonical sanitizer before controller custody")
    func smartLifeDriverUsesCanonicalSanitizer() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: app,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(driver.contains("TuyaApplicationUpdateSecretSanitizer.sanitize(dps)"))
        #expect(driver.contains("onApplicationUpdate?(sanitized)"))
        #expect(!driver.contains("private static let secretKeyFragments"))
        #expect(!driver.contains("private static func redactApplicationSecrets"))
        #expect(!driver.contains("String(describing: Self.redactApplicationSecrets(value))"))
    }

    @Test("canonical classifier covers every credential class promised absent from accepted export")
    func canonicalSanitizerMatchesExportSecretPromise() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let sanitizer = try readRepositoryFile("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaApplicationUpdateSecretSanitizer.swift")
        let prepareExport = String(try section(
            in: app,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))
        let makeExport = String(try section(
            in: app,
            from: "private func makeExport(exportedAt:",
            to: "func prepareExport()"
        ))

        #expect(makeExport.contains("secretsRedacted: true"))
        #expect(prepareExport.contains("No account UID, AppKey/AppSecret, password, account token, local_key, session key"))

        for fragment in ["localkey", "sessionkey", "appkey", "appsecret", "password", "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey"] {
            #expect(sanitizer.contains("\"\(fragment)\""), "Canonical sanitizer must redact export-promised credential key: \(fragment)")
        }
    }

    @Test("secret custody remains application evidence only")
    func sanitizerIntegrationDoesNotMintProtocolAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let callback = String(try section(
            in: app,
            from: "func device(_ device: ThingSmartDevice?, dpsUpdate dps:",
            to: "}\n#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        for forbidden in ["publishDps", "queryDps", "writeValue", "disconnectBLE"] {
            #expect(!callback.contains(forbidden), "Application secret custody must not add command authority: \(forbidden)")
        }
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
