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
        #expect(sanitizer.contains("exactSecretValues"))
        #expect(sanitizer.contains("redactKnownSecretValues"))
        #expect(sanitizer.contains("replacingOccurrences"))
        #expect(callback.contains("redactKnownSecretValues"))
        #expect(!callback.contains("String(describing: Self.redactApplicationSecrets(value))"))
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

    @Test("opaque key descriptions and recursively nested values cross a final exact-secret scrub")
    func finalStringBoundaryIsScrubbed() throws {
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

        #expect(callback.contains("redactKnownSecretValues(in: keyString)"))
        #expect(callback.contains("redactKnownSecretValues(in: String(describing: sanitizedValue))"))
        #expect(driver.contains("return array.map(redactApplicationSecrets)"))
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
