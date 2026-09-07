import Foundation
import Testing

@Suite("Tuya authenticated read-only safety contract")
struct TuyaAuthenticatedReadOnlySafetySourceTests {
    @Test("physical preflight cannot expose generic BLE or DP writes")
    func preflightSurfaceRemainsReadOnly() throws {
        let source = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlyPreflight.swift"
        )

        #expect(source.contains("public protocol TuyaReadOnlyAuthenticationSessionProvider"))
        #expect(source.contains("func currentPreflightSnapshot() async -> TuyaAuthenticatedReadOnlyPreflightSnapshot"))
        #expect(!source.contains("func write"))
        #expect(!source.contains("writeValue("))
        #expect(!source.contains("publishDps"))
        #expect(!source.contains("publishDPS"))
        #expect(!source.contains("unbind"))
        #expect(!source.contains("factoryReset"))
    }

    @Test("physical acceptance stays strictly beyond the historical rejection boundary")
    func historicalBoundaryRemainsStrict() throws {
        let source = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlyPreflight.swift"
        )

        #expect(source.contains("minimumPostAuthenticationPayloadSurvivalNanoseconds: UInt64 = 30_000_000_000"))
        #expect(source.contains("latestPayload - authenticatedAt > minimumPostAuthenticationPayloadSurvivalNanoseconds"))
        #expect(source.contains("minimumAuthenticatedConnectionNanoseconds: UInt64 = 45_000_000_000"))
        #expect(source.contains("minimumAuthenticatedApplicationPayloadCount = 2"))
    }

    @Test("only official SmartLife SDK provenance can mint physical readiness")
    func officialSDKProvenanceRemainsRequired() throws {
        let source = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlyPreflight.swift"
        )

        #expect(source.contains("authenticationMethod == .smartLifeAppSDK"))
        #expect(source.contains("cloud `local_key` alone is never accepted authentication provenance"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return String(decoding: data, as: UTF8.self)
    }
}
