import Foundation
import Testing

@Suite("ES80 candidate catalog performance acceptance")
struct ES80CandidateCatalogPerformanceAcceptanceTests {
    private static func repositorySource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("duplicate advertisement callbacks do not sort the presentation catalog")
    func callbackPathStaysConstantTimeForCandidatePresentationBookkeeping() throws {
        let source = try Self.repositorySource(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"
        )

        #expect(source.contains("public var discoveredPeripherals: [DiscoveredPeripheral]"))
        #expect(source.contains("latestDiscoveryByIdentifier.values.sorted"))
        #expect(!source.contains("public private(set) var discoveredPeripherals: [DiscoveredPeripheral] = []"))
        #expect(!source.contains("private func updateDiscoveryList()"))

        let callbackStart = try #require(
            source.range(
                of: "public func centralManager(\n        _ central: CBCentralManager,\n        didDiscover peripheral: CBPeripheral"
            )?.lowerBound
        )
        let nextCallback = try #require(
            source.range(
                of: "public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)",
                range: callbackStart..<source.endIndex
            )?.lowerBound
        )
        let callback = source[callbackStart..<nextCallback]

        #expect(callback.contains("latestDiscoveryByIdentifier[peripheral.identifier] = discovery"))
        #expect(!callback.contains("updateDiscoveryList()"))
        #expect(!callback.contains(".sorted"))
        #expect(callback.contains("latestAdvertisementByIdentifier[peripheral.identifier]"))
        #expect(callback.contains("enqueue(.advertisement(observation), receipt: receipt)"))
    }

    @Test("exact rediscovery checks use UUID catalog authority without materializing sorted presentation")
    func exactTargetRediscoveryUsesDictionaryLookup() throws {
        let controller = try Self.repositorySource(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"
        )
        let coordinator = try Self.repositorySource(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneCoordinator.swift"
        )

        #expect(controller.contains("func hasDiscoveredPeripheral(identifier: UUID) -> Bool"))
        #expect(controller.contains("latestDiscoveryByIdentifier[identifier] != nil"))
        #expect(coordinator.contains("controller.hasDiscoveredPeripheral(identifier: identifier)"))
        #expect(!coordinator.contains("controller.discoveredPeripherals.contains { $0.id == identifier }"))
        #expect(!coordinator.contains("controller.discoveredPeripherals.first(where: { $0.id == identifier })"))
    }

    @Test("deterministic RSSI presentation ordering remains explicit")
    func presentationSortContractRemainsDeterministic() throws {
        let source = try Self.repositorySource(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"
        )

        #expect(source.contains("DiscoveredPeripheral.sortsBefore($0, $1)"))
        #expect(source.contains("latestDiscoveryByIdentifier.values.sorted"))
    }
}
