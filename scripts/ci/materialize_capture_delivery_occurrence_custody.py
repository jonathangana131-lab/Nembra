#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def update(path: str, replacements: list[tuple[str, str, str]]) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    for old, new, label in replacements:
        text = replace_once(text, old, new, label)
    target.write_text(text, encoding="utf-8")


def main() -> int:
    ledger = "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
    update(ledger, [
        (
            "fileprivate let receivedAtUptimeNanoseconds: UInt64\n\n    fileprivate init(\n        token: TuyaReadOnlyConnectionToken,\n        issuerID: UUID,\n        deliveryID: UUID,\n        receivedAtUptimeNanoseconds: UInt64\n    ) {\n        self.token = token\n        self.issuerID = issuerID\n        self.deliveryID = deliveryID\n        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds\n    }",
            "fileprivate let receivedAtUptimeNanoseconds: UInt64\n    fileprivate let nonEmptyApplicationDeliveryOccurred: Bool\n\n    fileprivate init(\n        token: TuyaReadOnlyConnectionToken,\n        issuerID: UUID,\n        deliveryID: UUID,\n        receivedAtUptimeNanoseconds: UInt64,\n        nonEmptyApplicationDeliveryOccurred: Bool\n    ) {\n        self.token = token\n        self.issuerID = issuerID\n        self.deliveryID = deliveryID\n        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds\n        self.nonEmptyApplicationDeliveryOccurred = nonEmptyApplicationDeliveryOccurred\n    }",
            "seal occurrence inside opaque receipt",
        ),
        (
            "func captureApplicationReceipt(for token: TuyaReadOnlyConnectionToken) -> TuyaReadOnlyApplicationReceipt? {",
            "func captureApplicationDelivery(for token: TuyaReadOnlyConnectionToken) -> TuyaReadOnlyApplicationReceipt? {",
            "arbiter delivery capture name",
        ),
        (
            "deliveryID: UUID(),\n            receivedAtUptimeNanoseconds: nowUptimeNanoseconds()\n        )",
            "deliveryID: UUID(),\n            receivedAtUptimeNanoseconds: nowUptimeNanoseconds(),\n            nonEmptyApplicationDeliveryOccurred: true\n        )",
            "arbiter seals non-empty occurrence",
        ),
        (
            "nonisolated public func captureApplicationReceipt(\n        for token: TuyaReadOnlyConnectionToken\n    ) -> TuyaReadOnlyApplicationReceipt? {\n        applicationDeliveryArbiter.captureApplicationReceipt(for: token)\n    }",
            "nonisolated public func captureApplicationDelivery(\n        for token: TuyaReadOnlyConnectionToken\n    ) -> TuyaReadOnlyApplicationReceipt? {\n        applicationDeliveryArbiter.captureApplicationDelivery(for: token)\n    }",
            "ledger public delivery capture",
        ),
        (
            "public func recordApplicationUpdate(\n        isNonEmpty: Bool,\n        receipt: TuyaReadOnlyApplicationReceipt,\n        for token: TuyaReadOnlyConnectionToken\n    ) throws {\n        try requireCurrent(token)\n        guard case .authenticated = authenticationState else {\n            throw MutationError.authenticationRequired\n        }\n        guard isNonEmpty else {\n            throw MutationError.emptyApplicationUpdate\n        }",
            "public func recordApplicationUpdate(\n        delivery: TuyaReadOnlyApplicationReceipt,\n        for token: TuyaReadOnlyConnectionToken\n    ) throws {\n        try requireCurrent(token)\n        guard case .authenticated = authenticationState else {\n            throw MutationError.authenticationRequired\n        }\n        guard delivery.nonEmptyApplicationDeliveryOccurred else {\n            throw MutationError.emptyApplicationUpdate\n        }",
            "consumer cannot supply occurrence bit",
        ),
        (
            "applicationDeliveryArbiter.consumeApplicationReceipt(receipt, for: token)",
            "applicationDeliveryArbiter.consumeApplicationReceipt(delivery, for: token)",
            "consume opaque delivery",
        ),
        (
            "let now = receipt.receivedAtUptimeNanoseconds",
            "let now = delivery.receivedAtUptimeNanoseconds",
            "delivery owns chronology",
        ),
    ])

    app = "NembraApp/App/NembraCaptureEntrypoint.swift"
    update(app, [
        (
            "guard let applicationReceipt = sessionLedger.captureApplicationReceipt(for: token) else {",
            "guard let applicationDelivery = sessionLedger.captureApplicationDelivery(for: token) else {",
            "trusted callback seals delivery",
        ),
        (
            "await receivedApplicationUpdate(update, receipt: applicationReceipt, token: token)",
            "await receivedApplicationUpdate(update, delivery: applicationDelivery, token: token)",
            "async receiver receives sealed delivery",
        ),
        (
            "receipt: TuyaReadOnlyApplicationReceipt,\n        token: TuyaReadOnlyConnectionToken",
            "delivery: TuyaReadOnlyApplicationReceipt,\n        token: TuyaReadOnlyConnectionToken",
            "receiver delivery parameter",
        ),
        (
            "try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, receipt: receipt, for: token)",
            "try await sessionLedger.recordApplicationUpdate(delivery: delivery, for: token)",
            "public consumer has no occurrence bit",
        ),
    ])

    seal_test = "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift"
    update(seal_test, [
        (
            "receivedApplicationUpdate(update, receipt: applicationReceipt, token: token)",
            "receivedApplicationUpdate(update, delivery: applicationDelivery, token: token)",
            "seal source contract follows opaque delivery",
        )
    ])

    cutoff = "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationDeliveryCutoffSourceTests.swift"
    update(cutoff, [
        ("captureApplicationReceipt(for: token)", "captureApplicationDelivery(for: token)", "delivery-cutoff capture spelling"),
        ("captureApplicationReceipt(for token: TuyaReadOnlyConnectionToken)", "captureApplicationDelivery(for token: TuyaReadOnlyConnectionToken)", "ledger capture declaration spelling"),
        ("captureApplicationReceipt(for token: TuyaReadOnlyConnectionToken, receivedAtUptimeNanoseconds:", "captureApplicationDelivery(for token: TuyaReadOnlyConnectionToken, receivedAtUptimeNanoseconds:", "forbid caller timestamp spelling"),
        ("applicationDeliveryArbiter.captureApplicationReceipt(for: token)", "applicationDeliveryArbiter.captureApplicationDelivery(for: token)", "arbiter capture spelling"),
        ("receivedApplicationUpdate(update, receipt: applicationReceipt, token: token)", "receivedApplicationUpdate(update, delivery: applicationDelivery, token: token)", "receiver call spelling"),
        ("#expect(receiver.contains(\"receipt: TuyaReadOnlyApplicationReceipt\"))", "#expect(receiver.contains(\"delivery: TuyaReadOnlyApplicationReceipt\"))", "receiver opaque delivery contract"),
        ("#expect(receiver.contains(\"recordApplicationUpdate(isNonEmpty: !update.isEmpty, receipt: receipt, for: token)\"))", "#expect(receiver.contains(\"recordApplicationUpdate(delivery: delivery, for: token)\"))\n        #expect(!receiver.contains(\"recordApplicationUpdate(isNonEmpty:\"))", "consumer occurrence custody contract"),
        ("#expect(record.contains(\"receipt: TuyaReadOnlyApplicationReceipt\"))", "#expect(record.contains(\"delivery: TuyaReadOnlyApplicationReceipt\"))\n        #expect(!record.contains(\"isNonEmpty: Bool\"))\n        #expect(record.contains(\"delivery.nonEmptyApplicationDeliveryOccurred\"))", "public mutation seals occurrence"),
        ("applicationDeliveryArbiter.consumeApplicationReceipt(receipt, for: token)", "applicationDeliveryArbiter.consumeApplicationReceipt(delivery, for: token)", "cutoff consume spelling"),
        ("let now = receipt.receivedAtUptimeNanoseconds", "let now = delivery.receivedAtUptimeNanoseconds", "cutoff delivery chronology spelling"),
    ])

    arbitration = "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationReceiptArbitrationSourceTests.swift"
    update(arbitration, [
        ("applicationDeliveryArbiter.consumeApplicationReceipt(receipt, for: token)", "applicationDeliveryArbiter.consumeApplicationReceipt(delivery, for: token)", "arbitration consume spelling"),
    ])

    runtime = "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationReceiptAuthorityTests.swift"
    target = ROOT / runtime
    text = target.read_text(encoding="utf-8")
    text = text.replace("captureApplicationReceipt(for:", "captureApplicationDelivery(for:")
    text = text.replace("recordApplicationUpdate(isNonEmpty: true, receipt: ", "recordApplicationUpdate(delivery: ")
    text = text.replace(", for: ", ", for: ")
    # The replacement above leaves valid `recordApplicationUpdate(delivery: receipt, for: token)` calls.
    target.write_text(text, encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
