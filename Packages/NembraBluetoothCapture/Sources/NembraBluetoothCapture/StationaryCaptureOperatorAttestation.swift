import Foundation

/// A receipt for the safety conditions that an operator explicitly declared before one
/// stationary capture attempt.
///
/// This value records human declarations only. It is not sensor evidence, scooter telemetry,
/// proof that the charger is electrically disconnected, or proof that the scooter remained
/// stationary after the receipt was created.
public struct StationaryCaptureOperatorAttestation: Codable, Equatable, Sendable {
    /// Exact copy shown to the operator when the declarations were recorded.
    ///
    /// Persisting both the version and statements prevents a later copy change from silently
    /// changing the meaning of a retained receipt.
    public struct Wording: Codable, Equatable, Sendable {
        public static let current = Wording(
            version: "nembra-stationary-operator-attestation-v2",
            stationaryStatement: "The scooter is stationary.",
            poweredOffStatement: "The scooter is powered OFF.",
            chargerDisconnectedStatement: "The charger is disconnected.",
            noRidingStatement: "No one will ride the scooter during this capture.",
            controlsUntouchedStatement: "No one will touch the scooter controls during this capture."
        )

        public let version: String
        public let stationaryStatement: String
        public let poweredOffStatement: String
        public let chargerDisconnectedStatement: String
        public let noRidingStatement: String
        public let controlsUntouchedStatement: String

        public init(
            version: String,
            stationaryStatement: String,
            poweredOffStatement: String,
            chargerDisconnectedStatement: String,
            noRidingStatement: String,
            controlsUntouchedStatement: String
        ) {
            self.version = version
            self.stationaryStatement = stationaryStatement
            self.poweredOffStatement = poweredOffStatement
            self.chargerDisconnectedStatement = chargerDisconnectedStatement
            self.noRidingStatement = noRidingStatement
            self.controlsUntouchedStatement = controlsUntouchedStatement
        }
    }

    /// The five independent declarations required by the stationary procedure.
    public struct Declarations: Codable, Equatable, Sendable {
        public let stationary: Bool
        public let poweredOff: Bool
        public let chargerDisconnected: Bool
        public let noRiding: Bool
        public let controlsUntouched: Bool

        public init(
            stationary: Bool,
            poweredOff: Bool,
            chargerDisconnected: Bool,
            noRiding: Bool,
            controlsUntouched: Bool
        ) {
            self.stationary = stationary
            self.poweredOff = poweredOff
            self.chargerDisconnected = chargerDisconnected
            self.noRiding = noRiding
            self.controlsUntouched = controlsUntouched
        }
    }

    public enum Declaration: String, Codable, Equatable, Sendable {
        case stationary
        case poweredOff
        case chargerDisconnected
        case noRiding
        case controlsUntouched
    }

    /// An identifier minted for one app-owned attempt. A receipt must not be reused after the app
    /// creates a different attempt identifier.
    public let attemptID: UUID

    /// Human-readable wall-clock receipt time for the retained record.
    public let receivedAt: Date

    /// Process-monotonic receipt used for the fail-closed current-attempt chronology check.
    public let receivedAtUptimeNanoseconds: UInt64

    public let wording: Wording
    public let declarations: Declarations

    public init(
        attemptID: UUID,
        receivedAt: Date,
        receivedAtUptimeNanoseconds: UInt64,
        wording: Wording = .current,
        declarations: Declarations
    ) {
        self.attemptID = attemptID
        self.receivedAt = receivedAt
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.wording = wording
        self.declarations = declarations
    }

    /// Missing human declarations in the same deterministic order as the procedure copy.
    public var missingDeclarations: [Declaration] {
        var missing: [Declaration] = []
        if !declarations.stationary { missing.append(.stationary) }
        if !declarations.poweredOff { missing.append(.poweredOff) }
        if !declarations.chargerDisconnected { missing.append(.chargerDisconnected) }
        if !declarations.noRiding { missing.append(.noRiding) }
        if !declarations.controlsUntouched { missing.append(.controlsUntouched) }
        return missing
    }

    public var hasCompleteDeclarations: Bool {
        missingDeclarations.isEmpty
    }

    /// Convenience check for callers that need a Boolean admission gate. Use `verdict` when the
    /// blocked reason must be presented or logged.
    public func isCompleteForCurrentAttempt(
        currentAttemptID: UUID,
        attemptStartedAtUptimeNanoseconds: UInt64,
        nowUptimeNanoseconds: UInt64
    ) -> Bool {
        StationaryCaptureOperatorAttestationGate.verdict(
            for: self,
            currentAttemptID: currentAttemptID,
            attemptStartedAtUptimeNanoseconds: attemptStartedAtUptimeNanoseconds,
            nowUptimeNanoseconds: nowUptimeNanoseconds
        ) == .readyForOperatorDeclaredStationaryCapture
    }
}

/// Fail-closed admission check for a fresh, complete operator attestation.
///
/// A ready verdict means only that all current wording was affirmed during the current app-owned
/// attempt. It deliberately makes no sensor, telemetry, movement, or electrical-state claim.
public enum StationaryCaptureOperatorAttestationGate {
    public enum BlockReason: Equatable, Sendable {
        case missingAttestation
        case differentAttempt
        case unsupportedWording
        case invalidWallClockReceipt
        case receiptOutsideCurrentAttempt
        case incompleteDeclarations([StationaryCaptureOperatorAttestation.Declaration])
    }

    public enum Verdict: Equatable, Sendable {
        case blocked(BlockReason)
        case readyForOperatorDeclaredStationaryCapture
    }

    public static func verdict(
        for attestation: StationaryCaptureOperatorAttestation?,
        currentAttemptID: UUID,
        attemptStartedAtUptimeNanoseconds: UInt64,
        nowUptimeNanoseconds: UInt64
    ) -> Verdict {
        guard let attestation else {
            return .blocked(.missingAttestation)
        }
        guard attestation.attemptID == currentAttemptID else {
            return .blocked(.differentAttempt)
        }
        guard attestation.wording == .current else {
            return .blocked(.unsupportedWording)
        }
        guard attestation.receivedAt.timeIntervalSinceReferenceDate.isFinite else {
            return .blocked(.invalidWallClockReceipt)
        }
        guard attemptStartedAtUptimeNanoseconds <= nowUptimeNanoseconds,
              attestation.receivedAtUptimeNanoseconds >= attemptStartedAtUptimeNanoseconds,
              attestation.receivedAtUptimeNanoseconds <= nowUptimeNanoseconds else {
            return .blocked(.receiptOutsideCurrentAttempt)
        }
        let missing = attestation.missingDeclarations
        guard missing.isEmpty else {
            return .blocked(.incompleteDeclarations(missing))
        }
        return .readyForOperatorDeclaredStationaryCapture
    }
}
