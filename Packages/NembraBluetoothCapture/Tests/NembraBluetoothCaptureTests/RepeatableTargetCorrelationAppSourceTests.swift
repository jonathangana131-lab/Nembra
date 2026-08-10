import Foundation
import Testing

@Suite("Capture repeatable target-correlation app contract")
struct RepeatableTargetCorrelationAppSourceTests {
    private var appSource: String {
        get throws {
            let thisFile = URL(fileURLWithPath: #filePath)
            let packageRoot = thisFile
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let repositoryRoot = packageRoot
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let appURL = repositoryRoot
                .appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift")
            return try String(contentsOf: appURL, encoding: .utf8)
        }
    }

    @Test("app must not hard-code a historical CoreBluetooth UUID as scooter authority")
    func noHistoricalPeripheralUUIDAuthority() throws {
        let source = try appSource
        #expect(!source.contains("static let knownPeripheral = UUID(uuidString:"))
        #expect(!source.contains("knownID: id == knownPeripheral"))
        #expect(!source.contains("var likely: Bool { knownID }"))
        #expect(!source.contains("accepted-prior-physical-corebluetooth-uuid"))
    }

    @Test("app must consume two exact OFF to ON transitions before selection")
    func consumesRepeatedCorrelation() throws {
        let source = try appSource
        #expect(source.contains("PeripheralPowerCycleCorrelation.resolveRepeated("))
        #expect(source.contains("off1:"))
        #expect(source.contains("on1:"))
        #expect(source.contains("off2:"))
        #expect(source.contains("on2:"))
        #expect(source.contains("case let .correlated("))
    }

    @Test("correlated UUID is capture-local and still requires explicit user confirmation")
    func correlationDoesNotBecomeDurableIdentity() throws {
        let source = try appSource
        #expect(source.contains("correlated"))
        #expect(source.contains("confirmTarget"))
        #expect(source.contains(".confirmation"))
        #expect(!source.contains("verified AOVOPRO ES80 identity"))
    }
}
