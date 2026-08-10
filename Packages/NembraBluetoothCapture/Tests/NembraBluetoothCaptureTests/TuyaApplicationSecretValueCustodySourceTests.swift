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
