import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("ES80 guided stationary capture plan")
struct ES80GuidedCapturePlanTests {
    @Test("happy path preserves all nine ordered windows and completes")
    func happyPath() throws {
        var harness = try Harness()

        for (actionIndex, action) in ES80GuidedCapturePlan.requiredActions.enumerated() {
            #expect(harness.plan.currentAction == action)

            try harness.startWindow()
            try harness.record(payload: actionIndex * 2)
            try harness.completeObservationWindow()

            #expect(harness.plan.currentAction == action)
            #expect(harness.plan.currentPhase == .during)
            try harness.startWindow()
            try harness.record(payload: actionIndex * 2 + 1)
            try harness.confirm()

            #expect(harness.plan.currentAction == action)
            #expect(harness.plan.currentPhase == .after)
            try harness.startWindow()
            try harness.record(payload: actionIndex * 2 + 1)
            try harness.completeObservationWindow()
        }

        #expect(harness.plan.isComplete)
        #expect(!harness.plan.canContinue)
        #expect(harness.plan.currentAction == nil)
        #expect(harness.plan.currentPhase == nil)
        #expect(harness.plan.completedWindows.count == 9)
        #expect(
            harness.plan.completedWindows.map(\.action)
                == ES80GuidedCapturePlan.requiredActions.flatMap { action in
                    Array(repeating: action, count: 3)
                }
        )
        #expect(
            harness.plan.completedWindows.map(\.phase)
                == ES80GuidedCapturePlan.requiredActions.flatMap { _ in
                    ES80GuidedCaptureWindowPhase.allCases
                }
        )
        try harness.plan.validate()
    }

    @Test("unmapped payload changes remain evidence and never complete an action")
    func payloadChangeRequiresOperatorConfirmation() throws {
        var harness = try Harness()

        try harness.startWindow()
        try harness.record(payload: 0)
        let baseline = try #require(harness.plan.activeWindow?.evidenceReceipts.last)
        try harness.completeObservationWindow()

        try harness.startWindow()
        try harness.record(payload: 1)
        let during = try #require(harness.plan.activeWindow?.evidenceReceipts.last)
        #expect(during.canonicalEventSHA256 != baseline.canonicalEventSHA256)
        #expect(during.canonicalPayloadSHA256 != baseline.canonicalPayloadSHA256)
        #expect(harness.plan.completedWindows.count == 1)
        #expect(harness.plan.currentPhase == .during)
        #expect(harness.plan.activeWindow?.phase == .during)
        #expect(
            ES80GuidedCaptureWindowCompletion.allCases
                == [
                    .explicitOperatorConfirmation,
                    .nonOperatorObservationWindowCompletion,
                ]
        )
        try harness.confirm()
        #expect(harness.plan.currentPhase == .after)
    }

    @Test("equivalent repeated payloads retain distinct event receipts")
    func duplicateEvidenceIsPreserved() throws {
        var harness = try Harness()
        try harness.startWindow()
        try harness.record(payload: 4)
        try harness.record(payload: 4)
        try harness.completeObservationWindow()

        let receipt = try #require(harness.plan.completedWindows.first)
        #expect(receipt.evidenceReceipts.count == 2)
        #expect(
            receipt.evidenceReceipts[0].canonicalPayloadSHA256
                == receipt.evidenceReceipts[1].canonicalPayloadSHA256
        )
        #expect(
            receipt.evidenceReceipts[0].canonicalEventSHA256
                != receipt.evidenceReceipts[1].canonicalEventSHA256
        )
        #expect(
            receipt.evidenceReceipts[0].watermark.sourceSequence
                < receipt.evidenceReceipts[1].watermark.sourceSequence
        )
    }

    @Test("plan derives receipt identity and chronology from the typed source event")
    func receiptIsDerivedInsidePlan() throws {
        var harness = try Harness()
        try harness.startWindow()
        let event = try harness.event(
            payload: 12,
            sequence: 91,
            uptimeNanoseconds: 9_100
        )
        try harness.plan.recordEvidence(event)
        let receipt = try #require(harness.plan.activeWindow?.evidenceReceipts.last)
        let expectedEventHash = try TuyaStructuredApplicationEvidenceJSON
            .canonicalEventSHA256(event)
        let expectedPayloadHash = try TuyaStructuredApplicationEvidenceJSON
            .canonicalPayloadSHA256(event)

        #expect(receipt.pseudonymousSessionID == event.pseudonymousSessionID)
        #expect(receipt.watermark.connectionGeneration == event.connectionGeneration)
        #expect(receipt.watermark.sourceSequence == event.deliverySequence)
        #expect(
            receipt.watermark.receivedAtUptimeNanoseconds
                == event.receivedAtUptimeNanoseconds
        )
        #expect(receipt.canonicalEventSHA256 == expectedEventHash)
        #expect(receipt.canonicalPayloadSHA256 == expectedPayloadHash)
    }

    @Test("foreign session and connection generation receipts fail without mutation")
    func receiptAuthorityMustMatchPlan() throws {
        var harness = try Harness()
        try harness.startWindow()
        let before = harness.plan
        let otherSession = try TuyaStructuredApplicationSessionID(
            pseudonymousUUID: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        )

        let foreignSession = try harness.nextEvent(payload: 1, sessionID: otherSession)
        #expect(throws: ES80GuidedCapturePlanError.sourceSessionChanged) {
            try harness.plan.recordEvidence(foreignSession)
        }
        #expect(harness.plan == before)

        let foreignGeneration = try harness.nextEvent(
            payload: 1,
            connectionGeneration: harness.connectionGeneration + 1
        )
        #expect(throws: ES80GuidedCapturePlanError.sourceConnectionGenerationChanged) {
            try harness.plan.recordEvidence(foreignGeneration)
        }
        #expect(harness.plan == before)
    }

    @Test("disconnect abandons the active window and permanently blocks resume")
    func disconnectBreaksContinuity() throws {
        var harness = try Harness()
        try harness.startWindow()
        try harness.record(payload: 0)
        let last = try harness.nextWatermark()

        try harness.plan.recordContinuityBreak(
            .transportDisconnected,
            lastAcceptedWatermark: last
        )

        #expect(harness.plan.continuityBreak?.cause == .transportDisconnected)
        #expect(harness.plan.continuityBreak?.abandonedWindow?.evidenceReceipts.count == 1)
        #expect(harness.plan.activeWindow == nil)
        #expect(!harness.plan.canContinue)
        #expect(throws: ES80GuidedCapturePlanError.continuityBroken) {
            try harness.plan.startCurrentWindow(at: harness.nextWatermark())
        }
    }

    @Test("every foreground lifecycle terminal is a non-resumable continuity break", arguments: [
        ES80GuidedCaptureContinuityBreakCause.operatorInterrupted,
        .appEnteredBackground,
        .transportDisconnected,
        .scooterPowerCycleOrReconnect,
        .processTerminated,
    ])
    func lifecycleBreaksAreTerminal(cause: ES80GuidedCaptureContinuityBreakCause) throws {
        var harness = try Harness()
        try harness.startWindow()
        try harness.record(payload: 0)
        try harness.plan.recordContinuityBreak(
            cause,
            lastAcceptedWatermark: harness.nextWatermark()
        )

        #expect(harness.plan.continuityBreak?.cause == cause)
        #expect(throws: ES80GuidedCapturePlanError.continuityBroken) {
            try harness.plan.recordEvidence(harness.nextEvent(payload: 1))
        }
    }

    @Test("ordinary decoded unfinished state is inert until explicitly terminalized")
    func ordinaryDecodedStateCannotDrive() throws {
        var harness = try Harness()
        try harness.startWindow()
        try harness.record(payload: 0)
        let data = try ES80GuidedCapturePlan.encodeCanonicalJSON(harness.plan)
        let restored = try JSONDecoder().decode(ES80GuidedCapturePlan.self, from: data)

        #expect(restored.continuityBreak == nil)
        #expect(restored.activeWindow?.evidenceReceipts.count == 1)
        #expect(!restored.canContinue)

        var startAttempt = restored
        #expect(throws: ES80GuidedCapturePlanError.decodedPlanRequiresProcessRelaunchBoundary) {
            try startAttempt.startCurrentWindow(at: harness.nextWatermark())
        }

        var recordAttempt = restored
        #expect(throws: ES80GuidedCapturePlanError.decodedPlanRequiresProcessRelaunchBoundary) {
            try recordAttempt.recordEvidence(harness.nextEvent(payload: 1))
        }

        var confirmationAttempt = restored
        #expect(throws: ES80GuidedCapturePlanError.decodedPlanRequiresProcessRelaunchBoundary) {
            try confirmationAttempt.confirmCurrentWindow(endingAt: harness.nextWatermark())
        }

        var observationCompletionAttempt = restored
        #expect(throws: ES80GuidedCapturePlanError.decodedPlanRequiresProcessRelaunchBoundary) {
            try observationCompletionAttempt.completeObservationWindow(
                endingAt: harness.nextWatermark()
            )
        }

        var interruptionAttempt = restored
        #expect(throws: ES80GuidedCapturePlanError.decodedPlanRequiresProcessRelaunchBoundary) {
            try interruptionAttempt.recordContinuityBreak(
                .appEnteredBackground,
                lastAcceptedWatermark: nil
            )
        }

        var terminalized = restored
        #expect(
            throws: ES80GuidedCapturePlanError.processRelaunchRequiresTrustedBoundaryAPI
        ) {
            try terminalized.recordContinuityBreak(.processRelaunch, lastAcceptedWatermark: nil)
        }
        try terminalized.recordProcessRelaunchBoundary()
        #expect(terminalized.continuityBreak?.cause == .processRelaunch)
        #expect(terminalized.continuityBreak?.abandonedWindow?.evidenceReceipts.count == 1)
        #expect(terminalized.activeWindow == nil)
        #expect(!terminalized.canContinue)
        try terminalized.validate()
    }

    @Test("strict decode terminalizes unfinished state before returning it")
    func strictDecodeRecordsProcessRelaunch() throws {
        var harness = try Harness()
        try harness.startWindow()
        try harness.record(payload: 0)

        let data = try ES80GuidedCapturePlan.encodeCanonicalJSON(harness.plan)
        var restored = try ES80GuidedCapturePlan.decodeStrictJSON(data)

        #expect(restored.continuityBreak?.cause == .processRelaunch)
        #expect(restored.continuityBreak?.abandonedWindow?.evidenceReceipts.count == 1)
        #expect(restored.activeWindow == nil)
        #expect(!restored.canContinue)
        #expect(throws: ES80GuidedCapturePlanError.continuityBroken) {
            try restored.recordProcessRelaunchBoundary()
        }

        var fresh = harness.plan
        #expect(
            throws: ES80GuidedCapturePlanError.processRelaunchBoundaryRequiresDecodedPlan
        ) {
            try fresh.recordProcessRelaunchBoundary()
        }
    }

    @Test("a complete plan round-trips through the exact canonical representation")
    func completedPlanRoundTrips() throws {
        var harness = try Harness()
        try harness.completePlan()

        let data = try ES80GuidedCapturePlan.encodeCanonicalJSON(harness.plan)
        let restored = try ES80GuidedCapturePlan.decodeStrictJSON(data)
        #expect(restored.isComplete)
        #expect(!restored.canContinue)
        #expect(restored.continuityBreak == nil)
        #expect(restored.completedWindows == harness.plan.completedWindows)
        #expect(try ES80GuidedCapturePlan.encodeCanonicalJSON(restored) == data)
    }

    @Test("out-of-order source sequence and uptime receipts fail without mutation")
    func outOfOrderReceiptsFailClosed() throws {
        var harness = try Harness()
        try harness.startWindow()
        let accepted = try harness.nextEvent(payload: 0)
        try harness.plan.recordEvidence(accepted)
        let before = harness.plan

        let repeatedSequence = try harness.event(
            payload: 1,
            sequence: accepted.deliverySequence,
            uptimeNanoseconds: accepted.receivedAtUptimeNanoseconds + 10
        )
        #expect(throws: ES80GuidedCapturePlanError.invalidSourceSequence) {
            try harness.plan.recordEvidence(repeatedSequence)
        }
        #expect(harness.plan == before)

        let regressedUptime = try harness.event(
            payload: 1,
            sequence: accepted.deliverySequence + 1,
            uptimeNanoseconds: accepted.receivedAtUptimeNanoseconds - 1
        )
        #expect(throws: ES80GuidedCapturePlanError.invalidWindowChronology) {
            try harness.plan.recordEvidence(regressedUptime)
        }
        #expect(harness.plan == before)
    }

    @Test("a window rejects evidence beyond its bounded receipt capacity")
    func receiptLimitFailsBeforeAppend() throws {
        var harness = try Harness()
        try harness.startWindow()

        for index in 0..<ES80GuidedCapturePlan.maximumEvidenceReceiptsPerWindow {
            try harness.record(payload: index % 2)
        }
        #expect(
            harness.plan.activeWindow?.evidenceReceipts.count
                == ES80GuidedCapturePlan.maximumEvidenceReceiptsPerWindow
        )
        let before = harness.plan
        let overflow = try harness.nextEvent(payload: 2)

        #expect(
            throws: ES80GuidedCapturePlanError.windowEvidenceReceiptLimitExceeded(
                maximum: ES80GuidedCapturePlan.maximumEvidenceReceiptsPerWindow
            )
        ) {
            try harness.plan.recordEvidence(overflow)
        }
        #expect(harness.plan == before)

        let canonical = try ES80GuidedCapturePlan.encodeCanonicalJSON(harness.plan)
        #expect(canonical.count <= ES80GuidedCapturePlan.maximumCanonicalJSONByteCount)
    }

    @Test("decoded windows above the receipt limit fail validation before chronology")
    func decodedReceiptLimitFailsClosed() throws {
        var harness = try Harness()
        try harness.startWindow()
        try harness.record(payload: 0)
        let canonical = try ES80GuidedCapturePlan.encodeCanonicalJSON(harness.plan)
        var root = try #require(
            JSONSerialization.jsonObject(with: canonical) as? [String: Any]
        )
        var active = try #require(root["activeWindow"] as? [String: Any])
        let receipts = try #require(active["evidenceReceipts"] as? [Any])
        let sample = try #require(receipts.first)
        active["evidenceReceipts"] = Array<Any>(
            repeating: sample,
            count: ES80GuidedCapturePlan.maximumEvidenceReceiptsPerWindow + 1
        )
        root["activeWindow"] = active
        let oversizedWindow = try JSONSerialization.data(withJSONObject: root)

        #expect(
            throws: ES80GuidedCapturePlanError.windowEvidenceReceiptLimitExceeded(
                maximum: ES80GuidedCapturePlan.maximumEvidenceReceiptsPerWindow
            )
        ) {
            try JSONDecoder().decode(ES80GuidedCapturePlan.self, from: oversizedWindow)
        }
    }

    @Test("reconnect generation cannot enter an existing plan")
    func newConnectionGenerationFailsClosed() throws {
        var harness = try Harness()
        let wrongGeneration = try ES80GuidedCaptureSourceWatermark(
            connectionGeneration: harness.connectionGeneration + 1,
            sourceSequence: 1,
            receivedAtUptimeNanoseconds: 1
        )
        #expect(throws: ES80GuidedCapturePlanError.sourceConnectionGenerationChanged) {
            try harness.plan.startCurrentWindow(at: wrongGeneration)
        }
    }

    @Test("watermarks require nonzero source sequence and monotonic uptime")
    func watermarkZeroValuesFailClosed() {
        #expect(throws: ES80GuidedCapturePlanError.invalidSourceSequence) {
            try ES80GuidedCaptureSourceWatermark(
                connectionGeneration: 1,
                sourceSequence: 0,
                receivedAtUptimeNanoseconds: 1
            )
        }
        #expect(throws: ES80GuidedCapturePlanError.invalidWindowChronology) {
            try ES80GuidedCaptureSourceWatermark(
                connectionGeneration: 1,
                sourceSequence: 1,
                receivedAtUptimeNanoseconds: 0
            )
        }
    }

    @Test("unsafe stationary activities are excluded and require a separate procedure")
    func unsafeActivitiesAreExcluded() {
        #expect(
            ES80GuidedCaptureAction.allCases
                == [
                    .physicalModeChange,
                    .physicalHeadlightToggle,
                    .physicalBrakeLever,
                ]
        )
        #expect(
            ES80GuidedCapturePlan.deferredActivities
                == [.chargerTransition, .wheelMotion]
        )
        #expect(
            ES80GuidedCapturePlan.deferredActivities.allSatisfy {
                $0.disposition == .requiresSeparateSafetyProcedure
            }
        )
        #expect(
            !ES80GuidedCaptureAction.allCases.map(\.rawValue)
                .contains(ES80GuidedCaptureContinuityBreakCause.scooterPowerCycleOrReconnect.rawValue)
        )
    }

    @Test("bounded public plan surface is observation-only and has no command action")
    func noWriteAPI() {
        #expect(
            ES80GuidedCapturePlan.transportAuthority
                == .observationOnlyNoApplicationWrites
        )
        #expect(ES80GuidedCapturePlan.requiredActions == ES80GuidedCaptureAction.allCases)

        let actionSurface = ES80GuidedCaptureAction.allCases
            .map(\.rawValue)
            .joined(separator: " ")
        for forbidden in ["write", "firmware", "command", "query", "lock", "unlock"] {
            #expect(!actionSurface.contains(forbidden))
        }
    }

    @Test("strict decoding rejects unknown fields and unsupported schema versions")
    func strictVersionedDecoding() throws {
        let harness = try Harness()
        let encoded = try ES80GuidedCapturePlan.encodeCanonicalJSON(harness.plan)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        object["unexpected"] = true
        let unknownKeyData = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try ES80GuidedCapturePlan.decodeStrictJSON(unknownKeyData)
        }

        object.removeValue(forKey: "unexpected")
        object["version"] = ES80GuidedCapturePlan.schemaVersion + 1
        let unsupportedVersionData = try JSONSerialization.data(withJSONObject: object)
        #expect(
            throws: ES80GuidedCapturePlanError.unsupportedSchemaVersion(
                ES80GuidedCapturePlan.schemaVersion + 1
            )
        ) {
            try ES80GuidedCapturePlan.decodeStrictJSON(unsupportedVersionData)
        }
    }

    @Test("strict import rejects pretty, trailing-whitespace, and nested-duplicate JSON")
    func onlyExactCanonicalJSONIsAccepted() throws {
        var harness = try Harness()
        try harness.startWindow()
        try harness.record(payload: 0)
        let plan = harness.plan
        let canonical = try ES80GuidedCapturePlan.encodeCanonicalJSON(plan)
        let strictImport = try ES80GuidedCapturePlan.decodeStrictJSON(canonical)
        #expect(strictImport.continuityBreak?.cause == .processRelaunch)
        #expect(strictImport.continuityBreak?.abandonedWindow?.evidenceReceipts.count == 1)

        let object = try JSONSerialization.jsonObject(with: canonical)
        let pretty = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        #expect(pretty != canonical)
        #expect(throws: ES80GuidedCapturePlanError.nonCanonicalJSON) {
            try ES80GuidedCapturePlan.decodeStrictJSON(pretty)
        }

        var trailingWhitespace = canonical
        trailingWhitespace.append(contentsOf: [0x0A])
        #expect(throws: ES80GuidedCapturePlanError.nonCanonicalJSON) {
            try ES80GuidedCapturePlan.decodeStrictJSON(trailingWhitespace)
        }

        let receipt = try #require(plan.activeWindow?.evidenceReceipts.first)
        let canonicalText = String(decoding: canonical, as: UTF8.self)
        let member = "\"canonicalPayloadSHA256\":\"\(receipt.canonicalPayloadSHA256)\""
        let duplicateMember = "\(member),\(member)"
        let nestedDuplicateText = canonicalText.replacingOccurrences(
            of: member,
            with: duplicateMember
        )
        #expect(nestedDuplicateText != canonicalText)
        #expect(throws: ES80GuidedCapturePlanError.nonCanonicalJSON) {
            try ES80GuidedCapturePlan.decodeStrictJSON(Data(nestedDuplicateText.utf8))
        }
    }

    @Test("strict import rejects oversized bytes before JSON decoding")
    func strictImportByteLimit() {
        let oversizedCount = ES80GuidedCapturePlan.maximumCanonicalJSONByteCount + 1
        let oversized = Data(repeating: 0x20, count: oversizedCount)

        #expect(
            throws: ES80GuidedCapturePlanError.inputByteLimitExceeded(
                byteCount: oversizedCount,
                maximum: ES80GuidedCapturePlan.maximumCanonicalJSONByteCount
            )
        ) {
            try ES80GuidedCapturePlan.decodeStrictJSON(oversized)
        }
    }

    @Test("strict JSON import rejects a duplicate top-level authority key")
    func duplicateTopLevelKeyRejected() {
        let duplicate = Data(
            """
            {
              "schema":"\(ES80GuidedCapturePlan.schemaIdentifier)",
              "schema":"\(ES80GuidedCapturePlan.schemaIdentifier)",
              "version":1
            }
            """.utf8
        )
        #expect(
            throws: ES80GuidedCapturePlanError.duplicateTopLevelJSONKey("schema")
        ) {
            try ES80GuidedCapturePlan.decodeStrictJSON(duplicate)
        }
    }
}

private struct Harness {
    let connectionGeneration: UInt64 = 7
    let sessionID: TuyaStructuredApplicationSessionID
    var plan: ES80GuidedCapturePlan
    private var nextSequence: UInt64 = 1
    private var nextUptimeNanoseconds: UInt64 = 1_000

    init() throws {
        sessionID = try TuyaStructuredApplicationSessionID(
            pseudonymousUUID: UUID(
                uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
            )!
        )
        plan = try ES80GuidedCapturePlan(
            sourceSessionID: sessionID,
            connectionGeneration: connectionGeneration
        )
    }

    mutating func nextWatermark() throws -> ES80GuidedCaptureSourceWatermark {
        defer {
            nextSequence += 1
            nextUptimeNanoseconds += 1_000
        }
        return try ES80GuidedCaptureSourceWatermark(
            connectionGeneration: connectionGeneration,
            sourceSequence: nextSequence,
            receivedAtUptimeNanoseconds: nextUptimeNanoseconds
        )
    }

    func event(
        payload: Int,
        sessionID: TuyaStructuredApplicationSessionID? = nil,
        connectionGeneration: UInt64? = nil,
        sequence: UInt64,
        uptimeNanoseconds: UInt64
    ) throws -> TuyaStructuredApplicationEvidenceEvent {
        try TuyaStructuredApplicationEvidenceEvent(
            pseudonymousSessionID: sessionID ?? self.sessionID,
            connectionGeneration: connectionGeneration ?? self.connectionGeneration,
            deliverySequence: sequence,
            receivedAtUptimeNanoseconds: uptimeNanoseconds,
            receivedAtWallClock: Date(
                timeIntervalSince1970: 1_776_666_666 + Double(sequence) / 1_000
            ),
            entries: [
                .init(key: .string("observation"), value: .signedInteger(Int64(payload))),
            ]
        )
    }

    mutating func nextEvent(
        payload: Int,
        sessionID: TuyaStructuredApplicationSessionID? = nil,
        connectionGeneration: UInt64? = nil
    ) throws -> TuyaStructuredApplicationEvidenceEvent {
        let watermark = try nextWatermark()
        return try event(
            payload: payload,
            sessionID: sessionID,
            connectionGeneration: connectionGeneration,
            sequence: watermark.sourceSequence,
            uptimeNanoseconds: watermark.receivedAtUptimeNanoseconds
        )
    }

    mutating func startWindow() throws {
        try plan.startCurrentWindow(at: nextWatermark())
    }

    mutating func record(payload: Int) throws {
        try plan.recordEvidence(nextEvent(payload: payload))
    }

    mutating func confirm() throws {
        try plan.confirmCurrentWindow(endingAt: nextWatermark())
    }

    mutating func completeObservationWindow() throws {
        try plan.completeObservationWindow(endingAt: nextWatermark())
    }

    mutating func completePlan() throws {
        for actionIndex in ES80GuidedCapturePlan.requiredActions.indices {
            try startWindow()
            try record(payload: actionIndex * 2)
            try completeObservationWindow()
            try startWindow()
            try record(payload: actionIndex * 2 + 1)
            try confirm()
            try startWindow()
            try record(payload: actionIndex * 2 + 1)
            try completeObservationWindow()
        }
    }
}
