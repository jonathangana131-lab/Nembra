import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture fresh-target and acquisition-terminal truth")
struct TuyaFreshTargetAndAcquisitionTerminalSourceTests {
    @Test("historical C7D09A22 peripheral UUID cannot become durable scooter identity")
    func historicalPeripheralUUIDDoesNotMintCurrentTargetAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let physicalTruth = try readRepositoryFile("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")

        #expect(physicalTruth.contains("historical capture-local evidence only"))
        #expect(physicalTruth.contains("not accepted as a durable physical scooter identity"))

        // C7D09A22's CoreBluetooth identifier may remain descriptive historical evidence,
        // but the next field attempt must not promote that historical capture-local value
        // into the sole current target authority.
        #expect(!app.contains("var likely: Bool { knownID }"))
        #expect(!app.contains("accepted prior physical UUID matched"))
        #expect(!app.contains("accepted-prior-physical-corebluetooth-uuid"))
    }

    @Test("local-BLE settlement failure does not masquerade as SDK source-authority loss")
    func localBLEAcquisitionFailureKeepsTerminalReasonDistinct() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let timedOut = app.range(of: "case .timedOut:", range: authenticated.upperBound..<app.endIndex),
              let invalidClock = app.range(of: "case .invalidClock:", range: timedOut.upperBound..<app.endIndex),
              let nextFunction = app.range(of: "private func authenticationFailed", range: invalidClock.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate the bounded local-BLE acquisition terminal branches.")
            return
        }

        let timeoutBranch = String(app[timedOut.lowerBound..<invalidClock.lowerBound])
        let invalidClockBranch = String(app[invalidClock.lowerBound..<nextFunction.lowerBound])

        // Account/login/membership drift owns markSourceAuthorityInvalidated. A local-BLE
        // acquisition timeout or monotonic-clock failure is a different physical/software fact.
        #expect(!timeoutBranch.contains("invalidateSourceAuthority"))
        #expect(!invalidClockBranch.contains("invalidateSourceAuthority"))
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
}
