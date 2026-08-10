import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event export custody")
struct TuyaApplicationEventExportCustodySourceTests {
    @Test("accepted application events scrub exact account UID and protect trusted generation")
    func acceptedEventCustody() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        #expect(receiver.contains("let verifiedAccountUID = membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("let accountUIDRedactedUpdate = Self.redactVerifiedAccountUID("))
        #expect(receiver.contains("verifiedAccountUID,"))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
        #expect(!receiver.contains(") { current, _ in current })"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging"))
    }

    @Test("UID scrubber covers keys and values without blanket uid classification")
    func exactUIDScrubberIsValueBound() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(in: source, from: "private static func redactVerifiedAccountUID(", to: "private func startWatchdog"))
        #expect(helper.contains("<redacted-account-uid>"))
        #expect(helper.components(separatedBy: "replacingOccurrences(").count - 1 >= 2)
        #expect(helper.contains("sourceKey"))
        #expect(helper.contains("sourceValue"))
        #expect(helper.contains("verifiedAccountUID"))
        #expect(helper.contains("collisionIndex"))
        #expect(!helper.contains("publishDps"))
        #expect(!helper.contains("queryDps"))
        #expect(!helper.contains("writeValue"))
        #expect(!helper.contains("disconnectBLE"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw ContractError.missing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
    private enum ContractError: Error { case missing }
}
