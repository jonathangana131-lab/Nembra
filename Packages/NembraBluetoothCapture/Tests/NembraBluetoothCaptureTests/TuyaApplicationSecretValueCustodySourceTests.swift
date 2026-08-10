import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application private secret-value custody")
struct TuyaApplicationSecretValueCustodySourceTests {
    @Test("compiled AppKey and AppSecret participate in exact value redaction")
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

        #expect(driver.contains("private static var exactSecretValues: [String]"))
        #expect(driver.contains("NembraTuyaPrivateIdentity.appKey"))
        #expect(driver.contains("NembraTuyaPrivateIdentity.appSecret"))
        #expect(driver.contains(".filter { !$0.isEmpty }"))
        #expect(driver.contains("if $0.count != $1.count { return $0.count > $1.count }"))
        #expect(driver.contains("private static func redactExactApplicationSecretValues("))
        #expect(driver.contains("options: [.literal]"))
        #expect(driver.contains("<redacted-private-application-secret>"))
        #expect(callback.contains("let exactSecretValues = Self.exactSecretValues"))
        #expect(callback.contains("Self.redactApplicationSecrets("))
        #expect(callback.contains("exactSecretValues: exactSecretValues"))
        #expect(!callback.contains("String(describing: Self.redactApplicationSecrets(value))"))
    }

    @Test("exact private values are scrubbed from opaque keys and nested scalar descriptions")
    func exactSecretsCannotHideBehindInnocuousSDKKeys() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(driver.contains("in: keyString"))
        #expect(driver.contains("let rendered = String(describing: object)"))
        #expect(driver.contains("redacted == rendered ? object : redacted"))
        #expect(driver.contains("return array.map"))
        #expect(driver.contains("while sanitized[custodyKey] != nil"))
        #expect(driver.contains("uniqueCustodyKey"))
    }

    @Test("credential-shaped key redaction remains intact")
    func keyBasedCredentialRedactionIsPreserved() throws {
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

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
