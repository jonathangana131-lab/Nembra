import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture cross-controller BLE ownership")
struct TuyaCrossControllerBLEOwnershipSourceTests {
    @Test("package correlation refuses to scan while Tuya still owns same-device local BLE")
    func correlationRequiresGlobalTuyaBLEClearance() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = try section(
            in: app,
            from: "private func beginCorrelationSeries()",
            to: "func startNextCorrelationWindow()"
        )
        let body = String(begin)

        guard let globalOwnershipRead = body.range(of: "OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"),
              let scannerReset = body.range(of: "resetDiscoverySessionOnly()") else {
            Issue.record("Expected global Tuya local-BLE admission and package scanner boundary are missing.")
            throw SourceContractError.sectionMissing
        }

        #expect(globalOwnershipRead.lowerBound < scannerReset.lowerBound)
        #expect(body.contains("existing_sdk_local_ble_ownership_blocks_scan"))
        #expect(body.contains("Package-owned correlation will not scan while Tuya still owns local BLE"))

        let betweenReadAndScanner = body[globalOwnershipRead.upperBound..<scannerReset.lowerBound]
        #expect(betweenReadAndScanner.contains("return"))
    }

    @Test("global ownership read uses the same official Tuya local-BLE authority as authenticated observation")
    func globalReadUsesOfficialTuyaManager() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let factory = try section(
            in: app,
            from: "private enum OfficialTuyaFactory",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe"
        )
        let body = String(factory)

        #expect(body.contains("static func isLocallyConnected(uuid: String) -> Bool"))
        #expect(body.contains("ThingSmartBLEManager.sharedInstance().deviceStatue(withUUID: uuid)"))
    }

    @Test("pre-scan ownership gate does not manufacture a disconnect or command")
    func gateIsObservationOnly() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = try section(
            in: app,
            from: "private func beginCorrelationSeries()",
            to: "func startNextCorrelationWindow()"
        )
        let body = String(begin)

        #expect(!body.contains("disconnectBLE"))
        #expect(!body.contains("publishDps"))
        #expect(!body.contains("queryDps"))
        #expect(!body.contains("sessionLedger.endConnection"))
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
