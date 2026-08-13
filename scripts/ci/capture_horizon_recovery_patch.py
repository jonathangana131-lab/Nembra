#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

ledger = ROOT / 'Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift'
source = ledger.read_text()

reason_anchor = '''    private static let internalLifecycleFailureReason =
        "Session authority was retired after an internal lifecycle or chronology failure."
'''
reason_replacement = reason_anchor + '''    private static let incompleteObservationFailureReason =
        "Authenticated session reached the incomplete-observation horizon before canonical readiness."
'''
assert source.count(reason_anchor) == 1
source = source.replace(reason_anchor, reason_replacement, 1)

comment_anchor = '''    /// chronology; the exact token stays current on throw so the app's existing fail-closed
    /// lifecycle terminal can retire it without inventing a BLE disconnect or a second clock sample.
'''
comment_replacement = '''    /// chronology. Crossing the horizon atomically retires package callback authority without
    /// inventing a BLE disconnect or sampling a second timestamp; the app only mirrors that terminal.
'''
assert source.count(comment_anchor) == 1
source = source.replace(comment_anchor, comment_replacement, 1)

terminal_anchor = '''        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: makeSnapshot()) != .readyForStationaryMapping else {
            return
        }
        throw MutationError.incompleteObservationHorizonReached
'''
terminal_replacement = '''        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: makeSnapshot()) != .readyForStationaryMapping else {
            return
        }
        authenticationState = .failed(reason: Self.incompleteObservationFailureReason)
        currentToken = nil
        throw MutationError.incompleteObservationHorizonReached
'''
assert source.count(terminal_anchor) == 1
source = source.replace(terminal_anchor, terminal_replacement, 1)
ledger.write_text(source)

horizon = ROOT / 'Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAuthenticatedReadOnlyHorizonTests.swift'
tests = horizon.read_text()

first_anchor = '''        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestObservedUptimeNanoseconds == acceptedPrefix.latestObservedUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) != .readyForStationaryMapping)
    }

    @Test("application callback cannot rescue an expired incomplete generation")
'''
first_replacement = '''        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .failed(reason: "Authenticated session reached the incomplete-observation horizon before canonical readiness."))
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestObservedUptimeNanoseconds == acceptedPrefix.latestObservedUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) != .readyForStationaryMapping)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markInternalLifecycleFailure(for: token)
        }
    }

    @Test("application callback cannot rescue an expired incomplete generation")
'''
assert tests.count(first_anchor) == 1
tests = tests.replace(first_anchor, first_replacement, 1)

second_anchor = '''        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == acceptedPrefix.latestApplicationPayloadUptimeNanoseconds)
        #expect(snapshot.latestObservedUptimeNanoseconds == acceptedPrefix.latestObservedUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) != .readyForStationaryMapping)
    }

    @Test("Device Sharing provenance cannot enter authenticated BLE chronology")
'''
second_replacement = '''        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .failed(reason: "Authenticated session reached the incomplete-observation horizon before canonical readiness."))
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == acceptedPrefix.latestApplicationPayloadUptimeNanoseconds)
        #expect(snapshot.latestObservedUptimeNanoseconds == acceptedPrefix.latestObservedUptimeNanoseconds)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) != .readyForStationaryMapping)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markInternalLifecycleFailure(for: token)
        }
    }

    @Test("Device Sharing provenance cannot enter authenticated BLE chronology")
'''
assert tests.count(second_anchor) == 1
tests = tests.replace(second_anchor, second_replacement, 1)
horizon.write_text(tests)

ledger_tests = ROOT / 'Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAuthenticatedReadOnlySessionLedgerTests.swift'
suite = ledger_tests.read_text()
start = suite.index('    @Test("clock regression cannot rewrite accepted chronology")')
end = suite.index('    @Test("disconnect remains a distinct transport-loss terminal")', start)
block = suite[start:end]
old_method = 'try await ledger.markAuthenticated(for: token, method: .documentedDeviceSharing)'
assert block.count(old_method) == 1
block = block.replace(old_method, 'try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)', 1)
ledger_tests.write_text(suite[:start] + block + suite[end:])
