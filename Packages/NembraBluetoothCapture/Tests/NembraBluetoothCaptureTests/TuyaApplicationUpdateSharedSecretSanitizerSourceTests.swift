import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application update shared secret sanitizer app contract")
struct TuyaApplicationUpdateSharedSecretSanitizerSourceTests {
    @Test("shipping SmartLife driver delegates application projection to package custody")
    func smartLifeDriverUsesSharedSanitizer() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(driver.contains("TuyaApplicationUpdateSecretSanitizer.sanitizeForStringProjection(dps)"))
        #expect(driver.contains("onApplicationUpdate?("))
        #expect(!driver.contains("private static let secretKeyFragments"))
        #expect(!driver.contains("private static func redactApplicationSecrets"))
        #expect(!driver.contains("String(describing: value)"))
    }

    @Test("accepted export still asserts secret redaction while application events use shared custody")
    func exportPromiseRemainsCoupled() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("secretsRedacted: true"))
        #expect(source.contains("log(\"tuya_application_update\""))
        #expect(source.contains("TuyaApplicationUpdateSecretSanitizer.sanitizeForStringProjection(dps)"))
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
