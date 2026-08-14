import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaAppIncompleteHorizonTerminalSourceTests {
    @Test("bounded incomplete horizon uses an already-terminal package outcome")
    func incompleteHorizonDoesNotBecomeInternalLifecycleFailure() throws {
        let app = try readSemanticTerminalRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let applicationAdmission = String(try semanticTerminalSection(
            in: app,
            from: "private func receivedApplicationUpdate",
            to: "private func redactedApplicationEventDetails"
        ))
        let applicationTerminal = String(try semanticTerminalSection(
            in: applicationAdmission,
            from: "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection"
        ))

        let watchdog = String(try semanticTerminalSection(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))
        let watchdogTerminal = String(try semanticTerminalSection(
            in: watchdog,
            from: "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached",
            to: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection"
        ))

        for terminal in [applicationTerminal, watchdogTerminal] {
            #expect(terminal.contains("mirrorAlreadyTerminalIncompleteObservationHorizon"))
            #expect(!terminal.contains("invalidateIncompleteObservationHorizon"))
            #expect(!terminal.contains("invalidateInternalLifecycle"))
            #expect(!terminal.contains("markApplicationObservationTimedOut"))
            #expect(!terminal.contains("recordObservedTransportLoss"))
            #expect(!terminal.contains("endConnection"))
        }

        let mirror = String(try semanticTerminalSection(
            in: app,
            from: "private func mirrorAlreadyTerminalIncompleteObservationHorizon",
            to: "private func invalidateObservationContinuity"
        ))
        #expect(!mirror.contains("sessionLedger.markApplicationObservationTimedOut"))
        #expect(!mirror.contains("sessionLedger.markInternalLifecycleFailure"))
        #expect(!mirror.contains("sessionLedger.endConnection"))
        #expect(!mirror.contains("sessionLedger.observeCurrentConnection"))
        #expect(!mirror.contains("recordObservedTransportLoss"))
    }

    @Test("deadline liveness receipt atomically retires the exact generation")
    func livenessDeadlineIsPackageOwnedTerminal() async throws {
        let clock = SemanticTerminalClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let horizon = 2_000 + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        try await advanceSemanticLiveness(
            clock: clock,
            ledger: ledger,
            token: token,
            from: 3_000,
            untilBefore: horizon
        )
        let acceptedPrefix = await ledger.currentPreflightSnapshot()

        clock.advance(to: horizon)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.observeCurrentConnection(for: token)
        }

        let terminal = await ledger.currentPreflightSnapshot()
        expectFailedSemanticTerminal(terminal.authenticationState)
        #expect(terminal.latestObservedUptimeNanoseconds == acceptedPrefix.latestObservedUptimeNanoseconds)
        #expect(terminal.applicationPayloadCount == acceptedPrefix.applicationPayloadCount)
        #expect(terminal.latestApplicationPayloadUptimeNanoseconds == acceptedPrefix.latestApplicationPayloadUptimeNanoseconds)

        clock.advance(to: horizon + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == terminal)
    }

    @Test("deadline application receipt cannot mutate evidence and atomically retires the exact generation")
    func applicationDeadlineIsPackageOwnedTerminal() async throws {
        let clock = SemanticTerminalClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()

        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let horizon = 2_000 + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        try await advanceSemanticLiveness(
            clock: clock,
            ledger: ledger,
            token: token,
            from: 3_000,
            untilBefore: horizon
        )
        let acceptedPrefix = await ledger.currentPreflightSnapshot()

        clock.advance(to: horizon)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }

        let terminal = await ledger.currentPreflightSnapshot()
        expectFailedSemanticTerminal(terminal.authenticationState)
        #expect(terminal.latestObservedUptimeNanoseconds == acceptedPrefix.latestObservedUptimeNanoseconds)
        #expect(terminal.applicationPayloadCount == acceptedPrefix.applicationPayloadCount)
        #expect(terminal.latestApplicationPayloadUptimeNanoseconds == acceptedPrefix.latestApplicationPayloadUptimeNanoseconds)

        clock.advance(to: horizon + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == terminal)
    }

    private func expectFailedSemanticTerminal(
        _ state: TuyaAuthenticatedReadOnlyPreflightSnapshot.AuthenticationState
    ) {
        guard case let .failed(reason) = state else {
            Issue.record("Incomplete-observation horizon must become a package-owned failed terminal")
            return
        }
        #expect(reason.localizedCaseInsensitiveContains("application"))
        #expect(reason.localizedCaseInsensitiveContains("evidence"))
        #expect(!reason.localizedCaseInsensitiveContains("internal lifecycle"))
        #expect(!reason.localizedCaseInsensitiveContains("disconnect"))
    }

    private func semanticTerminalSection(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected semantic-terminal source section missing: \(start) ... \(end)")
            throw SemanticTerminalSourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readSemanticTerminalRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SemanticTerminalSourceContractError: Error {
        case sectionMissing
    }
}

private func advanceSemanticLiveness(
    clock: SemanticTerminalClock,
    ledger: TuyaAuthenticatedReadOnlySessionLedger,
    token: TuyaReadOnlyConnectionToken,
    from start: UInt64,
    untilBefore target: UInt64
) async throws {
    var cursor = start
    let gap = TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
    while cursor + gap < target {
        cursor += gap
        clock.advance(to: cursor)
        try await ledger.observeCurrentConnection(for: token)
    }
}

private final class SemanticTerminalClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

    var now: @Sendable () -> UInt64 {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    func advance(to newValue: UInt64) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
