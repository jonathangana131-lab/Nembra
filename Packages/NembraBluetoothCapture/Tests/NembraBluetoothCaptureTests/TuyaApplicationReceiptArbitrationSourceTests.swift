import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaApplicationTimeoutPresentationRaceSourceTests {
    @Test("application receipt arbitration is exact-ledger ordered and shares one clock")
    func packageOwnsReceiptIssuerOrderingAndClock() throws {
        let ledger = try receiptArbitrationRead(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )
        let arbiter = String(try receiptArbitrationSection(
            in: ledger,
            from: "private final class TuyaApplicationDeliveryArbiter",
            to: "public actor TuyaAuthenticatedReadOnlySessionLedger"
        ))

        #expect(arbiter.contains("private let lock = NSLock()"))
        #expect(arbiter.contains("let applicationReceiptIssuerID: UUID"))
        #expect(arbiter.contains("private let nowUptimeNanoseconds: @Sendable () -> UInt64"))
        #expect(arbiter.contains("private var pendingApplicationDeliveries"))
        #expect(arbiter.contains("private var consumedApplicationDeliveryIDs: Set<UUID>"))
        #expect(arbiter.contains("deliveryID: UUID()"))
        #expect(arbiter.contains("receivedAtUptimeNanoseconds: nowUptimeNanoseconds()"))
        #expect(arbiter.contains("pendingApplicationDeliveries.append(receipt)"))
        #expect(arbiter.contains("guard first.deliveryID == receipt.deliveryID else"))
        #expect(arbiter.contains("consumedApplicationDeliveryIDs.insert(receipt.deliveryID).inserted"))
        #expect(arbiter.contains("guard pendingApplicationDeliveries.isEmpty else"))
        #expect(arbiter.contains("return .applicationReceiptPending"))
        #expect(arbiter.contains("let now = nowUptimeNanoseconds()"))

        #expect(ledger.contains("private let nowUptimeNanoseconds: @Sendable () -> UInt64"))
        #expect(ledger.contains("private let applicationDeliveryArbiter: TuyaApplicationDeliveryArbiter"))
        #expect(ledger.contains("TuyaApplicationDeliveryArbiter(nowUptimeNanoseconds: clock)"))
        #expect(ledger.contains("applicationDeliveryArbiter.activate(for: token)"))
        #expect(ledger.contains("applicationDeliveryArbiter.retire(for: token)"))

        let record = String(try receiptArbitrationSection(
            in: ledger,
            from: "public func recordApplicationUpdate(",
            to: "public func observeCurrentConnection("
        ))
        let consume = try receiptArbitrationRequired(
            "applicationDeliveryArbiter.consumeApplicationReceipt(receipt, for: token)",
            in: record
        )
        let count = try receiptArbitrationRequired("applicationPayloadCount += 1", in: record)
        #expect(consume < count)
        #expect(record.contains("case .duplicateApplicationReceipt"))
        #expect(record.contains("case .applicationReceiptOrderPending"))

        let observe = String(try receiptArbitrationSection(
            in: ledger,
            from: "public func observeCurrentConnection(",
            to: "public func markObservationContinuityInvalidated("
        ))
        #expect(observe.contains("applicationDeliveryArbiter.captureLivenessBoundary(for: token)"))
        #expect(observe.contains("case .applicationReceiptPending"))
        #expect(observe.contains("let now = livenessBoundary"))
        #expect(!observe.contains("let now = try nextMonotonicObservation()"))
    }

    @Test("terminal and seal paths revoke synchronous receipt authority")
    func terminalPathsRetireReceiptIssuerAuthority() throws {
        let ledger = try receiptArbitrationRead(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )

        for start in [
            "public func markAuthenticationFailed(",
            "public func markInternalLifecycleFailure(",
            "public func markSourceAuthorityInvalidated(",
            "public func markObservationContinuityInvalidated(",
            "public func markApplicationObservationTimedOut(",
            "public func sealAcceptedObservation(",
            "public func endConnection("
        ] {
            let section = String(try receiptArbitrationFunctionBody(in: ledger, startingAt: start))
            #expect(section.contains("applicationDeliveryArbiter.retire(for: token)"),
                    Comment(rawValue: "Every explicit current-token terminal/seal must synchronously retire pending receipt authority: \(start)"))
        }

        let incomplete = String(try receiptArbitrationSection(
            in: ledger,
            from: "private func requireIncompleteObservationHorizonOpen",
            to: "private func requireContinuousAuthenticatedObservation"
        ))
        #expect(incomplete.contains("applicationDeliveryArbiter.retire(for: currentToken)"))

        let continuity = String(try receiptArbitrationFunctionBody(
            in: ledger,
            startingAt: "private func requireContinuousAuthenticatedObservation"
        ))
        #expect(continuity.contains("applicationDeliveryArbiter.retire(for: currentToken)"))
    }

    private func receiptArbitrationFunctionBody(in source: String, startingAt start: String) throws -> Substring {
        guard let startRange = source.range(of: start) else {
            Issue.record("Missing function: \(start)")
            throw ReceiptArbitrationSourceError.sectionMissing
        }
        var depth = 0
        var sawBrace = false
        var index = startRange.lowerBound
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
                sawBrace = true
            } else if character == "}" && sawBrace {
                depth -= 1
                if depth == 0 {
                    return source[startRange.lowerBound...index]
                }
            }
            index = source.index(after: index)
        }
        Issue.record("Could not isolate function body: \(start)")
        throw ReceiptArbitrationSourceError.sectionMissing
    }

    private func receiptArbitrationSection(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected receipt-arbitration source section missing: \(start) ... \(end)")
            throw ReceiptArbitrationSourceError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func receiptArbitrationRequired(_ needle: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: needle) else {
            Issue.record("Missing receipt-arbitration contract: \(needle)")
            throw ReceiptArbitrationSourceError.requiredTokenMissing
        }
        return range.lowerBound
    }

    private func receiptArbitrationRead(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum ReceiptArbitrationSourceError: Error {
        case sectionMissing
        case requiredTokenMissing
    }
}
