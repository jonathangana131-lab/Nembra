import Foundation

/// The only operator activities admitted by the first stationary ES80 mapping plan.
///
/// These cases describe physical observations. They do not represent a BLE command, a decoded
/// scooter state, or proof that the operator actually performed the requested activity.
public enum ES80GuidedCaptureAction: String, Codable, CaseIterable, Equatable, Sendable {
    case physicalModeChange = "physical-mode-change"
    case physicalHeadlightToggle = "physical-headlight-toggle"
    case physicalBrakeLever = "physical-brake-lever"
}

/// Activities deliberately excluded from the initial stationary procedure.
///
/// Adding one of these to a later procedure requires a separate safety review. Neither case is an
/// executable action and neither can be inserted into `ES80GuidedCapturePlan.requiredActions`.
public enum ES80GuidedCaptureDeferredActivity: String, Codable, CaseIterable, Equatable, Sendable {
    case chargerTransition = "charger-transition"
    case wheelMotion = "wheel-motion"

    public var disposition: ES80GuidedCaptureDeferredActivityDisposition {
        .requiresSeparateSafetyProcedure
    }
}

public enum ES80GuidedCaptureDeferredActivityDisposition: String, Codable, Equatable, Sendable {
    case requiresSeparateSafetyProcedure = "requires-separate-safety-procedure"
}

/// Fixed policy marker for consumers assembling the Capture UI and evidence bundle.
///
/// The guided plan accepts observations and operator confirmations only. It intentionally exposes
/// no transport-write, firmware, data-point query, or generic command API.
public enum ES80GuidedCaptureTransportAuthority: String, Codable, Equatable, Sendable {
    case observationOnlyNoApplicationWrites = "observation-only-no-application-writes"
}

public enum ES80GuidedCaptureWindowPhase: String, Codable, CaseIterable, Equatable, Sendable {
    case before
    case during
    case after
}

/// Monotonic boundary in the authoritative observation producer's sequence domain.
///
/// This is callback chronology, not RF emission time. A reconnect must mint a new connection
/// generation and a new guided plan; it cannot continue an existing window.
public struct ES80GuidedCaptureSourceWatermark: Codable, Equatable, Sendable {
    public let connectionGeneration: UInt64
    public let sourceSequence: UInt64
    public let receivedAtUptimeNanoseconds: UInt64

    public init(
        connectionGeneration: UInt64,
        sourceSequence: UInt64,
        receivedAtUptimeNanoseconds: UInt64
    ) throws {
        guard connectionGeneration > 0 else {
            throw ES80GuidedCapturePlanError.invalidConnectionGeneration
        }
        guard sourceSequence > 0 else {
            throw ES80GuidedCapturePlanError.invalidSourceSequence
        }
        guard receivedAtUptimeNanoseconds > 0 else {
            throw ES80GuidedCapturePlanError.invalidWindowChronology
        }
        self.connectionGeneration = connectionGeneration
        self.sourceSequence = sourceSequence
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case connectionGeneration
        case sourceSequence
        case receivedAtUptimeNanoseconds
    }

    public init(from decoder: Decoder) throws {
        try ES80GuidedCaptureCoding.rejectUnknownKeys(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.rawValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            connectionGeneration: container.decode(UInt64.self, forKey: .connectionGeneration),
            sourceSequence: container.decode(UInt64.self, forKey: .sourceSequence),
            receivedAtUptimeNanoseconds: container.decode(
                UInt64.self,
                forKey: .receivedAtUptimeNanoseconds
            )
        )
    }
}

/// One accepted source observation bound to a typed, lossless application-evidence event.
///
/// The full-event digest preserves exact receipt identity and the payload digest supports later
/// chronology-independent correlation. This plan neither compares nor interprets a field, bit,
/// unit, or scooter state. Equivalent payloads at distinct sequences remain distinct receipts.
public struct ES80GuidedCaptureEvidenceReceipt: Codable, Equatable, Sendable {
    public let pseudonymousSessionID: TuyaStructuredApplicationSessionID
    public let watermark: ES80GuidedCaptureSourceWatermark
    public let canonicalEventSHA256: String
    public let canonicalPayloadSHA256: String

    /// Constructs a receipt only from the package's lossless typed evidence boundary.
    ///
    /// The live-plan mutation boundary derives this from a source event. Decoded receipts are
    /// inspection data and are not accepted by `recordEvidence(_:)`.
    fileprivate init(event: TuyaStructuredApplicationEvidenceEvent) throws {
        try self.init(
            pseudonymousSessionID: event.pseudonymousSessionID,
            watermark: ES80GuidedCaptureSourceWatermark(
                connectionGeneration: event.connectionGeneration,
                sourceSequence: event.deliverySequence,
                receivedAtUptimeNanoseconds: event.receivedAtUptimeNanoseconds
            ),
            canonicalEventSHA256:
                TuyaStructuredApplicationEvidenceJSON.canonicalEventSHA256(event),
            canonicalPayloadSHA256:
                TuyaStructuredApplicationEvidenceJSON.canonicalPayloadSHA256(event)
        )
    }

    private init(
        pseudonymousSessionID: TuyaStructuredApplicationSessionID,
        watermark: ES80GuidedCaptureSourceWatermark,
        canonicalEventSHA256: String,
        canonicalPayloadSHA256: String
    ) throws {
        guard watermark.sourceSequence > 0 else {
            throw ES80GuidedCapturePlanError.invalidSourceSequence
        }
        guard watermark.receivedAtUptimeNanoseconds > 0 else {
            throw ES80GuidedCapturePlanError.invalidWindowChronology
        }
        guard ES80GuidedCaptureCoding.isLowercaseSHA256(canonicalEventSHA256),
              ES80GuidedCaptureCoding.isLowercaseSHA256(canonicalPayloadSHA256) else {
            throw ES80GuidedCapturePlanError.invalidObservationDigest
        }
        self.pseudonymousSessionID = pseudonymousSessionID
        self.watermark = watermark
        self.canonicalEventSHA256 = canonicalEventSHA256
        self.canonicalPayloadSHA256 = canonicalPayloadSHA256
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case pseudonymousSessionID
        case watermark
        case canonicalEventSHA256
        case canonicalPayloadSHA256
    }

    public init(from decoder: Decoder) throws {
        try ES80GuidedCaptureCoding.rejectUnknownKeys(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.rawValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            pseudonymousSessionID: container.decode(
                TuyaStructuredApplicationSessionID.self,
                forKey: .pseudonymousSessionID
            ),
            watermark: container.decode(
                ES80GuidedCaptureSourceWatermark.self,
                forKey: .watermark
            ),
            canonicalEventSHA256: container.decode(
                String.self,
                forKey: .canonicalEventSHA256
            ),
            canonicalPayloadSHA256: container.decode(
                String.self,
                forKey: .canonicalPayloadSHA256
            )
        )
    }
}

public enum ES80GuidedCaptureWindowCompletion:
    String, Codable, CaseIterable, Equatable, Sendable
{
    /// The operator explicitly confirmed a physical action because evidence did not auto-detect it.
    case explicitOperatorConfirmation = "explicit-operator-confirmation"

    /// App policy closed a non-action observation window after retaining evidence.
    /// This label claims neither a duration nor that a human performed another action.
    case nonOperatorObservationWindowCompletion = "non-operator-observation-window-completion"
}

/// Immutable receipt for one complete before/during/after observation window.
public struct ES80GuidedCaptureWindowReceipt: Codable, Equatable, Sendable {
    public let action: ES80GuidedCaptureAction
    public let phase: ES80GuidedCaptureWindowPhase
    public let startedAt: ES80GuidedCaptureSourceWatermark
    public let endedAt: ES80GuidedCaptureSourceWatermark
    public let evidenceReceipts: [ES80GuidedCaptureEvidenceReceipt]
    public let completion: ES80GuidedCaptureWindowCompletion

    fileprivate init(
        action: ES80GuidedCaptureAction,
        phase: ES80GuidedCaptureWindowPhase,
        startedAt: ES80GuidedCaptureSourceWatermark,
        endedAt: ES80GuidedCaptureSourceWatermark,
        evidenceReceipts: [ES80GuidedCaptureEvidenceReceipt],
        completion: ES80GuidedCaptureWindowCompletion
    ) {
        self.action = action
        self.phase = phase
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.evidenceReceipts = evidenceReceipts
        self.completion = completion
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case action
        case phase
        case startedAt
        case endedAt
        case evidenceReceipts
        case completion
    }

    public init(from decoder: Decoder) throws {
        try ES80GuidedCaptureCoding.rejectUnknownKeys(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.rawValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            action: try container.decode(ES80GuidedCaptureAction.self, forKey: .action),
            phase: try container.decode(ES80GuidedCaptureWindowPhase.self, forKey: .phase),
            startedAt: try container.decode(
                ES80GuidedCaptureSourceWatermark.self,
                forKey: .startedAt
            ),
            endedAt: try container.decode(
                ES80GuidedCaptureSourceWatermark.self,
                forKey: .endedAt
            ),
            evidenceReceipts: try container.decode(
                [ES80GuidedCaptureEvidenceReceipt].self,
                forKey: .evidenceReceipts
            ),
            completion: try container.decode(
                ES80GuidedCaptureWindowCompletion.self,
                forKey: .completion
            )
        )
    }
}

/// In-progress window fields. Decoded unfinished windows are inert until terminalized as abandoned
/// evidence by `recordProcessRelaunchBoundary()`.
public struct ES80GuidedCaptureActiveWindow: Codable, Equatable, Sendable {
    public let action: ES80GuidedCaptureAction
    public let phase: ES80GuidedCaptureWindowPhase
    public let startedAt: ES80GuidedCaptureSourceWatermark
    public fileprivate(set) var evidenceReceipts: [ES80GuidedCaptureEvidenceReceipt]

    fileprivate init(
        action: ES80GuidedCaptureAction,
        phase: ES80GuidedCaptureWindowPhase,
        startedAt: ES80GuidedCaptureSourceWatermark,
        evidenceReceipts: [ES80GuidedCaptureEvidenceReceipt] = []
    ) {
        self.action = action
        self.phase = phase
        self.startedAt = startedAt
        self.evidenceReceipts = evidenceReceipts
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case action
        case phase
        case startedAt
        case evidenceReceipts
    }

    public init(from decoder: Decoder) throws {
        try ES80GuidedCaptureCoding.rejectUnknownKeys(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.rawValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            action: try container.decode(ES80GuidedCaptureAction.self, forKey: .action),
            phase: try container.decode(ES80GuidedCaptureWindowPhase.self, forKey: .phase),
            startedAt: try container.decode(
                ES80GuidedCaptureSourceWatermark.self,
                forKey: .startedAt
            ),
            evidenceReceipts: try container.decode(
                [ES80GuidedCaptureEvidenceReceipt].self,
                forKey: .evidenceReceipts
            )
        )
    }
}

/// A lifecycle boundary that permanently invalidates the current guided plan.
public enum ES80GuidedCaptureContinuityBreakCause: String, Codable, Equatable, Sendable {
    case operatorInterrupted = "operator-interrupted"
    case appEnteredBackground = "app-entered-background"
    case transportDisconnected = "transport-disconnected"
    case scooterPowerCycleOrReconnect = "scooter-power-cycle-or-reconnect"
    case processTerminated = "process-terminated"
    case processRelaunch = "process-relaunch"
}

/// Durable record of why an in-progress plan cannot resume.
///
/// `lastAcceptedWatermark` is the latest truthful producer boundary known when the break was
/// recorded. It is not presented as the RF time or exact system time of the interruption.
public struct ES80GuidedCaptureContinuityBreak: Codable, Equatable, Sendable {
    public let cause: ES80GuidedCaptureContinuityBreakCause
    public let lastAcceptedWatermark: ES80GuidedCaptureSourceWatermark?
    public let abandonedWindow: ES80GuidedCaptureActiveWindow?

    fileprivate init(
        cause: ES80GuidedCaptureContinuityBreakCause,
        lastAcceptedWatermark: ES80GuidedCaptureSourceWatermark?,
        abandonedWindow: ES80GuidedCaptureActiveWindow?
    ) {
        self.cause = cause
        self.lastAcceptedWatermark = lastAcceptedWatermark
        self.abandonedWindow = abandonedWindow
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cause
        case lastAcceptedWatermark
        case abandonedWindow
    }

    public init(from decoder: Decoder) throws {
        try ES80GuidedCaptureCoding.rejectUnknownKeys(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.rawValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cause: try container.decode(ES80GuidedCaptureContinuityBreakCause.self, forKey: .cause),
            lastAcceptedWatermark: try container.decodeIfPresent(
                ES80GuidedCaptureSourceWatermark.self,
                forKey: .lastAcceptedWatermark
            ),
            abandonedWindow: try container.decodeIfPresent(
                ES80GuidedCaptureActiveWindow.self,
                forKey: .abandonedWindow
            )
        )
    }
}

public enum ES80GuidedCapturePlanError: Error, Equatable, Sendable {
    case duplicateTopLevelJSONKey(String)
    case nonCanonicalJSON
    case inputByteLimitExceeded(byteCount: Int, maximum: Int)
    case outputByteLimitExceeded(byteCount: Int, maximum: Int)
    case invalidSchemaIdentifier
    case unsupportedSchemaVersion(Int)
    case invalidConnectionGeneration
    case invalidObservationDigest
    case invalidProgress
    case invalidWindowChronology
    case invalidSourceSequence
    case sourceSessionChanged
    case sourceConnectionGenerationChanged
    case windowEvidenceReceiptLimitExceeded(maximum: Int)
    case decodedPlanRequiresProcessRelaunchBoundary
    case processRelaunchRequiresTrustedBoundaryAPI
    case processRelaunchBoundaryRequiresDecodedPlan
    case windowAlreadyActive
    case windowNotActive
    case windowHasNoEvidence
    case invalidCompletionForPhase
    case continuityBroken
    case planComplete
}

/// Bounded observation state machine for the initial stationary ES80 procedure.
///
/// Each action owns exactly three windows (`before`, `during`, `after`). Only one window and one
/// operator action can be active. Samples are retained in receipt order without deduplication.
/// The app closes `before` and `after` through non-operator observation-window completion. Every
/// `during` window requires explicit operator confirmation: an unmapped payload change is retained
/// for later correlation but cannot prove which physical state changed.
///
/// Ordinary decoding preserves the encoded fields but marks unfinished state as non-driving. A
/// trusted restoration coordinator must call `recordProcessRelaunchBoundary()` to terminalize that
/// state. Strict decoding performs this terminalization before returning an unfinished plan.
public struct ES80GuidedCapturePlan: Codable, Equatable, Sendable {
    public static let schemaIdentifier = "nembra.es80-guided-stationary-capture-plan"
    public static let schemaVersion = 1
    public static let maximumCanonicalJSONByteCount = 8_388_608
    public static let maximumEvidenceReceiptsPerWindow = 2_048
    public static let transportAuthority: ES80GuidedCaptureTransportAuthority =
        .observationOnlyNoApplicationWrites
    public static let requiredActions: [ES80GuidedCaptureAction] = [
        .physicalModeChange,
        .physicalHeadlightToggle,
        .physicalBrakeLever,
    ]
    public static let deferredActivities: [ES80GuidedCaptureDeferredActivity] = [
        .chargerTransition,
        .wheelMotion,
    ]

    public let schema: String
    public let version: Int
    public let sourceSessionID: TuyaStructuredApplicationSessionID
    public let connectionGeneration: UInt64
    public private(set) var completedWindows: [ES80GuidedCaptureWindowReceipt]
    public private(set) var activeWindow: ES80GuidedCaptureActiveWindow?
    public private(set) var continuityBreak: ES80GuidedCaptureContinuityBreak?
    private var provenance: Provenance

    private enum Provenance: Equatable, Sendable {
        case fresh
        case decoded
    }

    public init(
        sourceSessionID: TuyaStructuredApplicationSessionID,
        connectionGeneration: UInt64
    ) throws {
        guard connectionGeneration > 0 else {
            throw ES80GuidedCapturePlanError.invalidConnectionGeneration
        }
        schema = Self.schemaIdentifier
        version = Self.schemaVersion
        self.sourceSessionID = sourceSessionID
        self.connectionGeneration = connectionGeneration
        completedWindows = []
        activeWindow = nil
        continuityBreak = nil
        provenance = .fresh
    }

    public var currentAction: ES80GuidedCaptureAction? {
        guard !isComplete else { return nil }
        return Self.requiredActions[completedWindows.count / ES80GuidedCaptureWindowPhase.allCases.count]
    }

    public var currentPhase: ES80GuidedCaptureWindowPhase? {
        guard !isComplete else { return nil }
        return Self.expectedWindowSequence[completedWindows.count].phase
    }

    public var isComplete: Bool {
        completedWindows.count == Self.expectedWindowSequence.count
            && activeWindow == nil
            && continuityBreak == nil
    }

    public var canContinue: Bool {
        provenance == .fresh && !isComplete && continuityBreak == nil
    }

    /// Opens the next required window at an exact source watermark.
    public mutating func startCurrentWindow(
        at watermark: ES80GuidedCaptureSourceWatermark
    ) throws {
        try requireMutablePlan()
        guard activeWindow == nil else {
            throw ES80GuidedCapturePlanError.windowAlreadyActive
        }
        try validateConnectionGeneration(watermark)
        if let latest = latestAcceptedWatermark {
            try Self.requireNondecreasing(watermark, after: latest)
        }
        guard let action = currentAction, let phase = currentPhase else {
            throw ES80GuidedCapturePlanError.planComplete
        }
        activeWindow = ES80GuidedCaptureActiveWindow(
            action: action,
            phase: phase,
            startedAt: watermark
        )
    }

    /// Derives and retains a receipt from a typed source event, including equivalent repeated
    /// payloads. Decoded or caller-minted receipt values never cross this mutation boundary.
    public mutating func recordEvidence(
        _ event: TuyaStructuredApplicationEvidenceEvent
    ) throws {
        try requireMutablePlan()
        guard var window = activeWindow else {
            throw ES80GuidedCapturePlanError.windowNotActive
        }
        guard window.evidenceReceipts.count < Self.maximumEvidenceReceiptsPerWindow else {
            throw ES80GuidedCapturePlanError.windowEvidenceReceiptLimitExceeded(
                maximum: Self.maximumEvidenceReceiptsPerWindow
            )
        }
        let receipt = try ES80GuidedCaptureEvidenceReceipt(event: event)
        try validateSession(receipt)
        try validateConnectionGeneration(receipt.watermark)

        let prior = window.evidenceReceipts.last?.watermark ?? window.startedAt
        guard receipt.watermark.sourceSequence > prior.sourceSequence else {
            throw ES80GuidedCapturePlanError.invalidSourceSequence
        }
        guard receipt.watermark.receivedAtUptimeNanoseconds
                >= prior.receivedAtUptimeNanoseconds else {
            throw ES80GuidedCapturePlanError.invalidWindowChronology
        }

        window.evidenceReceipts.append(receipt)
        activeWindow = window
    }

    /// Explicitly closes a window after the operator confirms the requested physical observation.
    /// At least one source receipt remains mandatory; confirmation cannot turn an empty window into
    /// evidence.
    public mutating func confirmCurrentWindow(
        endingAt watermark: ES80GuidedCaptureSourceWatermark
    ) throws {
        try requireMutablePlan()
        guard let window = activeWindow else {
            throw ES80GuidedCapturePlanError.windowNotActive
        }
        guard window.phase == .during else {
            throw ES80GuidedCapturePlanError.invalidCompletionForPhase
        }
        try validateEnd(watermark, for: window)
        try sealActiveWindow(
            endingAt: watermark,
            completion: .explicitOperatorConfirmation
        )
    }

    /// Closes a baseline (`before`) or recovery (`after`) observation window without another human
    /// action. This state machine requires retained source evidence and exact start/end chronology;
    /// it makes no claim about elapsed duration.
    public mutating func completeObservationWindow(
        endingAt watermark: ES80GuidedCaptureSourceWatermark
    ) throws {
        try requireMutablePlan()
        guard let window = activeWindow else {
            throw ES80GuidedCapturePlanError.windowNotActive
        }
        guard window.phase == .before || window.phase == .after else {
            throw ES80GuidedCapturePlanError.invalidCompletionForPhase
        }
        try validateEnd(watermark, for: window)
        try sealActiveWindow(
            endingAt: watermark,
            completion: .nonOperatorObservationWindowCompletion
        )
    }

    /// Permanently invalidates this plan at a lifecycle or transport boundary.
    /// A new process/connection must create a new plan; no resume method exists.
    public mutating func recordContinuityBreak(
        _ cause: ES80GuidedCaptureContinuityBreakCause,
        lastAcceptedWatermark watermark: ES80GuidedCaptureSourceWatermark?
    ) throws {
        guard cause != .processRelaunch else {
            throw ES80GuidedCapturePlanError.processRelaunchRequiresTrustedBoundaryAPI
        }
        try recordContinuityBreakUnchecked(cause, lastAcceptedWatermark: watermark)
    }

    /// Explicitly records that restored unfinished state crossed a process boundary.
    ///
    /// The trusted restoration coordinator calls this on ordinary decoded state. It only converts
    /// that inert state into a terminal continuity record; it never enables workflow mutations. No
    /// relaunch timestamp is manufactured, and the last accepted pre-relaunch watermark is retained.
    public mutating func recordProcessRelaunchBoundary() throws {
        guard provenance == .decoded else {
            throw ES80GuidedCapturePlanError.processRelaunchBoundaryRequiresDecodedPlan
        }
        guard continuityBreak == nil else {
            throw ES80GuidedCapturePlanError.continuityBroken
        }
        guard !isComplete else {
            throw ES80GuidedCapturePlanError.planComplete
        }
        continuityBreak = ES80GuidedCaptureContinuityBreak(
            cause: .processRelaunch,
            lastAcceptedWatermark: latestAcceptedWatermark,
            abandonedWindow: activeWindow
        )
        activeWindow = nil
        try validate()
    }

    private mutating func recordContinuityBreakUnchecked(
        _ cause: ES80GuidedCaptureContinuityBreakCause,
        lastAcceptedWatermark watermark: ES80GuidedCaptureSourceWatermark?
    ) throws {
        try requireMutablePlan()
        if let watermark {
            try validateConnectionGeneration(watermark)
            if let latest = latestAcceptedWatermark {
                try Self.requireNondecreasing(watermark, after: latest)
            }
        }
        continuityBreak = ES80GuidedCaptureContinuityBreak(
            cause: cause,
            lastAcceptedWatermark: watermark ?? latestAcceptedWatermark,
            abandonedWindow: activeWindow
        )
        activeWindow = nil
    }

    /// Validates the complete durable state, including exact procedure order and chronology.
    public func validate() throws {
        guard schema == Self.schemaIdentifier else {
            throw ES80GuidedCapturePlanError.invalidSchemaIdentifier
        }
        guard version == Self.schemaVersion else {
            throw ES80GuidedCapturePlanError.unsupportedSchemaVersion(version)
        }
        guard connectionGeneration > 0 else {
            throw ES80GuidedCapturePlanError.invalidConnectionGeneration
        }
        guard completedWindows.count <= Self.expectedWindowSequence.count else {
            throw ES80GuidedCapturePlanError.invalidProgress
        }

        var priorReceipt: ES80GuidedCaptureWindowReceipt?
        for (index, receipt) in completedWindows.enumerated() {
            let expected = Self.expectedWindowSequence[index]
            guard receipt.action == expected.action, receipt.phase == expected.phase else {
                throw ES80GuidedCapturePlanError.invalidProgress
            }
            try validateCompleted(receipt, priorReceipt: priorReceipt)
            priorReceipt = receipt
        }

        if let activeWindow {
            guard continuityBreak == nil,
                  completedWindows.count < Self.expectedWindowSequence.count else {
                throw ES80GuidedCapturePlanError.invalidProgress
            }
            let expected = Self.expectedWindowSequence[completedWindows.count]
            guard activeWindow.action == expected.action,
                  activeWindow.phase == expected.phase else {
                throw ES80GuidedCapturePlanError.invalidProgress
            }
            try validateActive(activeWindow, after: priorReceipt?.endedAt)
        }

        if let continuityBreak {
            guard completedWindows.count < Self.expectedWindowSequence.count,
                  activeWindow == nil else {
                throw ES80GuidedCapturePlanError.invalidProgress
            }
            if let abandoned = continuityBreak.abandonedWindow {
                let expected = Self.expectedWindowSequence[completedWindows.count]
                guard abandoned.action == expected.action,
                      abandoned.phase == expected.phase else {
                    throw ES80GuidedCapturePlanError.invalidProgress
                }
                try validateActive(abandoned, after: priorReceipt?.endedAt)
            }
            if let watermark = continuityBreak.lastAcceptedWatermark {
                try validateConnectionGeneration(watermark)
                if let latest = latestWatermark(
                    completed: completedWindows,
                    abandoned: continuityBreak.abandonedWindow
                ) {
                    try Self.requireNondecreasing(watermark, after: latest)
                }
            }
        }

        if completedWindows.count == Self.expectedWindowSequence.count {
            guard activeWindow == nil, continuityBreak == nil else {
                throw ES80GuidedCapturePlanError.invalidProgress
            }
        }
    }

    /// Returns the one bounded canonical representation accepted by strict import.
    /// Validation occurs before encoding, and oversized output is rejected before it is returned.
    public static func encodeCanonicalJSON(_ plan: Self) throws -> Data {
        try plan.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(plan)
        guard data.count <= maximumCanonicalJSONByteCount else {
            throw ES80GuidedCapturePlanError.outputByteLimitExceeded(
                byteCount: data.count,
                maximum: maximumCanonicalJSONByteCount
            )
        }
        return data
    }

    /// Duplicate keys, unknown fields, unsupported versions, noncanonical bytes, and invalid state
    /// fail closed. Exact input bytes are verified before unfinished state is terminalized with an
    /// explicit `.processRelaunch` continuity record.
    public static func decodeStrictJSON(_ data: Data) throws -> Self {
        guard data.count <= maximumCanonicalJSONByteCount else {
            throw ES80GuidedCapturePlanError.inputByteLimitExceeded(
                byteCount: data.count,
                maximum: maximumCanonicalJSONByteCount
            )
        }
        if let duplicate = PassiveBluetoothStrictJSON.duplicateTopLevelObjectKey(in: data) {
            throw ES80GuidedCapturePlanError.duplicateTopLevelJSONKey(duplicate)
        }
        var plan = try JSONDecoder().decode(Self.self, from: data)
        guard try encodeCanonicalJSON(plan) == data else {
            throw ES80GuidedCapturePlanError.nonCanonicalJSON
        }
        if !plan.isComplete, plan.continuityBreak == nil {
            try plan.recordProcessRelaunchBoundary()
        }
        return plan
    }

    private static let expectedWindowSequence: [(
        action: ES80GuidedCaptureAction,
        phase: ES80GuidedCaptureWindowPhase
    )] = requiredActions.flatMap { action in
        ES80GuidedCaptureWindowPhase.allCases.map { (action: action, phase: $0) }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema
        case version
        case sourceSessionID
        case connectionGeneration
        case completedWindows
        case activeWindow
        case continuityBreak
    }

    public init(from decoder: Decoder) throws {
        try ES80GuidedCaptureCoding.rejectUnknownKeys(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.rawValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        version = try container.decode(Int.self, forKey: .version)
        sourceSessionID = try container.decode(
            TuyaStructuredApplicationSessionID.self,
            forKey: .sourceSessionID
        )
        connectionGeneration = try container.decode(UInt64.self, forKey: .connectionGeneration)
        completedWindows = try container.decode(
            [ES80GuidedCaptureWindowReceipt].self,
            forKey: .completedWindows
        )
        activeWindow = try container.decodeIfPresent(
            ES80GuidedCaptureActiveWindow.self,
            forKey: .activeWindow
        )
        continuityBreak = try container.decodeIfPresent(
            ES80GuidedCaptureContinuityBreak.self,
            forKey: .continuityBreak
        )
        provenance = .decoded

        try validate()
    }

    private var latestAcceptedWatermark: ES80GuidedCaptureSourceWatermark? {
        latestWatermark(completed: completedWindows, abandoned: activeWindow)
    }

    private func latestWatermark(
        completed: [ES80GuidedCaptureWindowReceipt],
        abandoned: ES80GuidedCaptureActiveWindow?
    ) -> ES80GuidedCaptureSourceWatermark? {
        if let abandoned {
            return abandoned.evidenceReceipts.last?.watermark ?? abandoned.startedAt
        }
        return completed.last?.endedAt
    }

    private mutating func sealActiveWindow(
        endingAt watermark: ES80GuidedCaptureSourceWatermark,
        completion: ES80GuidedCaptureWindowCompletion
    ) throws {
        guard let window = activeWindow else {
            throw ES80GuidedCapturePlanError.windowNotActive
        }
        guard !window.evidenceReceipts.isEmpty else {
            throw ES80GuidedCapturePlanError.windowHasNoEvidence
        }
        completedWindows.append(
            ES80GuidedCaptureWindowReceipt(
                action: window.action,
                phase: window.phase,
                startedAt: window.startedAt,
                endedAt: watermark,
                evidenceReceipts: window.evidenceReceipts,
                completion: completion
            )
        )
        activeWindow = nil
    }

    private func validateEnd(
        _ watermark: ES80GuidedCaptureSourceWatermark,
        for window: ES80GuidedCaptureActiveWindow
    ) throws {
        try validateConnectionGeneration(watermark)
        guard !window.evidenceReceipts.isEmpty else {
            throw ES80GuidedCapturePlanError.windowHasNoEvidence
        }
        let latest = window.evidenceReceipts.last?.watermark ?? window.startedAt
        try Self.requireNondecreasing(watermark, after: latest)
    }

    private func validateCompleted(
        _ receipt: ES80GuidedCaptureWindowReceipt,
        priorReceipt: ES80GuidedCaptureWindowReceipt?
    ) throws {
        try validateConnectionGeneration(receipt.startedAt)
        try validateConnectionGeneration(receipt.endedAt)
        if let priorReceipt {
            try Self.requireNondecreasing(receipt.startedAt, after: priorReceipt.endedAt)
        }
        guard !receipt.evidenceReceipts.isEmpty else {
            throw ES80GuidedCapturePlanError.windowHasNoEvidence
        }
        try validateEvidence(
            receipt.evidenceReceipts,
            after: receipt.startedAt,
            through: receipt.endedAt
        )
        switch receipt.completion {
        case .explicitOperatorConfirmation:
            guard receipt.phase == .during else {
                throw ES80GuidedCapturePlanError.invalidProgress
            }
        case .nonOperatorObservationWindowCompletion:
            guard receipt.phase == .before || receipt.phase == .after else {
                throw ES80GuidedCapturePlanError.invalidProgress
            }
        }
    }

    private func validateActive(
        _ window: ES80GuidedCaptureActiveWindow,
        after prior: ES80GuidedCaptureSourceWatermark?
    ) throws {
        try validateConnectionGeneration(window.startedAt)
        if let prior {
            try Self.requireNondecreasing(window.startedAt, after: prior)
        }
        try validateEvidence(window.evidenceReceipts, after: window.startedAt, through: nil)
    }

    private func validateEvidence(
        _ receipts: [ES80GuidedCaptureEvidenceReceipt],
        after start: ES80GuidedCaptureSourceWatermark,
        through end: ES80GuidedCaptureSourceWatermark?
    ) throws {
        guard receipts.count <= Self.maximumEvidenceReceiptsPerWindow else {
            throw ES80GuidedCapturePlanError.windowEvidenceReceiptLimitExceeded(
                maximum: Self.maximumEvidenceReceiptsPerWindow
            )
        }
        var prior = start
        for receipt in receipts {
            try validateSession(receipt)
            try validateConnectionGeneration(receipt.watermark)
            guard ES80GuidedCaptureCoding.isLowercaseSHA256(
                receipt.canonicalEventSHA256
            ), ES80GuidedCaptureCoding.isLowercaseSHA256(
                receipt.canonicalPayloadSHA256
            ) else {
                throw ES80GuidedCapturePlanError.invalidObservationDigest
            }
            guard receipt.watermark.sourceSequence > prior.sourceSequence else {
                throw ES80GuidedCapturePlanError.invalidSourceSequence
            }
            guard receipt.watermark.receivedAtUptimeNanoseconds
                    >= prior.receivedAtUptimeNanoseconds else {
                throw ES80GuidedCapturePlanError.invalidWindowChronology
            }
            prior = receipt.watermark
        }
        if let end {
            try Self.requireNondecreasing(end, after: prior)
        }
    }

    private func validateConnectionGeneration(
        _ watermark: ES80GuidedCaptureSourceWatermark
    ) throws {
        guard watermark.connectionGeneration == connectionGeneration else {
            throw ES80GuidedCapturePlanError.sourceConnectionGenerationChanged
        }
    }

    private func validateSession(_ receipt: ES80GuidedCaptureEvidenceReceipt) throws {
        guard receipt.pseudonymousSessionID == sourceSessionID else {
            throw ES80GuidedCapturePlanError.sourceSessionChanged
        }
    }

    private func requireMutablePlan() throws {
        guard provenance == .fresh else {
            throw ES80GuidedCapturePlanError.decodedPlanRequiresProcessRelaunchBoundary
        }
        guard continuityBreak == nil else {
            throw ES80GuidedCapturePlanError.continuityBroken
        }
        guard !isComplete else {
            throw ES80GuidedCapturePlanError.planComplete
        }
    }

    private static func requireNondecreasing(
        _ watermark: ES80GuidedCaptureSourceWatermark,
        after prior: ES80GuidedCaptureSourceWatermark
    ) throws {
        guard watermark.sourceSequence >= prior.sourceSequence else {
            throw ES80GuidedCapturePlanError.invalidSourceSequence
        }
        guard watermark.receivedAtUptimeNanoseconds
                >= prior.receivedAtUptimeNanoseconds else {
            throw ES80GuidedCapturePlanError.invalidWindowChronology
        }
    }
}

private enum ES80GuidedCaptureCoding {
    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            self.intValue = intValue
            stringValue = String(intValue)
        }
    }

    static func rejectUnknownKeys(in decoder: Decoder, allowed: [String]) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowed = Set(allowed)
        if let unknown = container.allKeys
            .map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown guided capture key: \(unknown)"
                )
            )
        }
    }

    static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
}
