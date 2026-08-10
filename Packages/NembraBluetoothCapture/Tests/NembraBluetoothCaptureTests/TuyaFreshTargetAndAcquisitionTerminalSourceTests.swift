import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture fresh-target and acquisition-terminal truth")
struct TuyaFreshTargetAndAcquisitionTerminalSourceTests {
    @Test("historical C7D09A22 peripheral UUID cannot become current target authority")
    func historicalPeripheralUUIDDoesNotMintCurrentTargetAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let candidateStart = app.range(of: "struct Candidate:"),
              let candidateEnd = app.range(of: "enum Phase:", range: candidateStart.upperBound..<app.endIndex),
              let finishStart = app.range(of: "private func finishCorrelationSeries("),
              let finishEnd = app.range(of: "func invalidateSDKMembership()", range: finishStart.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate current target-authority source boundaries.")
            return
        }

        let candidateAuthority = String(app[candidateStart.lowerBound..<candidateEnd.lowerBound])
        let correlationPromotion = String(app[finishStart.lowerBound..<finishEnd.lowerBound])

        // The historical C7D09A22 CoreBluetooth identifier may remain descriptive evidence,
        // but only the fresh package-owned repeated correlation may mint current-session authority.
        #expect(candidateAuthority.contains("var likely: Bool { freshlyCorrelated }"))
        #expect(!candidateAuthority.contains("var likely: Bool { knownID }"))
        #expect(app.contains("historicalCapturePeripheral"))
        #expect(correlationPromotion.contains("fresh-repeated-off-on-full-corebluetooth-id"))
        #expect(correlationPromotion.contains("matches C7D09A22 capture-local UUID descriptive"))
        #expect(correlationPromotion.contains("not permanent scooter identity"))

        #expect(!app.contains("accepted prior physical UUID matched"))
        #expect(!app.contains("accepted-prior-physical-corebluetooth-uuid"))
    }

    @Test("fresh target authority consumes the package-owned four-window producer")
    func currentTargetRequiresPackageOwnedRepeatedCorrelation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))
        #expect(app.contains("case let .singleRepeatableCandidate(id):"))
        #expect(app.contains("case let .ambiguousRepeatableCandidates(ids):"))
        #expect(app.contains("case .noRepeatableCandidate:"))
        #expect(app.contains("case .invalidObservationAuthority, .invalidObservationWindowOrder:"))
        #expect(app.contains("freshlyCorrelated: true"))
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
        #expect(timeoutBranch.contains("authenticationAcquisitionFailed"))
        #expect(invalidClockBranch.contains("authenticationAcquisitionFailed"))
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
