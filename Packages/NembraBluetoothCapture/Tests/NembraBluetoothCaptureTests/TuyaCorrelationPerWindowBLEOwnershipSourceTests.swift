import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture per-window Tuya BLE ownership")
struct TuyaCorrelationPerWindowBLEOwnershipSourceTests {
    @Test("every fresh correlation window rechecks global Tuya local-BLE ownership before package scan")
    func everyWindowRechecksGlobalOwnership() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let window = try section(
            in: app,
            from: "private func startCurrentCorrelationWindow()",
            to: "func finishCorrelationWindow()"
        )
        let body = String(window)

        guard let ownershipRead = body.range(of: "OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"),
              let scannerStart = body.range(of: "try session.startCurrentWindow()") else {
            Issue.record("Each fresh OFF1/ON1/OFF2/ON2 scanner window must synchronously recheck process-global Tuya local-BLE ownership before package-owned scanning starts.")
            throw SourceContractError.sectionMissing
        }

        #expect(ownershipRead.lowerBound < scannerStart.lowerBound)
        #expect(body[ownershipRead.upperBound..<scannerStart.lowerBound].contains("return"))
    }

    @Test("the shared window-start path actually owns every OFF1 ON1 OFF2 ON2 scanner admission")
    func sharedWindowStartPathOwnsSeries() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = try section(
            in: app,
            from: "private func beginCorrelationSeries()",
            to: "func finishCorrelationWindow()"
        )
        let body = String(begin)

        #expect(body.contains("startCurrentCorrelationWindow()"))
        #expect(body.contains("func startNextCorrelationWindow()"))
        #expect(body.contains("startCurrentCorrelationWindow()\n    }"))
    }

    @Test("per-window ownership fence remains observation-only and cannot mutate scooter state")
    func ownershipFenceIsReadOnly() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let window = try section(
            in: app,
            from: "private func startCurrentCorrelationWindow()",
            to: "func finishCorrelationWindow()"
        )
        let body = String(window)

        #expect(!body.contains("disconnectBLE"))
        #expect(!body.contains("publishDps"))
        #expect(!body.contains("queryDps"))
        #expect(!body.contains("writeValue"))
        #expect(!body.contains("sessionLedger.endConnection"))
    }

    @Test("ownership loss abandons the in-progress series and fails closed")
    func ownershipLossAbandonsSeries() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let window = try section(
            in: app,
            from: "private func startCurrentCorrelationWindow()",
            to: "func finishCorrelationWindow()"
        )
        let body = String(window)
        guard let ownership = body.range(of: "guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else"),
              let scannerStart = body.range(of: "try session.startCurrentWindow()") else {
            throw SourceContractError.sectionMissing
        }
        let guarded = body[ownership.lowerBound..<scannerStart.lowerBound]
        #expect(guarded.contains("correlationSession?.abandonCurrentWindow()"))
        #expect(guarded.contains("correlationSession = nil"))
        #expect(guarded.contains("sdk_local_ble_ownership_changed_during_target_correlation"))
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
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
