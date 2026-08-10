import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated application session-key custody")
struct TuyaApplicationSessionKeyRedactionSourceTests {
    @Test("accepted export session-key promise is enforced at the SDK application boundary")
    func acceptedExportSessionKeyPromiseIsEnforced() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let exportBuilder = String(try section(
            in: source,
            from: "private func makeExport(exportedAt:",
            to: "func prepareExport()"
        ))
        let exportPreparation = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))

        #expect(driver.contains("\"sessionkey\""))
        #expect(driver.contains("lowercased().filter { $0.isLetter || $0.isNumber }"))
        #expect(driver.contains("String(describing: Self.redactApplicationSecrets(value))"))
        #expect(exportBuilder.contains("secretsRedacted: true"))
        #expect(exportPreparation.contains("session key"))
    }

    @Test("session-key spellings normalize to the required custody fragment")
    func sessionKeySpellingsNormalizeToRequiredFragment() {
        for spelling in ["session_key", "session-key", "sessionKey", "SESSION.KEY"] {
            let normalized = spelling.lowercased().filter { $0.isLetter || $0.isNumber }
            #expect(normalized == "sessionkey")
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
