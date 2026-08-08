import Foundation
import XCTest

/// Expected-red app wiring contract for the V14 ES80 field vertical.
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
    }

    func testResearchLaunchDoesNotMintGenericControllerAsFieldAuthority() throws {
        let app = try source(at: "NembraApp/App/NembraApp.swift")

        XCTAssertFalse(
            app.contains("try? ForegroundCoreBluetoothCaptureController("),
            "A future physical-GO launch must obtain its controller through the package-owned Experiment One workflow; direct generic-controller construction cannot become field authority."
        )
    }

    func testBindingLockedStateCannotBeTheAuthorizedGoTerminal() throws {
        let shell = try source(at: "NembraApp/Features/Research/ES80CaptureShellView.swift")

        XCTAssertFalse(
            shell.contains("Passive capture binding not available in this build"),
            "Before physical GO can be earned, the app-visible workflow must continue the same package-owned authority through passive acquisition, Ready, Horizon, immutable seal, analysis, and Share rather than terminating at a permanent binding lock."
        )
    }
}
