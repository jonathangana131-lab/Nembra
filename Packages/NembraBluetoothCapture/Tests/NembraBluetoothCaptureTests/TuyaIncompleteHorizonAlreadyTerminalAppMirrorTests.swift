import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya incomplete-horizon app terminal mirroring")
struct TuyaIncompleteHorizonAlreadyTerminalAppMirrorTests {
    @Test("package horizon throw has already retired exact callback authority")
    func horizonThrowIsAlreadyTerminal() async throws {
        let clock = MirrorHorizonClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let horizon = 2_000 + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        var cursor: UInt64 = 3_000
        let gap = TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
        while cursor + gap < horizon {
            cursor += gap
            clock.advance(to: cursor)
            try await ledger.observeCurrentConnection(for: token)
        }

        let acceptedPrefix = await ledger.currentPreflightSnapshot()
        clock.advance(to: horizon)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }

        let terminal = await ledger.currentPreflightSnapshot()
        #expect(terminal.applicationPayloadCount == acceptedPrefix.applicationPayloadCount)
        #expect(terminal.latestApplicationPayloadUptimeNanoseconds == acceptedPrefix.latestApplicationPayloadUptimeNanoseconds)
        #expect(terminal.latestObservedUptimeNanoseconds == acceptedPrefix.latestObservedUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: terminal) != .readyForStationaryMapping)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markInternalLifecycleFailure(for: token)
        }
    }

    @Test("canonical app repair mirrors package terminal instead of trying to retire it twice")
    func canonicalRepairDoesNotDoubleRetireHorizon() throws {
        let workflow = try readRepositoryFile(".github/workflows/capture-app-horizon-patch-go.yml")

        let receipt = try sourceSection(
            workflow,
            from: "receipt_catch =",
            to: "one(receipt_anchor"
        )
        let watchdog = try sourceSection(
            workflow,
            from: "watchdog_catch =",
            to: "one(watchdog_anchor"
        )

        #expect(receipt.contains("incompleteObservationHorizonReached"))
        #expect(watchdog.contains("incompleteObservationHorizonReached"))
        #expect(receipt.contains("mirrorAlreadyTerminalIncompleteObservationHorizon"))
        #expect(watchdog.contains("mirrorAlreadyTerminalIncompleteObservationHorizon"))
        #expect(!receipt.contains("invalidateInternalLifecycle"))
        #expect(!watchdog.contains("invalidateInternalLifecycle"))
    }

    private func sourceSection(_ source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw SourceContractError.sectionMissing
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}

private final class MirrorHorizonClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

    func now() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(to newValue: UInt64) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
