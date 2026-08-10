import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event metadata precedence")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("SDK application keys cannot overwrite Nembra generation provenance")
    func trustedGenerationWinsReservedKeyCollision() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(!receiver.contains(") { current, _ in current })"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
        for forbidden in ["publishDps", "queryDps", "writeValue", "disconnectBLE"] { #expect(!receiver.contains(forbidden)) }
    }
    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw ContractError.missing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum ContractError: Error { case missing }
}
