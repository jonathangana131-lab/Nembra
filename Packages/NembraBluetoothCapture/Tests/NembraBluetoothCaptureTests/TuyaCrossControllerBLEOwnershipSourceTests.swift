import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture process-wide BLE ownership")
struct TuyaCrossControllerBLEOwnershipSourceTests {
    @Test("process gate permanently retires package correlation after any Tuya BLE attempt")
    func processGateIsFailClosedAfterTuyaAttempt() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let factory = String(try section(
            in: app,
            from: "private enum OfficialTuyaFactory",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe"
        ))

        #expect(factory.contains("private static var packageCorrelationOwnerID: UUID?"))
        #expect(factory.contains("private static var didAttemptLocalBLEOwnership = false"))
        #expect(factory.contains("static var packageCorrelationRequiresRelaunch: Bool"))
        #expect(factory.contains("static func claimPackageCorrelation(ownerID: UUID) -> Bool"))
        #expect(factory.contains("guard !didAttemptLocalBLEOwnership else { return false }"))
        #expect(factory.contains("guard packageCorrelationOwnerID == nil || packageCorrelationOwnerID == ownerID else { return false }"))
        #expect(factory.contains("packageCorrelationOwnerID = ownerID"))
        #expect(factory.contains("static func beginLocalBLEOwnershipAttempt() -> Bool"))
        #expect(factory.contains("guard packageCorrelationOwnerID == nil else { return false }"))
        #expect(factory.contains("didAttemptLocalBLEOwnership = true"))
    }

    @Test("OFF1 claims process ownership before package scanner creation")
    func correlationClaimPrecedesScannerCreation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = String(try section(
            in: app,
            from: "private func beginCorrelationSeries()",
            to: "func startNextCorrelationWindow()"
        ))

        guard let relaunch = begin.range(of: "OfficialTuyaFactory.packageCorrelationRequiresRelaunch"),
              let currentStatus = begin.range(of: "OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"),
              let reset = begin.range(of: "resetDiscoverySessionOnly()"),
              let claim = begin.range(of: "OfficialTuyaFactory.claimPackageCorrelation(ownerID: controllerOwnershipID)"),
              let scanner = begin.range(of: "PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)") else {
            Issue.record("Could not isolate process ownership admission around package scanner creation.")
            throw SourceContractError.sectionMissing
        }

        #expect(relaunch.lowerBound < currentStatus.lowerBound)
        #expect(currentStatus.lowerBound < reset.lowerBound)
        #expect(reset.lowerBound < claim.lowerBound)
        #expect(claim.lowerBound < scanner.lowerBound)
        #expect(begin.contains("package_correlation_requires_relaunch"))
        #expect(begin.contains("existing_sdk_local_ble_ownership_blocks_scan"))
        #expect(begin.contains("package_correlation_process_claim_rejected"))
        #expect(!begin[reset.lowerBound..<scanner.lowerBound].contains("await "))
    }

    @Test("all four correlation windows retain the same process claim and reject Tuya overlap")
    func fourWindowSeriesRetainsClaim() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let start = String(try section(
            in: app,
            from: "private func startCurrentCorrelationWindow()",
            to: "func finishCorrelationWindow()"
        ))
        let finish = String(try section(
            in: app,
            from: "func finishCorrelationWindow()",
            to: "private func finishCorrelationSeries"
        ))
        let final = String(try section(
            in: app,
            from: "private func finishCorrelationSeries",
            to: "func confirmCorrelatedTarget()"
        ))
        let fail = String(try section(
            in: app,
            from: "private func failLocally",
            to: "private func log("
        ))

        #expect(start.contains("OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID)"))
        #expect(finish.contains("OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID)"))
        #expect(start.contains("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"))
        #expect(finish.contains("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"))
        #expect(start.contains("sdk_local_ble_ownership_appeared_during_correlation"))
        #expect(finish.contains("sdk_local_ble_ownership_appeared_during_correlation"))
        #expect(final.contains("OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)"))
        #expect(fail.contains("OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)"))

        guard let release = final.range(of: "OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)"),
              let correlated = final.range(of: "phase = .correlated") else {
            throw SourceContractError.sectionMissing
        }
        #expect(release.lowerBound < correlated.lowerBound)
    }

    @Test("Tuya BLE attempt is process-gated before driver creation and permanently blocks future package correlation")
    func tuyaAttemptCannotOverlapPackageCorrelation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let connection = String(try section(
            in: app,
            from: "private func beginOfficialConnection(candidate:",
            to: "private func authenticated(token:"
        ))

        guard let gate = connection.range(of: "OfficialTuyaFactory.beginLocalBLEOwnershipAttempt()"),
              let make = connection.range(of: "OfficialTuyaFactory.make()"),
              let task = connection.range(of: "Task { @MainActor") else {
            Issue.record("Could not isolate process gate before Tuya driver/session work.")
            throw SourceContractError.sectionMissing
        }
        #expect(gate.lowerBound < make.lowerBound)
        #expect(make.lowerBound < task.lowerBound)
        #expect(connection.contains("package_correlation_blocks_tuya_ble_ownership"))
        #expect(!connection[gate.lowerBound..<make.lowerBound].contains("await "))
    }

    @Test("ownership coordinator is MainActor serialized and observation only")
    func coordinatorDoesNotManufactureTransportOutcomes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("@MainActor\nprivate enum OfficialTuyaFactory"))
        #expect(app.contains("ThingSmartBLEManager.sharedInstance().deviceStatue(withUUID: uuid)"))

        let factory = String(try section(
            in: app,
            from: "private enum OfficialTuyaFactory",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe"
        ))
        #expect(!factory.contains("disconnectBLE"))
        #expect(!factory.contains("publishDps"))
        #expect(!factory.contains("queryDps"))
        #expect(!factory.contains("sessionLedger.endConnection"))
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
