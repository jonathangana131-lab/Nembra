import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya account bridge secret retention")
struct TuyaAccountBridgeSecretRetentionSourceTests {
    @Test("linked devices do not retain local key or raw cloud dictionaries")
    func linkedDeviceKeepsOnlyProductMetadata() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let linked = try section(in: bridge, from: "struct LinkedDevice: Identifiable, Equatable {", to: "struct Home: Identifiable, Equatable {")
        let body = String(linked)

        #expect(!body.contains("localKey"))
        #expect(!body.contains("let raw:"))
        #expect(bridge.contains("\"localKeyRetained\": false"))
        #expect(bridge.contains("selectedDeviceMetadata = Self.redactSecrets(rawDetail)"))
        #expect(bridge.contains("normalized == \"local_key\" || normalized == \"localkey\""))
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

    private enum SourceContractError: Error { case sectionMissing }
}
