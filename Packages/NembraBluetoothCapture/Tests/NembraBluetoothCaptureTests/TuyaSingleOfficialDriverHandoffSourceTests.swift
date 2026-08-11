import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture single official Tuya driver handoff")
struct TuyaSingleOfficialDriverHandoffSourceTests {
    @Test("factory refuses any second official driver after process retirement")
    func factoryRefusesSecondDriverHandoff() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let factory = String(try section(
            in: source,
            from: "private enum OfficialTuyaFactory",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe"
        ))
        let make = String(try section(
            in: factory,
            from: "static func make() -> OfficialTuyaDriver?",
            to: "}\n}\n\n#if canImport(ThingSmartHomeKit)"
        ))

        guard let retirementGuard = make.range(of: "guard !packageCorrelationRetiredForProcess,"),
              let packageOwnerGuard = make.range(of: "activePackageCorrelationOwner == nil,"),
              let retirement = make.range(of: "packageCorrelationRetiredForProcess = true"),
              let driver = make.range(of: "return SmartLifeDriver()") else {
            Issue.record("OfficialTuyaFactory.make() must reject a second process-global Tuya driver after the first handoff retires package correlation.")
            throw SourceContractError.sectionMissing
        }

        #expect(retirementGuard.lowerBound < packageOwnerGuard.lowerBound)
        #expect(packageOwnerGuard.lowerBound < retirement.lowerBound)
        #expect(retirement.lowerBound < driver.lowerBound)
    }

    @Test("single-driver guard remains process coordination only")
    func singleDriverGuardHasNoScooterSideEffects() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let factory = String(try section(
            in: source,
            from: "private enum OfficialTuyaFactory",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe"
        ))

        for forbidden in ["disconnectBLE", "publishDps", "queryDps", "writeValue", "sessionLedger.endConnection"] {
            #expect(!factory.contains(forbidden))
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
