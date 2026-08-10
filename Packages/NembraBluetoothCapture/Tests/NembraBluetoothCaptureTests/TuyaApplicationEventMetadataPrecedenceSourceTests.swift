import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event metadata precedence")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("SDK application keys cannot overwrite Nembra generation provenance")
    func trustedGenerationWinsReservedKeyCollision() throws {
        let source = try entrypointSource()
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        #expect(receiver.contains("log(\"tuya_application_update\""))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(!receiver.contains(") { current, _ in current })"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
    }
    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { Issue.record("Missing section"); throw ContractError.missing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath); for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }
    private enum ContractError: Error { case missing }
}
