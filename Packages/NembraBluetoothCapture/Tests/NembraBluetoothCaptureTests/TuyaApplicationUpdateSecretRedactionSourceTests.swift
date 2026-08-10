import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated application update secret custody integration")
struct TuyaApplicationUpdateSecretRedactionSourceTests {
    @Test("SmartLifeDriver sanitizes before controller event custody")
    func smartLifeDriverUsesPackageSanitizerBeforeCallback() throws {
        let appSource = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: appSource,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(driver.contains("guard let dps, !dps.isEmpty else { return }"))
        #expect(driver.contains("let sanitized = TuyaApplicationUpdateSecretSanitizer.sanitize(dps)"))
        #expect(driver.contains("onApplicationUpdate?(sanitized)"))
        #expect(!driver.contains("sanitized[String(describing: key)] = String(describing: value)"))
        #expect(driver.components(separatedBy: "onApplicationUpdate?(sanitized)").count == 2)
    }

    @Test("package sanitizer owns recursive credential-key redaction")
    func sanitizerOwnsExpectedFailClosedContract() throws {
        let sanitizer = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaApplicationUpdateSecretSanitizer.swift"
        )

        #expect(sanitizer.contains("public enum TuyaApplicationUpdateSecretSanitizer"))
        #expect(sanitizer.contains("public static func sanitize(_ update: [AnyHashable: Any]) -> [String: String]"))
        #expect(sanitizer.contains("key.lowercased().filter { $0.isLetter || $0.isNumber }"))
        #expect(sanitizer.contains("array.map(redactApplicationSecrets)"))
        #expect(sanitizer.contains("localkey"))
        #expect(sanitizer.contains("accesstoken"))
        #expect(sanitizer.contains("refreshtoken"))
        #expect(sanitizer.contains("authkey"))
        #expect(sanitizer.contains("seckey"))
        #expect(sanitizer.contains("redactedValue = \"<redacted>\""))
    }

    @Test("export redaction declaration remains coupled to application-event custody")
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
