import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One app authority wiring")
struct PassiveBluetoothExperimentOneAppAuthorityWiringTests {
    private static func fieldEntrypointSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    @Test("authenticated stationary field path binds current build and account/device authority before BLE ownership")
    func authenticatedFieldPathUsesCurrentAuthorityModel() throws {
        let source = try Self.fieldEntrypointSource()

        #expect(source.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(source.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(source.contains("var privateConfig: Bool { OfficialTuyaFactory.configured }"))
        #expect(source.contains("var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }"))
        #expect(source.contains("var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }"))
        #expect(source.contains("sdkDeviceMembershipVerified"))
        #expect(source.contains("accountIdentityLeaseIsAuthorized"))

        let lease = try #require(source.range(of: "OfficialTuyaFactory.acquirePackageCorrelationLease()"))
        let correlation = try #require(
            source.range(of: "PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)")
        )
        let officialSDKOwnership = try #require(source.range(of: "OfficialTuyaFactory.make()"))

        #expect(lease.lowerBound < correlation.lowerBound)
        #expect(correlation.lowerBound < officialSDKOwnership.lowerBound)
        #expect(!source.contains("makeResearchAuthorizedES80ForCurrentApplication()"))
        #expect(!source.contains("PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"))
        #expect(!source.contains("verifiedAdmission:"))
        #expect(!source.contains("UserDefaults"))
    }

    @Test("process BLE ownership and failed-attempt restart remain fail closed")
    func processOwnershipAndRestartRemainFailClosed() throws {
        let source = try Self.fieldEntrypointSource()

        #expect(source.contains("OfficialTuyaFactory.packageCorrelationMayStart"))
        #expect(source.contains("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"))
        #expect(source.contains("OfficialTuyaFactory.releasePackageCorrelationLease(processCorrelationLease)"))
        #expect(source.contains("private var processCorrelationLease: UUID?"))
        #expect(source.contains("private var currentConnectionToken: TuyaReadOnlyConnectionToken?"))
        #expect(source.contains("private var localBLESettlementToken: TuyaReadOnlyConnectionToken?"))

        let restartStart = try #require(source.range(of: "var failedAttemptCanRestartFromOFF1: Bool {"))
        let restartEnd = try #require(
            source.range(
                of: "var canRestartFromFreshOFF1: Bool",
                range: restartStart.upperBound..<source.endIndex
            )
        )
        let restart = source[restartStart.lowerBound..<restartEnd.lowerBound]

        #expect(restart.contains("phase == .failed"))
        #expect(restart.contains("currentConnectionToken == nil"))
        #expect(restart.contains("localBLESettlementToken == nil"))
        #expect(restart.contains("driver == nil"))
        #expect(restart.contains("OfficialTuyaFactory.packageCorrelationMayStart"))

        #expect(source.contains("func abandonCorrelationForViewExit()"))
        #expect(source.contains("private func releasePackageCorrelationLease()"))
    }
}
