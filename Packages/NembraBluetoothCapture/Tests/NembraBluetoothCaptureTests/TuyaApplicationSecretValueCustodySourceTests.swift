import Foundation
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
        #expect(driver.contains("exactSecretValues"))
        #expect(sanitizer.contains("replacingOccurrences"))
        #expect(sanitizer.contains("exactSecretValues"))
        #expect(!callback.contains("String(describing: Self.redactApplicationSecrets(value))"))
        #expect(callback.contains("String(describing: Self.redactApplicationSecrets(value, exactSecretValues: exactSecretValues))"))
    }

    @Test("credential-shaped keys remain redacted in addition to exact-value custody")
    func keyBasedRedactionIsPreserved() throws {
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
    }

    @Test("recursive sanitizer carries exact-secret custody through arrays and dictionaries")
    func recursiveSanitizerCarriesExactValues() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let sanitizer = String(try section(
            in: driver,
            from: "private static let secretKeyFragments",
            to: "}\n#endif"
        ))

        #expect(sanitizer.contains("redactApplicationSecrets(value, exactSecretValues: exactSecretValues)"))
        #expect(sanitizer.contains("array.map { redactApplicationSecrets($0, exactSecretValues: exactSecretValues) }"))
        #expect(sanitizer.contains("for secret in exactSecretValues"))
        #expect(sanitizer.contains("<redacted-private-app-credential>"))
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
