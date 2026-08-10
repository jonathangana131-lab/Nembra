import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current-product process BLE mutual exclusion")
struct TuyaProcessBLEMutualExclusionCurrentProductSourceTests {
    @Test("package correlation claims one process owner before constructing its scanner")
    func packageCorrelationClaimsBeforeScannerConstruction() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = try section(in: app, from: "private func beginCorrelationSeries()", to: "func startNextCorrelationWindow()")
        let body = String(begin)
        let reset = try requiredRange("resetDiscoverySessionOnly()", in: body)
        let claim = try requiredRange("OfficialTuyaFactory.claimPackageCorrelation(ownerID: controllerOwnershipID)", in: body)
        let session = try requiredRange("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)", in: body)
        #expect(reset.lowerBound < claim.lowerBound)
        #expect(claim.lowerBound < session.lowerBound)
        #expect(body[claim.upperBound..<session.lowerBound].contains("return"))
    }

    @Test("every active window retains process ownership and same-device local BLE contamination fences")
    func activeWindowsRetainOwner() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let async = try section(in: app, from: "func consumeCorrelationAsyncInvalidation()", to: "var correlationWindowLabel")
        let start = try section(in: app, from: "private func startCurrentCorrelationWindow()", to: "func finishCorrelationWindow()")
        let finish = try section(in: app, from: "func finishCorrelationWindow()", to: "private func finishCorrelationSeries")

        #expect(async.contains("OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID)"))
        #expect(async.contains("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"))

        let startOwner = try requiredRange("OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID)", in: String(start))
        let startLocal = try requiredRange("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)", in: String(start))
        let scannerStart = try requiredRange("session.startCurrentWindow()", in: String(start))
        #expect(startOwner.lowerBound < scannerStart.lowerBound)
        #expect(startLocal.lowerBound < scannerStart.lowerBound)

        let finishOwner = try requiredRange("OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID)", in: String(finish))
        let finishLocal = try requiredRange("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)", in: String(finish))
        let scannerSeal = try requiredRange("session.finishCurrentWindow()", in: String(finish))
        #expect(finishOwner.lowerBound < scannerSeal.lowerBound)
        #expect(finishLocal.lowerBound < scannerSeal.lowerBound)
    }

    @Test("correlation owner is released before correlated handoff and on local reset/failure")
    func ownerReleaseIsBoundedToOwningController() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let final = try section(in: app, from: "private func finishCorrelationSeries", to: "func confirmCorrelatedTarget")
        let reset = try section(in: app, from: "private func resetDiscoverySessionOnly()", to: "private func failLocally")
        let failure = try section(in: app, from: "private func failLocally", to: "private func log")
        let finalBody = String(final)
        let release = try requiredRange("OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)", in: finalBody)
        let disposition = try requiredRange("switch result.correlation.disposition", in: finalBody)
        #expect(release.lowerBound < disposition.lowerBound)
        #expect(reset.contains("OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)"))
        #expect(failure.contains("OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)"))
    }

    @Test("Tuya driver handoff cannot race an active package correlation owner")
    func factoryAndControllerBothFenceDriverHandoff() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(in: app, from: "private func beginOfficialConnection(candidate:", to: "private func authenticated(token:")
        let factory = try section(in: app, from: "private enum OfficialTuyaFactory", to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe")
        let controllerBody = String(controller)
        let factoryBody = String(factory)

        let controllerFence = try requiredRange("OfficialTuyaFactory.packageCorrelationOwnerIsClear", in: controllerBody)
        let controllerMake = try requiredRange("OfficialTuyaFactory.make()", in: controllerBody)
        #expect(controllerFence.lowerBound < controllerMake.lowerBound)

        #expect(factoryBody.contains("private static var packageCorrelationOwnerID: UUID?"))
        #expect(factoryBody.contains("static func claimPackageCorrelation(ownerID: UUID) -> Bool"))
        #expect(factoryBody.contains("static func ownsPackageCorrelation(ownerID: UUID) -> Bool"))
        #expect(factoryBody.contains("static func releasePackageCorrelation(ownerID: UUID)"))
        let factoryFence = try requiredRange("guard packageCorrelationOwnerIsClear else { return nil }", in: factoryBody)
        let retirement = try requiredRange("packageCorrelationRetiredForProcess = true", in: factoryBody)
        let driver = try requiredRange("return SmartLifeDriver()", in: factoryBody)
        #expect(factoryFence.lowerBound < retirement.lowerBound)
        #expect(retirement.lowerBound < driver.lowerBound)
    }

    @Test("mutual exclusion remains observation and ownership only")
    func repairCannotMutateScooterTransport() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = try section(in: app, from: "private func beginCorrelationSeries()", to: "func startNextCorrelationWindow()")
        let start = try section(in: app, from: "private func startCurrentCorrelationWindow()", to: "func finishCorrelationWindow()")
        let finish = try section(in: app, from: "func finishCorrelationWindow()", to: "private func finishCorrelationSeries")
        let combined = String(begin) + String(start) + String(finish)
        for forbidden in ["disconnectBLE", "publishDps", "queryDps", "writeValue", "sessionLedger.endConnection"] {
            #expect(!combined.contains(forbidden))
        }
        #expect(app.contains("@MainActor\nprivate enum OfficialTuyaFactory"))
    }

    private func requiredRange(_ needle: String, in source: String) throws -> Range<String.Index> {
        guard let range = source.range(of: needle) else {
            Issue.record("Expected source contract missing: \(needle)")
            throw SourceContractError.sectionMissing
        }
        return range
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
