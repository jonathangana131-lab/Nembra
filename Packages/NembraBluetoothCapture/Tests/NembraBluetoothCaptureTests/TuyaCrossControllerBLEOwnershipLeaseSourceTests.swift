import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture cross-controller BLE ownership lease")
struct TuyaCrossControllerBLEOwnershipLeaseSourceTests {
    @Test("package correlation owns one process-global lease and Tuya handoff refuses overlap")
    func leaseSerializesPackageCorrelationAgainstTuyaHandoff() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let factory = String(try section(
            in: source,
            from: "private enum OfficialTuyaFactory",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe"
        ))

        #expect(factory.contains("private static var activePackageCorrelationOwner: UUID?"))
        #expect(factory.contains("guard !packageCorrelationRetiredForProcess, activePackageCorrelationOwner == nil else { return nil }"))
        #expect(factory.contains("activePackageCorrelationOwner = lease"))
        #expect(factory.contains("guard activePackageCorrelationOwner == lease else { return }"))
        #expect(factory.contains("activePackageCorrelationOwner = nil"))

        let makeStart = try #require(factory.range(of: "static func make() -> OfficialTuyaDriver?"))
        let make = factory[makeStart.lowerBound...]
        let retirementGuard = make.range(of: "guard !packageCorrelationRetiredForProcess,")
        let noPackageOwner = make.range(of: "activePackageCorrelationOwner == nil,")
        let retirePackageForever = make.range(of: "packageCorrelationRetiredForProcess = true")
        let driver = make.range(of: "return SmartLifeDriver()")
        #expect(retirementGuard != nil)
        #expect(noPackageOwner != nil)
        #expect(retirePackageForever != nil)
        #expect(driver != nil)
        if let retirementGuard, let noPackageOwner, let retirePackageForever, let driver {
            #expect(retirementGuard.lowerBound < noPackageOwner.lowerBound)
            #expect(noPackageOwner.lowerBound < retirePackageForever.lowerBound)
            #expect(retirePackageForever.lowerBound < driver.lowerBound)
        }
    }

    @Test("OFF1 acquires after reset and every release is owner-token bound")
    func correlationAcquiresAndReleasesTokenBoundLease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        #expect(controller.contains("private var processCorrelationLease: UUID?"))

        let begin = try section(
            in: controller,
            from: "private func beginCorrelationSeries()",
            to: "func startNextCorrelationWindow()"
        )
        let reset = begin.range(of: "resetDiscoverySessionOnly()")
        let acquire = begin.range(of: "OfficialTuyaFactory.acquirePackageCorrelationLease()")
        let store = begin.range(of: "processCorrelationLease = processLease")
        let session = begin.range(of: "PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)")
        #expect(reset != nil)
        #expect(acquire != nil)
        #expect(store != nil)
        #expect(session != nil)
        if let reset, let acquire, let store, let session {
            #expect(reset.lowerBound < acquire.lowerBound)
            #expect(acquire.lowerBound < store.lowerBound)
            #expect(store.lowerBound < session.lowerBound)
        }

        let release = try section(
            in: controller,
            from: "private func releasePackageCorrelationLease()",
            to: "private func resetDiscoverySessionOnly()"
        )
        #expect(release.contains("guard let processCorrelationLease else { return }"))
        #expect(release.contains("OfficialTuyaFactory.releasePackageCorrelationLease(processCorrelationLease)"))
        #expect(release.contains("self.processCorrelationLease = nil"))
    }

    @Test("pre-window failure cannot strand an acquired process lease")
    func preWindowFailureReleasesLease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let failure = try section(
            in: source,
            from: "private func failLocally(_ text: String, _ kind: String)",
            to: "private func log(_ kind: String"
        )
        #expect(failure.contains("if processCorrelationLease != nil || phase == .baseline"))
        #expect(failure.contains("abandonPackageCorrelation()"))
    }

    @Test("scanner is retired before process lease release and successful series also releases")
    func scannerRetiresBeforeLeaseRelease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let abandon = try section(
            in: source,
            from: "private func abandonPackageCorrelation()",
            to: "private func releasePackageCorrelationLease()"
        )
        let stop = abandon.range(of: "correlationSession?.abandonCurrentWindow()")
        let clear = abandon.range(of: "correlationSession = nil")
        let release = abandon.range(of: "releasePackageCorrelationLease()")
        #expect(stop != nil)
        #expect(clear != nil)
        #expect(release != nil)
        if let stop, let clear, let release {
            #expect(stop.lowerBound < clear.lowerBound)
            #expect(clear.lowerBound < release.lowerBound)
        }

        let finish = try section(
            in: source,
            from: "private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult)",
            to: "func confirmCorrelatedTarget()"
        )
        let finishClear = finish.range(of: "correlationSession = nil")
        let finishRelease = finish.range(of: "releasePackageCorrelationLease()")
        #expect(finishClear != nil)
        #expect(finishRelease != nil)
        if let finishClear, let finishRelease {
            #expect(finishClear.lowerBound < finishRelease.lowerBound)
        }
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
