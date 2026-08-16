import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya exact-device callback admission")
struct TuyaExactDeviceCallbackSourceTests {
    @Test("application evidence is admitted only from the exact bound SmartLife device")
    func callbackMustMatchBoundDeviceBeforeForwarding() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let callback = try section(
            in: source,
            from: "func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?)",
            to: "private func"
        )

        guard let exactDeviceFence = callback.range(of: "callbackDevice === boundDevice"),
              let applicationForward = callback.range(of: "onApplicationUpdate") else {
            Issue.record("SmartLife callback must prove exact bound-device identity before application evidence forwarding.")
            return
        }

        #expect(exactDeviceFence.lowerBound < applicationForward.lowerBound)
        #expect(!callback.contains("publishDps("))
        #expect(!callback.contains("writeValue("))
        #expect(!callback.contains("removeDevice"))
        #expect(!callback.contains("resetFactory"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected SmartLife callback source markers are missing.")
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
