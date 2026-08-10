import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Nembra product and Capture target bootstrap separation")
struct NembraCaptureAppBootstrapSeparationSourceTests {
    @Test("main app boots the consumer product instead of the retired direct-BLE field takeover")
    func mainAppUsesConsumerBootstrap() throws {
        let source = try read("NembraApp/App/NembraApp.swift")
        #expect(source.contains("@State private var runtime = AppBootstrap.makeRuntime()"))
        #expect(source.contains("AppRootView()"))
        #expect(source.contains(".environment(runtime.vehicleStore)"))
        #expect(source.contains(".environment(runtime.rideStore)"))
        #expect(source.contains("await runtime.start()"))
        for forbidden in ["TuyaSecureLinkPreflightView", "TuyaSecureLinkPreflightController", "CBCentralManager", "central.connect(", "6815A5F5-4D1E-E004-BAE8-6DF924123907", "currentTuyaOdometerMiles", "userTrackedLifetimeMiles", "PassiveBluetoothExperimentOneFieldExecutionGate"] {
            #expect(!source.contains(forbidden), "main app still owns retired Capture takeover token: \(forbidden)")
        }
    }

    @Test("authenticated stationary research remains owned by standalone Capture")
    func standaloneCaptureOwnsCurrentProcedure() throws {
        let source = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("ES80-AUTHENTICATED-STATIONARY-v1"))
        #expect(source.contains("SecureLinkController"))
        #expect(source.contains("scenePhase"))
    }

    private func read(_ relativePath: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
