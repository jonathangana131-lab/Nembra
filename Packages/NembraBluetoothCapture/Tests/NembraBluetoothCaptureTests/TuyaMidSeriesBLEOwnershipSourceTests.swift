import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture mid-series Tuya BLE ownership fence")
struct TuyaMidSeriesBLEOwnershipSourceTests {
    @Test("every active correlation window fails closed if Tuya reacquires local BLE")
    func correlationCannotCoexistWithTuyaLocalBLE() throws {
        let source = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let asyncGuard = try section(in: source, from: "func consumeCorrelationAsyncInvalidation()", to: "var correlationWindowLabel")
        let start = try section(in: source, from: "private func startCurrentCorrelationWindow()", to: "func finishCorrelationWindow()")
        let finish = try section(in: source, from: "func finishCorrelationWindow()", to: "private func finishCorrelationSeries")
        let abandon = try section(in: source, from: "private func abandonPackageCorrelation()", to: "private func releasePackageCorrelationLease()")
        let view = try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View")

        #expect(asyncGuard.contains("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"))
        #expect(asyncGuard.contains("abandonPackageCorrelation()"))
        #expect(asyncGuard.contains("sdk_local_ble_reacquired_during_target_correlation"))

        #expect(abandon.contains("correlationSession?.abandonCurrentWindow()"))
        #expect(abandon.contains("correlationSession = nil"))
        #expect(abandon.contains("releasePackageCorrelationLease()"))
        #expect(abandon.range(of: "correlationSession?.abandonCurrentWindow()")!.lowerBound < abandon.range(of: "releasePackageCorrelationLease()")!.lowerBound)

        #expect(start.contains("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"))
        #expect(start.contains("sdk_local_ble_ownership_blocks_correlation_window"))
        #expect(start.range(of: "OfficialTuyaFactory.isLocallyConnected")!.lowerBound < start.range(of: "session.startCurrentWindow()")!.lowerBound)

        #expect(finish.contains("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"))
        #expect(finish.contains("sdk_local_ble_ownership_invalidates_correlation_window"))
        #expect(finish.range(of: "OfficialTuyaFactory.isLocallyConnected")!.lowerBound < finish.range(of: "session.finishCurrentWindow()")!.lowerBound)

        #expect(view.contains("while !Task.isCancelled"))
        #expect(view.contains("test.consumeCorrelationAsyncInvalidation()"))
        #expect(view.contains("Task.sleep(nanoseconds: 250_000_000)"))
    }

    @Test("ownership fence remains observation-only")
    func ownershipFenceDoesNotMutateTuyaTransport() throws {
        let source = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(in: source, from: "private final class SecureLinkController", to: "private protocol OfficialTuyaDriver")
        #expect(!controller.contains("disconnectBLE"))
        #expect(!controller.contains("publishDps("))
        #expect(!controller.contains("queryDps("))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func read(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}