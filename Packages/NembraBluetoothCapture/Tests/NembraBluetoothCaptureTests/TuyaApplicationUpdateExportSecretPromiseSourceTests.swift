import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application-update export secret promise")
struct TuyaApplicationUpdateExportSecretPromiseSourceTests {
    @Test("application sanitizer covers every credential key explicitly promised absent from export")
    func applicationSanitizerMatchesExportSecretPromise() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let prepareExport = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))
        let makeExport = String(try section(
            in: source,
            from: "private func makeExport(exportedAt:",
            to: "func prepareExport()"
        ))

        #expect(makeExport.contains("secretsRedacted: true"))
        #expect(prepareExport.contains("No account UID, AppKey/AppSecret, password, account token, local_key, session key"))

        for fragment in [
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
        ] {
            #expect(driver.contains("\"\(fragment)\""), "Application sanitizer must redact export-promised credential key: \(fragment)")
        }

        #expect(driver.contains("private static var exactSecretValues: [String]"))
        #expect(driver.contains("Set([NembraTuyaPrivateIdentity.appKey, NembraTuyaPrivateIdentity.appSecret])"))
        #expect(driver.contains("private static func redactKnownSecretValues(in text: String) -> String"))
        #expect(driver.contains("Self.redactedApplicationDescription(value)"))
        #expect(driver.contains("onApplicationUpdate?(sanitized)"))
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