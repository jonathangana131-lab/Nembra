import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture process-wide BLE mutual exclusion")
struct TuyaCrossControllerBLEOwnershipSourceTests {
    @Test("package correlation claims one process owner before scanner creation")
    func packageClaimPrecedesScannerCreation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = String(try section(
            in: app,
            from: "private func beginCorrelationSeries()",
            to: "func startNextCorrelationWindow()"
        ))

        guard let processFence = begin.range(of: "OfficialTuyaFactory.packageCorrelationMayStart"),
              let currentStatus = begin.range(of: "OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"),
              let reset = begin.range(of: "resetDiscoverySessionOnly()"),
              let claim = begin.range(of: "OfficialTuyaFactory.claimPackageCorrelation(ownerID: controllerOwnershipID)"),
              let scanner = begin.range(of: "PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)") else {
            Issue.record("Could not isolate process ownership admission around package scanner creation.")
            throw SourceContractError.sectionMissing
        }

        #expect(processFence.lowerBound < currentStatus.lowerBound)
        #expect(currentStatus.lowerBound < reset.lowerBound)
        #expect(reset.lowerBound < claim.lowerBound)
        #expect(claim.lowerBound < scanner.lowerBound)
        #expect(begin.contains("package_correlation_process_claim_rejected"))
        #expect(!begin[reset.lowerBound..<scanner.lowerBound].contains("await "))
    }

    @Test("every correlation window retains process ownership and rejects Tuya overlap")
    func everyWindowRetainsClaimAndRejectsOverlap() throws {
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

        for body in [start, finish] {
            #expect(body.contains("OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID)"))
            #expect(body.contains("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"))
            #expect(body.contains("sdk_local_ble_ownership_appeared_during_correlation"))
        }
    }

    @Test("final correlation result releases process ownership before correlated handoff")
    func finalResultReleasesBeforeHandoff() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
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

        guard let release = final.range(of: "OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)"),
              let correlated = final.range(of: "phase = .correlated") else {
            Issue.record("Could not isolate final package-claim release before correlated handoff.")
            throw SourceContractError.sectionMissing
        }
        #expect(release.lowerBound < correlated.lowerBound)
        #expect(fail.contains("OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)"))
    }

    @Test("Tuya driver handoff refuses an active package owner and still retires correlation for process")
    func driverHandoffIsMutuallyExclusive() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let factory = String(try section(
            in: app,
            from: "private enum OfficialTuyaFactory",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe"
        ))
        let connection = String(try section(
            in: app,
            from: "private func beginOfficialConnection(candidate:",
            to: "private func authenticated(token:"
        ))

        #expect(factory.contains("private static var packageCorrelationOwnerID: UUID?"))
        #expect(factory.contains("static var packageCorrelationOwnerIsClear: Bool"))
        #expect(factory.contains("static func claimPackageCorrelation(ownerID: UUID) -> Bool"))
        #expect(factory.contains("static func ownsPackageCorrelation(ownerID: UUID) -> Bool"))
        #expect(factory.contains("static func releasePackageCorrelation(ownerID: UUID)"))
        #expect(factory.contains("guard packageCorrelationOwnerID == nil else { return nil }"))

        let make = String(try section(
            in: factory,
            from: "static func make() -> OfficialTuyaDriver?",
            to: "}\n}\n\n#if canImport(ThingSmartHomeKit)"
        ))
        guard let ownerGuard = make.range(of: "guard packageCorrelationOwnerID == nil else { return nil }"),
              let retirement = make.range(of: "packageCorrelationRetiredForProcess = true"),
              let returnDriver = make.range(of: "return SmartLifeDriver()") else {
            Issue.record("Could not isolate package-owner guard and process retirement before driver handoff.")
            throw SourceContractError.sectionMissing
        }
        #expect(ownerGuard.lowerBound < retirement.lowerBound)
        #expect(retirement.lowerBound < returnDriver.lowerBound)

        guard let controllerGuard = connection.range(of: "OfficialTuyaFactory.packageCorrelationOwnerIsClear"),
              let makeCall = connection.range(of: "OfficialTuyaFactory.make()") else {
            Issue.record("Could not isolate controller-side package-owner guard before Tuya driver creation.")
            throw SourceContractError.sectionMissing
        }
        #expect(controllerGuard.lowerBound < makeCall.lowerBound)
        #expect(connection.contains("package_correlation_blocks_tuya_ble_ownership"))
        #expect(!connection[controllerGuard.lowerBound..<makeCall.lowerBound].contains("await "))
    }

    @Test("ownership coordinator stays MainActor serialized and observation only")
    func coordinatorIsObservationOnly() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("@MainActor\nprivate enum OfficialTuyaFactory"))
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
