import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture process-lifetime BLE ownership fence")
struct TuyaProcessLifetimeBLEOwnershipFenceSourceTests {
    @Test("official Tuya driver handoff permanently retires package correlation until relaunch")
    func officialDriverHandoffRetiresPackageCorrelation() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let factory = try section(
            in: source,
            from: "private enum OfficialTuyaFactory",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe"
        )
        let body = String(factory)

        #expect(body.contains("private static var packageCorrelationRetiredForProcess = false"))
        #expect(body.contains("static var packageCorrelationMayStart: Bool"))
        #expect(body.contains("!packageCorrelationRetiredForProcess"))
        #expect(body.contains("packageCorrelationRetiredForProcess = true"))
        #expect(body.components(separatedBy: "packageCorrelationRetiredForProcess = false").count - 1 == 1)
        #expect(body.components(separatedBy: "packageCorrelationRetiredForProcess = true").count - 1 == 1)

        let makeStart = try #require(body.range(of: "static func make() -> OfficialTuyaDriver?"))
        let makeBody = body[makeStart.lowerBound...]
        let retirement = makeBody.range(of: "packageCorrelationRetiredForProcess = true")
        let returnDriver = makeBody.range(of: "return SmartLifeDriver()")
        #expect(retirement != nil)
        #expect(returnDriver != nil)
        if let retirement, let returnDriver {
            #expect(retirement.lowerBound < returnDriver.lowerBound)
        }
    }

    @Test("OFF1 admission and in-process retry both consume the process fence")
    func correlationAndRetryConsumeProcessFence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let retry = try section(
            in: source,
            from: "var failedAttemptCanRestartFromOFF1: Bool",
            to: "var canRestartFromFreshOFF1"
        )
        #expect(retry.contains("OfficialTuyaFactory.packageCorrelationMayStart"))

        let correlation = try section(
            in: source,
            from: "private func beginCorrelationSeries()",
            to: "func confirmCorrelatedTarget"
        )
        let processFence = correlation.range(of: "guard OfficialTuyaFactory.packageCorrelationMayStart else")
        let liveStatus = correlation.range(of: "guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else")
        let reset = correlation.range(of: "resetDiscoverySessionOnly()")
        #expect(processFence != nil)
        #expect(liveStatus != nil)
        #expect(reset != nil)
        if let processFence, let liveStatus, let reset {
            #expect(processFence.lowerBound < liveStatus.lowerBound)
            #expect(liveStatus.lowerBound < reset.lowerBound)
        }
        #expect(correlation.contains("process_tuya_ble_ownership_blocks_scan"))
        #expect(correlation.contains("relaunch with the scooter OFF before a fresh OFF1"))
    }

    @Test("process fence cannot be cleared by controller recovery")
    func processFenceHasNoRuntimeClearPath() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.components(separatedBy: "packageCorrelationRetiredForProcess = false").count - 1 == 1)
        #expect(source.components(separatedBy: "packageCorrelationRetiredForProcess = true").count - 1 == 1)
        #expect(!source.contains("packageCorrelationRetiredForProcess.toggle()"))
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
