import Foundation
import Testing

@Suite("ES80 Capture fresh-restart charger preflight source contract")
struct ES80CaptureFreshRestartChargerPreflightSourceTests {
    @Test("fresh Experiment One restart cannot inherit the previous charger declaration")
    func freshRestartRequiresExplicitChargerRedeclaration() throws {
        let source = try shellSource()

        let restartStart = try #require(source.range(of: "private func restartExperiment()"))
        let restartTail = source[restartStart.lowerBound...]
        let restartEnd = try #require(restartTail.range(of: "private func handleScenePhaseChange"))
        let restart = restartTail[..<restartEnd.lowerBound]

        let clearsSetup = try #require(restart.range(of: "declaredStationarySetup = nil"))
        let requiresRedeclaration = try #require(
            restart.range(of: "freshRestartRequiresChargerRedeclaration = true")
        )
        let clearsFreshChoice = try #require(
            restart.range(of: "freshRestartChargerDisconnectedDeclaration = nil")
        )
        let freshCoordinator = try #require(
            restart.range(of: "PassiveBluetoothExperimentOneCoordinator()")
        )

        #expect(clearsSetup.lowerBound < requiresRedeclaration.lowerBound)
        #expect(requiresRedeclaration.lowerBound < clearsFreshChoice.lowerBound)
        #expect(clearsFreshChoice.lowerBound < freshCoordinator.lowerBound)

        #expect(source.contains("es80.capture.restart-charger-disconnected"))
        #expect(source.contains("es80.capture.restart-charger-connected"))
        #expect(source.contains("freshRestartChargerDisconnectedDeclaration == true"))
        #expect(source.contains("disabled: !freshRestartCanConfirm"))
        #expect(source.contains("guard freshRestartCanConfirm else { return }"))
        #expect(source.contains("A fresh experiment cannot inherit the previous run's charger declaration."))
    }

    private func shellSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            root.deleteLastPathComponent()
        }
        return try String(
            contentsOf: root.appendingPathComponent(
                "NembraApp/Features/Research/ES80CaptureShellView.swift"
            ),
            encoding: .utf8
        )
    }
}
