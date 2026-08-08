import Foundation

public enum VehicleCommandUserFeedbackCorrelationError: Error, Equatable, Sendable {
    case requestAlreadyPending
    case noPendingRequest
    case requestDoesNotMatch
    case requestSequenceExhausted
}

/// Opaque identity for one app-local, user-initiated vehicle-command request.
///
/// This identity is presentation causality only. It is not transport authority,
/// a scooter acknowledgement, Bluetooth evidence, or proof that vehicle state changed.
public struct VehicleCommandUserFeedbackRequestID: Hashable, Sendable {
    public let sequence: UInt64
    fileprivate let ownerID: UUID

    fileprivate init(sequence: UInt64, ownerID: UUID) {
        self.sequence = sequence
        self.ownerID = ownerID
    }
}

/// The outcome already accepted by the command owner for the exact local request.
///
/// This type deliberately carries no haptic pattern. Product surfaces remain free
/// to choose whether a confirmed event deserves selection/success feedback or no
/// tactile feedback at all.
public enum VehicleCommandUserFeedbackOutcome: Equatable, Sendable {
    case confirmed
    case failed
}

/// Correlates a single locally initiated command request with its later accepted
/// outcome so presentation feedback cannot be driven by unrelated global state.
///
/// The caller still owns command truth. `resolve` must be invoked only after the
/// existing command/service architecture has accepted a matching outcome. This
/// coordinator never observes `VehicleState`, compares requested/observed values,
/// interprets Bluetooth completion, or manufactures command acknowledgement.
///
/// Nembra currently permits one vehicle command at a time, so this presentation
/// gate intentionally models one pending local request. It is MainActor-bound to
/// keep request admission and outcome consumption serialized with UI interaction.
@MainActor
public final class VehicleCommandUserFeedbackCorrelation {
    private let ownerID = UUID()
    private var nextSequence: UInt64 = 1
    private var pendingRequest: VehicleCommandUserFeedbackRequestID?

    public init() {}

    public var hasPendingUserRequest: Bool {
        pendingRequest != nil
    }

    /// Mints presentation causality for a user action. Starting a second request
    /// while one is unresolved fails closed instead of replacing its provenance.
    public func beginUserRequest() throws -> VehicleCommandUserFeedbackRequestID {
        guard pendingRequest == nil else {
            throw VehicleCommandUserFeedbackCorrelationError.requestAlreadyPending
        }
        guard nextSequence < UInt64.max else {
            throw VehicleCommandUserFeedbackCorrelationError.requestSequenceExhausted
        }

        let request = VehicleCommandUserFeedbackRequestID(
            sequence: nextSequence,
            ownerID: ownerID
        )
        nextSequence += 1
        pendingRequest = request
        return request
    }

    /// Consumes exactly the current locally issued request and returns the
    /// caller-supplied accepted outcome once. Duplicate, stale, foreign, or
    /// otherwise mismatched requests cannot emit a presentation outcome.
    @discardableResult
    public func resolve(
        _ request: VehicleCommandUserFeedbackRequestID,
        as outcome: VehicleCommandUserFeedbackOutcome
    ) throws -> VehicleCommandUserFeedbackOutcome {
        guard let pendingRequest else {
            throw VehicleCommandUserFeedbackCorrelationError.noPendingRequest
        }
        guard pendingRequest == request else {
            throw VehicleCommandUserFeedbackCorrelationError.requestDoesNotMatch
        }

        self.pendingRequest = nil
        return outcome
    }

    /// Clears the exact local request without producing a feedback outcome.
    /// Useful when lifecycle or cancellation invalidates the causal relationship.
    public func abandon(
        _ request: VehicleCommandUserFeedbackRequestID
    ) throws {
        guard let pendingRequest else {
            throw VehicleCommandUserFeedbackCorrelationError.noPendingRequest
        }
        guard pendingRequest == request else {
            throw VehicleCommandUserFeedbackCorrelationError.requestDoesNotMatch
        }

        self.pendingRequest = nil
    }
}
