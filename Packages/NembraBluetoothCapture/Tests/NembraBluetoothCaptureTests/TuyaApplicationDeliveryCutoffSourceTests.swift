import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Source contract for the exact boundary where SmartLife delivers an application callback before
/// the app creates a new Task. A callback delivered before the package-owned incomplete-observation
/// cutoff must not become late merely because its async ledger admission is scheduled later.
extension TuyaApplicationTimeoutPresentationRaceSourceTests {
    @Test("SmartLife delivery crosses synchronous admission before any new MainActor task")
    func deliveredApplicationCallbackOwnsItsCutoffBeforeTaskScheduling() throws {
        let app = try deliveryCutoffReadRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let connection = String(try deliveryCutoffSection(
            in: app,
            from: "newDriver.connect(",
            to: "private func authenticated(token:"
        ))
        let callback = String(try deliveryCutoffSection(
            in: connection,
            from: "onApplicationUpdate: { [weak self] update in",
            to: "sourceAuthorityFailure:"
        ))

        #expect(callback.contains("admitApplicationUpdateCallback(update, token: token)"))
        #expect(!callback.contains("Task { @MainActor"))

        let admission = String(try deliveryCutoffSection(
            in: app,
            from: "private func admitApplicationUpdateCallback(",
            to: "private func receivedApplicationUpdate("
        ))
        let receipt = try deliveryCutoffRequiredOffset(
            "let applicationReceipt = sessionLedger.captureApplicationReceipt(for: token)",
            in: admission
        )
        let inFlight = try deliveryCutoffRequiredOffset(
            "applicationUpdateAdmissionsInFlight += 1",
            in: admission,
            after: receipt
        )
        let asyncHop = try deliveryCutoffRequiredOffset(
            "Task { @MainActor",
            in: admission,
            after: inFlight
        )
        let deferFence = try deliveryCutoffRequiredOffset(
            "defer {",
            in: admission,
            after: asyncHop
        )
        let release = try deliveryCutoffRequiredOffset(
            "applicationUpdateAdmissionsInFlight -= 1",
            in: admission,
            after: deferFence
        )
        let receiverCall = try deliveryCutoffRequiredOffset(
            "receivedApplicationUpdate(update, receipt: applicationReceipt, token: token)",
            in: admission,
            after: release
        )

        #expect(receipt < inFlight)
        #expect(inFlight < asyncHop)
        #expect(asyncHop < deferFence)
        #expect(deferFence < release)
        #expect(release < receiverCall)
        #expect(deliveryCutoffOccurrenceCount("captureApplicationReceipt(for: token)", in: app) == 1)
        #expect(!app.contains("TuyaReadOnlyApplicationReceipt.capture"))

        let receiver = String(try deliveryCutoffSection(
            in: app,
            from: "private func receivedApplicationUpdate(",
            to: "private func redactedApplicationEventDetails("
        ))
        #expect(receiver.contains("receipt: TuyaReadOnlyApplicationReceipt"))
        #expect(receiver.contains("recordApplicationUpdate(isNonEmpty: !update.isEmpty, receipt: receipt, for: token)"))
        #expect(!receiver.contains("applicationUpdateAdmissionsInFlight += 1"))
        #expect(!receiver.contains("applicationUpdateAdmissionsInFlight -= 1"))

        let watchdog = String(try deliveryCutoffSection(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))
        let pendingFence = try deliveryCutoffRequiredOffset(
            "applicationUpdateAdmissionsInFlight > 0",
            in: watchdog
        )
        let livenessMutation = try deliveryCutoffRequiredOffset(
            "try await self.sessionLedger.observeCurrentConnection(for: token)",
            in: watchdog,
            after: pendingFence
        )
        #expect(pendingFence < livenessMutation)
    }

    @Test("delivery receipt is ledger-issued token-bound timestamp-opaque and one-shot")
    func applicationReceiptCannotBeCrossLedgerForgedOrReused() throws {
        let ledger = try deliveryCutoffReadRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let receiptType = String(try deliveryCutoffSection(
            in: ledger,
            from: "public struct TuyaReadOnlyApplicationReceipt",
            to: "private final class TuyaApplicationDeliveryArbiter"
        ))

        #expect(receiptType.contains("fileprivate let token: TuyaReadOnlyConnectionToken"))
        #expect(receiptType.contains("fileprivate let issuerID: UUID"))
        #expect(receiptType.contains("fileprivate let deliveryID: UUID"))
        #expect(receiptType.contains("fileprivate let receivedAtUptimeNanoseconds: UInt64"))
        #expect(!receiptType.contains("public init("))
        #expect(!receiptType.contains("public static func capture"))

        #expect(ledger.contains("applicationReceiptIssuerID"))
        #expect(ledger.contains("consumedApplicationDeliveryIDs"))
        #expect(ledger.contains("nonisolated public func captureApplicationReceipt(for token: TuyaReadOnlyConnectionToken)"),
                Comment(rawValue: "Receipt capture must be synchronous at SDK delivery; an actor hop before timestamping recreates scheduler-defined chronology."))

        let capture = String(try deliveryCutoffSection(
            in: ledger,
            from: "nonisolated public func captureApplicationReceipt(for token: TuyaReadOnlyConnectionToken)",
            to: "public func recordApplicationUpdate("
        ))
        #expect(capture.contains("applicationDeliveryArbiter.captureApplicationReceipt(for: token)"))
        #expect(!ledger.contains("captureApplicationReceipt(for token: TuyaReadOnlyConnectionToken, receivedAtUptimeNanoseconds:"),
                Comment(rawValue: "The public capture API must not accept caller-selected receipt time."))

        let record = String(try deliveryCutoffSection(
            in: ledger,
            from: "public func recordApplicationUpdate(",
            to: "public func observeCurrentConnection("
        ))
        #expect(record.contains("receipt: TuyaReadOnlyApplicationReceipt"))
        #expect(record.contains("applicationDeliveryArbiter.consumeApplicationReceipt(receipt, for: token)"))
        #expect(record.contains("let now = receipt.receivedAtUptimeNanoseconds"))
        #expect(!record.contains("receivedAtUptimeNanoseconds: UInt64"))
        #expect(!record.contains("let now = try nextMonotonicObservation()"))
        #expect(record.contains("try requireContinuousAuthenticatedObservation(at: now)"))
        #expect(record.contains("try requireIncompleteObservationHorizonOpen(at: now)"))
    }

    private func deliveryCutoffOccurrenceCount(_ needle: String, in source: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return source.components(separatedBy: needle).count - 1
    }

    private func deliveryCutoffRequiredOffset(
        _ token: String,
        in source: String,
        after lowerBound: String.Index? = nil
    ) throws -> String.Index {
        let lower = lowerBound ?? source.startIndex
        guard let range = source.range(of: token, range: lower..<source.endIndex) else {
            Issue.record("Expected delivered-callback cutoff contract missing: \(token)")
            throw DeliveryCutoffSourceContractError.requiredTokenMissing
        }
        return range.lowerBound
    }

    private func deliveryCutoffSection(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw DeliveryCutoffSourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func deliveryCutoffReadRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum DeliveryCutoffSourceContractError: Error {
        case sectionMissing
        case requiredTokenMissing
    }
}
