#!/usr/bin/env python3
from pathlib import Path

ENTRYPOINT = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCorrelationPerWindowBLEOwnershipSourceTests.swift")

source = ENTRYPOINT.read_text(encoding="utf-8")
old = '''        guard let session = correlationSession,
              let progress = session.progress else {
            failLocally("Fresh Bluetooth correlation authority is unavailable. Restart from OFF1.", "target_correlation_authority_unavailable")
            return
        }

        let label = correlationWindowLabel
'''
new = '''        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
            failLocally(
                "Tuya regained local BLE ownership before the next correlation window. Restart from scooter OFF after that SDK session has cleared; package-owned scanning will not compete with Tuya BLE.",
                "sdk_local_ble_ownership_changed_during_target_correlation"
            )
            return
        }
        guard let session = correlationSession,
              let progress = session.progress else {
            failLocally("Fresh Bluetooth correlation authority is unavailable. Restart from OFF1.", "target_correlation_authority_unavailable")
            return
        }

        let label = correlationWindowLabel
'''
if source.count(old) != 1:
    raise SystemExit("expected exact startCurrentCorrelationWindow insertion point once")
ENTRYPOINT.write_text(source.replace(old, new, 1), encoding="utf-8")

TEST.write_text(r'''import Foundation
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
''', encoding="utf-8")

window = ENTRYPOINT.read_text(encoding="utf-8").split("private func startCurrentCorrelationWindow()", 1)[1].split("func finishCorrelationWindow()", 1)[0]
assert window.index("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)") < window.index("try session.startCurrentWindow()")
for forbidden in ("disconnectBLE", "publishDps", "queryDps", "writeValue", "sessionLedger.endConnection"):
    assert forbidden not in window
print("capture per-window BLE ownership materialized: PASS")
