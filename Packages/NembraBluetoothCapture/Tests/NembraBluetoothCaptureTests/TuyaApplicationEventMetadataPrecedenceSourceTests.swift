import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event metadata precedence")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("SDK application keys cannot overwrite Nembra generation provenance")
    func trustedGenerationWins() throws {
        let source = try repositorySource()
        let receiver = String(try section(source, "private func receivedApplicationUpdate(", "private func startWatchdog"))
        #expect(receiver.contains("log(\"tuya_application_update\""))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(!receiver.contains(") { current, _ in current })"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
    }

    private func section(_ text: String, _ start: String, _ end: String) throws -> Substring {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { throw SourceError.missing }
        return text[a.lowerBound..<b.lowerBound]
    }

    private func repositorySource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private enum SourceError: Error { case missing }
}
