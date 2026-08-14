import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application timeout presentation race post-await phase fence repair")
struct TuyaApplicationTimeoutPresentationRaceSourceTestsPostAwaitPhaseFenceRepair {
    @Test("continuity mirror publishes package terminal only while observation still owns presentation")
    func continuityMirrorUsesPostAwaitPhaseFence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let mirror = try section(
            in: source,
            from: "private func mirrorAlreadyTerminalObservationContinuity",
            to: "private func mirrorAlreadyTerminalIncompleteObservationHorizon"
        )
        try requireNarrowPhaseFence(in: String(mirror))
    }

    @Test("incomplete horizon mirror publishes package terminal only while observation still owns presentation")
    func incompleteHorizonMirrorUsesPostAwaitPhaseFence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let mirror = try section(
            in: source,
            from: "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
            to: "private func invalidateObservationContinuity"
        )
        try requireNarrowPhaseFence(in: String(mirror))
    }

    private func requireNarrowPhaseFence(in mirror: String) throws {
        let tokenGuard = try offset("guard currentConnectionToken == token", in: mirror)
        let tokenClear = try offset("currentConnectionToken = nil", in: mirror, after: tokenGuard)
        let refresh = try offset("await refreshLedgerSnapshot()", in: mirror, after: tokenClear)
        let phaseFence = try offset("guard phase == .observing else { return }", in: mirror, after: refresh)
        let failure = try offset("phase = .failed", in: mirror, after: phaseFence)
        let message = try offset("self.message = message", in: mirror, after: failure)

        #expect(tokenGuard < tokenClear)
        #expect(tokenClear < refresh)
        #expect(refresh < phaseFence)
        #expect(phaseFence < failure)
        #expect(failure < message)
        #expect(!mirror.contains("officialConnectionRequestID"))
        #expect(!mirror.contains("sessionLedger."))
        #expect(!mirror.contains("markApplicationObservationTimedOut"))
        #expect(!mirror.contains("markInternalLifecycleFailure"))
        #expect(!mirror.contains("endConnection"))
        #expect(!mirror.contains("recordObservedTransportLoss"))
    }

    private func offset(_ token: String, in source: String, after lower: String.Index? = nil) throws -> String.Index {
        let start = lower ?? source.startIndex
        guard let range = source.range(of: token, range: start..<source.endIndex) else {
            Issue.record("Missing terminal-mirror phase-fence contract: \(token)")
            throw SourceContractError.requiredTokenMissing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Missing source section: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
        case requiredTokenMissing
    }
}
