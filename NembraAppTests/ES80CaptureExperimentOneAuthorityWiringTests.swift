import Foundation
import XCTest

/// App wiring contract for the V14 ES80 field vertical.
///
/// The app may present package-owned Experiment One state, but it must not create a public
/// four-window producer and a generic foreground controller as two independent evidence lives.
/// This is software authority QA only; it establishes no physical ES80 identity or protocol truth.
final class ES80CaptureExperimentOneAuthorityWiringTests: XCTestCase {
    private func source(at relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func testCaptureShellDoesNotMintStandalonePublicCorrelationProducer() throws {
        let shell = try source(at: "NembraApp/Features/Research/ES80CaptureShellView.swift")

        XCTAssertFalse(
            shell.contains("PassiveBluetoothPowerCycleObservationSession("),
            "The product shell must consume one package-owned Experiment One workflow instead of minting a public four-window producer that cannot share the sealed recorder authority."
        )
        XCTAssertTrue(
            shell.contains("PassiveBluetoothExperimentOneCoordinator"),
            "The Capture shell must retain the canonical package-owned Experiment One coordinator."
        )
    }

    func testResearchLaunchDoesNotMintGenericControllerAsFieldAuthority() throws {
        let app = try source(at: "NembraApp/App/NembraApp.swift")

        XCTAssertFalse(
            app.contains("try? ForegroundCoreBluetoothCaptureController("),
            "A future physical-GO launch must obtain its controller through the package-owned Experiment One workflow; direct generic-controller construction cannot become field authority."
        )
        XCTAssertTrue(
            app.contains("PassiveBluetoothExperimentOneCoordinator()"),
            "The research bootstrap must create the package-owned Experiment One coordinator rather than parallel controller authority."
        )
    }

    func testAuthorizedWorkflowAdvancesPastCorrelationBindingDeadEndWithoutExposingFinish() throws {
        let shell = try source(at: "NembraApp/Features/Research/ES80CaptureShellView.swift")

        XCTAssertFalse(
            shell.contains("Passive capture binding not available in this build"),
            "The app-visible workflow must not terminate at the old split-authority binding lock."
        )
        XCTAssertTrue(
            shell.contains("coordinator.connectPreparedCapture()"),
            "Exact-target reacquisition must hand off through the same package-owned Experiment One coordinator."
        )
        XCTAssertTrue(
            shell.contains("Begin passive capture"),
            "The authorized shell must advance from fresh target reacquisition into same-authority passive acquisition."
        )
        XCTAssertFalse(
            shell.contains("Finish Capture"),
            "Finish must remain unavailable until exact H/seal/integrity/export authority is app-wired and accepted."
        )
    }
}
