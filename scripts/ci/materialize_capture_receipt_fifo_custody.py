#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def update_file(relative: str, fn) -> None:
    path = ROOT / relative
    text = path.read_text(encoding="utf-8")
    path.write_text(fn(text), encoding="utf-8")


def update_ledger(text: str) -> str:
    text = replace_once(
        text,
        '''    public nonisolated func captureApplicationReceipt(
        isNonEmpty: Bool,
        for token: TuyaReadOnlyConnectionToken
    ) throws -> TuyaReadOnlyApplicationReceipt {
        try receiptAuthority.captureApplicationReceipt(isNonEmpty: isNonEmpty, for: token)
    }
''',
        '''    public nonisolated func captureApplicationDelivery(
        for token: TuyaReadOnlyConnectionToken
    ) throws -> TuyaReadOnlyApplicationReceipt {
        try receiptAuthority.captureApplicationDelivery(for: token)
    }
''',
        "public delivery mint removes caller occurrence bit",
    )
    text = replace_once(
        text,
        "        private var pendingApplicationSequences: Set<UInt64> = []\n",
        "        private var pendingApplicationSequences: [UInt64] = []\n",
        "ordered pending application storage",
    )
    text = replace_once(
        text,
        '''        func captureApplicationReceipt(
            isNonEmpty: Bool,
            for token: TuyaReadOnlyConnectionToken
        ) throws -> TuyaReadOnlyApplicationReceipt {
            lock.lock()
            defer { lock.unlock() }
            try requireActive(token)
            guard isNonEmpty else { throw MutationError.emptyApplicationUpdate }
            let (sequence, now) = try issueNextReceipt()
            pendingApplicationSequences.insert(sequence)
            return TuyaReadOnlyApplicationReceipt(
''',
        '''        func captureApplicationDelivery(
            for token: TuyaReadOnlyConnectionToken
        ) throws -> TuyaReadOnlyApplicationReceipt {
            lock.lock()
            defer { lock.unlock() }
            try requireActive(token)
            let (sequence, now) = try issueNextReceipt()
            pendingApplicationSequences.append(sequence)
            return TuyaReadOnlyApplicationReceipt(
''',
        "receipt authority seals trusted delivery without caller bool",
    )
    text = replace_once(
        text,
        '''        func releaseApplicationReceipt(_ receipt: TuyaReadOnlyApplicationReceipt) {
            lock.lock()
            defer { lock.unlock() }
            guard receipt.issuerID == issuerID else { return }
            pendingApplicationSequences.remove(receipt.deliverySequence)
        }
''',
        '''        func releaseApplicationReceipt(_ receipt: TuyaReadOnlyApplicationReceipt) {
            lock.lock()
            defer { lock.unlock() }
            guard receipt.issuerID == issuerID,
                  let index = pendingApplicationSequences.firstIndex(of: receipt.deliverySequence) else { return }
            pendingApplicationSequences.remove(at: index)
        }
''',
        "ordered receipt release",
    )
    text = replace_once(
        text,
        '''            guard receipt.issuerID == issuerID,
                  receipt.token == token,
                  pendingApplicationSequences.remove(receipt.deliverySequence) != nil else {
                throw MutationError.observationAdmissionInvalidOrConsumed
            }
            return receipt.receivedAtUptimeNanoseconds
''',
        '''            guard receipt.issuerID == issuerID,
                  receipt.token == token else {
                throw MutationError.observationAdmissionInvalidOrConsumed
            }
            guard let first = pendingApplicationSequences.first else {
                throw MutationError.observationAdmissionInvalidOrConsumed
            }
            guard first == receipt.deliverySequence else {
                guard pendingApplicationSequences.contains(receipt.deliverySequence) else {
                    throw MutationError.observationAdmissionInvalidOrConsumed
                }
                throw MutationError.applicationAdmissionPending
            }
            pendingApplicationSequences.removeFirst()
            return receipt.receivedAtUptimeNanoseconds
''',
        "package FIFO consumption fence",
    )
    return text


def update_app(text: str) -> str:
    return replace_once(
        text,
        '''applicationReceipt = try self.sessionLedger.captureApplicationReceipt(
                                isNonEmpty: true,
                                for: token
                            )''',
        '''applicationReceipt = try self.sessionLedger.captureApplicationDelivery(
                                for: token
                            )''',
        "shipping callback delivery mint",
    )


def update_source_oracle(text: str) -> str:
    text = replace_once(
        text,
        'body.range(of: "self.sessionLedger.captureApplicationReceipt(")',
        'body.range(of: "self.sessionLedger.captureApplicationDelivery(")',
        "callback source oracle delivery mint",
    )
    text = replace_once(
        text,
        '''        #expect(ledger.contains("public nonisolated func captureApplicationReceipt("))
        #expect(ledger.contains("isNonEmpty: Bool"))
        #expect(ledger.contains("guard isNonEmpty else { throw MutationError.emptyApplicationUpdate }"))
''',
        '''        #expect(ledger.contains("public nonisolated func captureApplicationDelivery("))
        #expect(!ledger.contains("public nonisolated func captureApplicationReceipt("))
''',
        "receipt source oracle removes caller occurrence bit",
    )
    text = replace_once(
        text,
        '''        #expect(ledger.contains("pendingApplicationSequences.remove(receipt.deliverySequence) != nil"))
        #expect(ledger.contains("guard pendingApplicationSequences.isEmpty else"))
''',
        '''        #expect(ledger.contains("private var pendingApplicationSequences: [UInt64] = []"))
        #expect(ledger.contains("pendingApplicationSequences.append(sequence)"))
        #expect(ledger.contains("guard let first = pendingApplicationSequences.first else"))
        #expect(ledger.contains("guard first == receipt.deliverySequence else"))
        #expect(ledger.contains("throw MutationError.applicationAdmissionPending"))
        #expect(ledger.contains("pendingApplicationSequences.removeFirst()"))
        #expect(ledger.contains("guard pendingApplicationSequences.isEmpty else"))
''',
        "receipt source oracle requires package FIFO",
    )
    return text


def update_ledger_tests(text: str) -> str:
    helper_tail = '''    while cursor < target {
        cursor = min(target, cursor + gap)
        clock.advance(to: cursor)
        try await ledger.observeCurrentConnection(for: token)
    }

    @Test("pre-cut application delivery remains pre-cut when actor admission happens after the deadline")
'''
    text = replace_once(
        text,
        helper_tail,
        '''    while cursor < target {
        cursor = min(target, cursor + gap)
        clock.advance(to: cursor)
        try await ledger.observeCurrentConnection(for: token)
    }
}

extension TuyaAuthenticatedReadOnlySessionLedgerTests {
    @Test("pre-cut application delivery remains pre-cut when actor admission happens after the deadline")
''',
        "move receipt tests out of helper scope",
    )

    text = text.replace(
        "captureApplicationReceipt(isNonEmpty: true, for:",
        "captureApplicationDelivery(for:",
    )
    text = replace_once(
        text,
        '''            try await secondLedger.recordApplicationUpdate(
                isNonEmpty: true,
                receipt: foreignReceipt,
                for: secondToken
            )''',
        '''            try await secondLedger.recordApplicationUpdate(
                receipt: foreignReceipt,
                for: secondToken
            )''',
        "remove stale cross-ledger consumer signature",
    )

    fifo_test = '''
    @Test("package consumes application deliveries in issuance order before evidence mutation")
    func applicationDeliveryFIFOIsPackageOwned() async throws {
        let clock = TestUptimeClock(10_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedToken(ledger: ledger, clock: clock, base: 10_000)

        clock.advance(to: 10_010)
        let first = try ledger.captureApplicationDelivery(for: token)
        clock.advance(to: 10_020)
        let second = try ledger.captureApplicationDelivery(for: token)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationAdmissionPending) {
            try await ledger.recordApplicationUpdate(receipt: second, for: token)
        }
        #expect((await ledger.currentPreflightSnapshot()).applicationPayloadCount == 0)

        try await ledger.recordApplicationUpdate(receipt: first, for: token)
        try await ledger.recordApplicationUpdate(receipt: second, for: token)
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 2)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 10_020)
        #expect(snapshot.latestObservedUptimeNanoseconds == 10_020)
    }
'''
    text = replace_once(
        text,
        "\n}\n\nprivate final class TestUptimeClock",
        fifo_test + "\n}\n\nprivate final class TestUptimeClock",
        "add suite-scope package FIFO regression",
    )
    return text


def main() -> int:
    update_file(
        "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift",
        update_ledger,
    )
    update_file("NembraApp/App/NembraCaptureEntrypoint.swift", update_app)
    update_file(
        "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift",
        update_source_oracle,
    )
    update_file(
        "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAuthenticatedReadOnlySessionLedgerTests.swift",
        update_ledger_tests,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
