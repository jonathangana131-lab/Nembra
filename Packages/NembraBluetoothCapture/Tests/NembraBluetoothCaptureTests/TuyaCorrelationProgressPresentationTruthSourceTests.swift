import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation progress presentation truth")
struct TuyaCorrelationProgressPresentationTruthSourceTests {
    @Test("completed OFF1 ON1 OFF2 ON2 correlation presents four of four")
    func completedCorrelationDoesNotFallBackToOneOfFour() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        )
        let body = String(surface)

        #expect(!body.contains("Text(\"\\(min(test.correlationCompletedWindowCount + 1, 4))/4\")"))
        #expect(body.contains("correlationDisplayedWindowOrdinal"))
        #expect(body.contains("test.phase == .correlated ? 4"))
        #expect(body.contains("Text(\"\\(correlationDisplayedWindowOrdinal)/4\")"))
    }

    @Test("in-progress correlation still derives its ordinal from package-owned completed windows")
    func activeCorrelationProgressRemainsEvidenceBacked() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        )
        let body = String(surface)

        #expect(body.contains("min(test.correlationCompletedWindowCount + 1, 4)"))
        #expect(!body.localizedCaseInsensitiveContains("rssi progress"))
        #expect(!body.localizedCaseInsensitiveContains("name progress"))
        #expect(!body.localizedCaseInsensitiveContains("tuya hint progress"))
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
