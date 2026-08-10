import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture bidirectional process BLE ownership lease")
struct TuyaBidirectionalBLEOwnershipLeaseSourceTests {
    @Test("package correlation holds one process lease and Tuya driver handoff is excluded")
    func processLeaseIsBidirectional() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let factory = try section(in: source, from: "private enum OfficialTuyaFactory", to: "private final class OfficialTuyaMembershipProbe")
        let body = String(factory)

        #expect(body.contains("private static var packageCorrelationOwnershipLeaseID: UUID?"))
        #expect(body.contains("static func claimPackageCorrelationOwnership() -> UUID?"))
        #expect(body.contains("static func packageCorrelationOwnershipIsCurrent(_ ownershipLeaseID: UUID) -> Bool"))
        #expect(body.contains("static func releasePackageCorrelationOwnership(_ ownershipLeaseID: UUID)"))
        #expect(body.contains("!packageCorrelationRetiredForProcess && packageCorrelationOwnershipLeaseID == nil"))

        guard let makeStart = body.range(of: "static func make() -> OfficialTuyaDriver?") else {
            Issue.record("Official Tuya make() missing")
            throw SourceContractError.sectionMissing
        }
        let makeTail = body[makeStart.lowerBound...]
        let packageExclusion = makeTail.range(of: "packageCorrelationOwnershipLeaseID == nil")
        let retirement = makeTail.range(of: "packageCorrelationRetiredForProcess = true")
        let driverReturn = makeTail.range(of: "return SmartLifeDriver()")
        #expect(packageExclusion != nil)
        #expect(retirement != nil)
        #expect(driverReturn != nil)
        if let packageExclusion, let retirement, let driverReturn {
            #expect(packageExclusion.lowerBound < retirement.lowerBound)
            #expect(retirement.lowerBound < driverReturn.lowerBound)
        }
    }

    @Test("the complete four-window package series owns the lease until success or failure")
    func controllerOwnsLeaseAcrossSeries() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("private var packageCorrelationOwnershipLeaseID: UUID?"))

        let begin = try section(in: source, from: "private func beginCorrelationSeries()", to: "func startNextCorrelationWindow()")
        let claim = begin.range(of: "OfficialTuyaFactory.claimPackageCorrelationOwnership()")
        let store = begin.range(of: "packageCorrelationOwnershipLeaseID = ownershipLeaseID")
        let reset = begin.range(of: "resetDiscoverySessionOnly()")
        #expect(claim != nil)
        #expect(store != nil)
        #expect(reset != nil)
        if let claim, let store, let reset {
            #expect(claim.lowerBound < store.lowerBound)
            #expect(store.lowerBound < reset.lowerBound)
        }

        let window = try section(in: source, from: "private func startCurrentCorrelationWindow()", to: "func finishCorrelationWindow()")
        let leaseCheck = window.range(of: "OfficialTuyaFactory.packageCorrelationOwnershipIsCurrent(ownershipLeaseID)")
        let liveCheck = window.range(of: "OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)")
        let scannerStart = window.range(of: "session.startCurrentWindow()")
        #expect(leaseCheck != nil)
        #expect(liveCheck != nil)
        #expect(scannerStart != nil)
        if let leaseCheck, let liveCheck, let scannerStart {
            #expect(leaseCheck.lowerBound < liveCheck.lowerBound)
            #expect(liveCheck.lowerBound < scannerStart.lowerBound)
        }

        let finish = try section(in: source, from: "private func finishCorrelationSeries", to: "func confirmCorrelatedTarget")
        #expect(finish.contains("releasePackageCorrelationOwnership()"))
        let failure = try section(in: source, from: "private func failLocally", to: "private func log")
        #expect(failure.contains("releasePackageCorrelationOwnership()"))
    }

    @Test("controller abandonment cannot silently reopen process ownership")
    func abandonmentFailsClosed() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("deinit { watchdog?.cancel() }"))
        #expect(!source.contains("deinit { releasePackageCorrelationOwnership()"))
        #expect(source.components(separatedBy: "packageCorrelationRetiredForProcess = false").count - 1 == 1)
        #expect(source.components(separatedBy: "packageCorrelationRetiredForProcess = true").count - 1 == 1)
        #expect(source.contains("&& !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"))
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
