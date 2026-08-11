import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture package-owned correlation scanner ownership")
struct TuyaPackageOwnedCorrelationSingleScannerSourceTests {
    @Test("standalone Capture does not keep a second app-owned CoreBluetooth manager")
    func packageCorrelationIsTheOnlyDiscoveryOwner() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("PassiveBluetoothPowerCycleObservationSession"))
        #expect(app.contains("beginCorrelationSeries"))
        #expect(!app.contains("private var central: CBCentralManager"))
        #expect(!app.contains("CBCentralManager(delegate: self"))
        #expect(!app.contains("CBCentralManagerDelegate"))
        #expect(!app.contains("central.scanForPeripherals"))
        #expect(!app.contains("central.stopScan"))
    }

    @Test("legacy app-side advertisement candidate mutation is retired")
    func legacyCandidateScannerCannotCompeteWithPackageCorrelation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(!app.contains("private func updateCandidate"))
        #expect(!app.contains("didDiscover peripheral"))
        #expect(!app.contains("CBAdvertisementDataServiceUUIDsKey"))
        #expect(!app.contains("CBAdvertisementDataManufacturerDataKey"))
        #expect(!app.contains("CBAdvertisementDataIsConnectableKey"))
    }

    @Test("fresh target authority continues to come only from the package correlation result")
    func targetAuthorityStillConsumesPackageDisposition() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let finish = try section(
            in: app,
            from: "private func finishCorrelationSeries",
            to: "func invalidateSDKMembership"
        )

        #expect(finish.contains("PassiveBluetoothPowerCycleObservationResult"))
        #expect(finish.contains("singleRepeatableCandidate"))
        #expect(finish.contains("freshlyCorrelated: true"))
        #expect(finish.localizedCaseInsensitiveContains("not permanent scooter identity"))
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
