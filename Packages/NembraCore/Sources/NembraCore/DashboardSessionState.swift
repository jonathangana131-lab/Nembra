import Foundation

/// An app-owned key for the portrait navigation state that must be restored
/// when Dashboard closes.
///
/// NembraCore deliberately cannot inspect or manufacture portrait navigation
/// content. The application keeps the corresponding snapshot in its own store
/// and uses this opaque token only to correlate entry and restoration.
public struct DashboardPortraitRestorationToken: Equatable, Hashable, Sendable {
    private let value: UUID

    public init() {
        value = UUID()
    }
}

/// Product-level geometry states, intentionally independent of UIKit.
/// Landscape-left and landscape-right both satisfy Dashboard's landscape
/// contract; the app shell remains responsible for the platform orientation
/// mask used for a request.
public enum DashboardSceneGeometry: Equatable, Sendable {
    case portrait
    case landscape
    case indeterminate
}

public enum DashboardGeometryTarget: Equatable, Sendable {
    case dashboardLandscape
    case portrait

    fileprivate func isSatisfied(by geometry: DashboardSceneGeometry) -> Bool {
        switch (self, geometry) {
        case (.dashboardLandscape, .landscape), (.portrait, .portrait):
            true
        default:
            false
        }
    }
}

/// A process-local fence for exactly one geometry request.
///
/// The value is intentionally opaque. Callers carry the ID into platform
/// callbacks but cannot mint or reinterpret request generations.
public struct DashboardGeometryRequestID: Equatable, Hashable, Sendable {
    fileprivate let sequence: UInt64

    fileprivate init(sequence: UInt64) {
        self.sequence = sequence
    }
}

public struct DashboardGeometryRequest: Equatable, Sendable {
    public let id: DashboardGeometryRequestID
    public let target: DashboardGeometryTarget

    fileprivate init(id: DashboardGeometryRequestID, target: DashboardGeometryTarget) {
        self.id = id
        self.target = target
    }
}

public enum DashboardGeometryFailureReason: Equatable, Sendable {
    /// No foreground scene was available to receive the request.
    case sceneUnavailable
    /// The current device/app configuration does not support the target.
    case unsupportedGeometry
    /// The system rejected the public geometry request.
    case requestDenied
    /// No matching scene observation arrived inside the app's bounded wait.
    case timedOut
    /// Sanitized platform context for diagnostics; never use raw `Error` as
    /// state because its identity and sendability are not deterministic.
    case systemRejected(description: String)
}

public enum DashboardGeometryReceiptOutcome: Equatable, Sendable {
    case observed(DashboardSceneGeometry)
    case failed(DashboardGeometryFailureReason)
}

/// A platform callback or scene observation associated with one request.
/// Passive geometry observations intentionally have no request ID and cannot
/// grant Dashboard presentation authority.
public struct DashboardGeometryReceipt: Equatable, Sendable {
    public let requestID: DashboardGeometryRequestID?
    public let outcome: DashboardGeometryReceiptOutcome

    public init(
        requestID: DashboardGeometryRequestID,
        outcome: DashboardGeometryReceiptOutcome
    ) {
        self.requestID = requestID
        self.outcome = outcome
    }

    public static func passiveObservation(
        _ geometry: DashboardSceneGeometry
    ) -> DashboardGeometryReceipt {
        DashboardGeometryReceipt(
            requestID: nil,
            outcome: .observed(geometry)
        )
    }

    private init(
        requestID: DashboardGeometryRequestID?,
        outcome: DashboardGeometryReceiptOutcome
    ) {
        self.requestID = requestID
        self.outcome = outcome
    }
}

public struct DashboardActiveSession: Equatable, Sendable {
    public let activationRequestID: DashboardGeometryRequestID
    public let portraitRestorationToken: DashboardPortraitRestorationToken

    fileprivate init(
        activationRequestID: DashboardGeometryRequestID,
        portraitRestorationToken: DashboardPortraitRestorationToken
    ) {
        self.activationRequestID = activationRequestID
        self.portraitRestorationToken = portraitRestorationToken
    }
}

/// The last presentation state known to remain usable after a failed geometry
/// transition. This makes failure recovery explicit instead of asking UI code
/// to infer whether Dashboard or portrait content still owns the scene.
public enum DashboardStablePresentation: Equatable, Sendable {
    case portrait(restorationToken: DashboardPortraitRestorationToken)
    case dashboard(session: DashboardActiveSession)
}

public enum DashboardSessionRecoveryAction: Equatable, Sendable {
    case retryGeometryRequest
    case stayInPortrait
    case continueDashboard
}

public struct DashboardSessionFailure: Equatable, Sendable {
    public let failedRequest: DashboardGeometryRequest
    public let reason: DashboardGeometryFailureReason
    public let stablePresentation: DashboardStablePresentation

    public var availableRecoveryActions: [DashboardSessionRecoveryAction] {
        switch stablePresentation {
        case .portrait:
            [.retryGeometryRequest, .stayInPortrait]
        case .dashboard:
            [.retryGeometryRequest, .continueDashboard]
        }
    }

    fileprivate init(
        failedRequest: DashboardGeometryRequest,
        reason: DashboardGeometryFailureReason,
        stablePresentation: DashboardStablePresentation
    ) {
        self.failedRequest = failedRequest
        self.reason = reason
        self.stablePresentation = stablePresentation
    }
}

public enum DashboardSessionState: Equatable, Sendable {
    case inactive
    case opening(
        request: DashboardGeometryRequest,
        portraitRestorationToken: DashboardPortraitRestorationToken
    )
    case active(DashboardActiveSession)
    case closing(request: DashboardGeometryRequest, session: DashboardActiveSession)
    case failure(DashboardSessionFailure)
}

public enum DashboardGeometryReceiptDisposition: Equatable, Sendable {
    case ignoredPassiveObservation
    case ignoredNoPendingRequest
    case ignoredStaleRequest
    case awaitingTargetGeometry
    case activatedDashboard(DashboardActiveSession)
    case restoredPortrait(DashboardPortraitRestorationToken)
    case transitionedToFailure(DashboardSessionFailure)
}

public enum DashboardSessionRecoveryResult: Equatable, Sendable {
    case geometryRequest(DashboardGeometryRequest)
    case restorePortrait(DashboardPortraitRestorationToken)
    case dashboardRemainsActive(DashboardActiveSession)
}

public enum DashboardSessionError: Error, Equatable, Sendable {
    case entryRequiresInactiveSession
    case exitRequiresActiveSession
    case recoveryRequiresFailure
    case recoveryActionUnavailable(DashboardSessionRecoveryAction)
    case requestSequenceExhausted
}

/// Pure request/receipt authority for the portrait-to-Dashboard session shell.
///
/// Scene size classes and passive device rotation are observations, not entry
/// commands. Dashboard becomes active only after an explicit `beginEntry` and
/// a matching, target-satisfying receipt. Exit follows the same fenced path so
/// the caller can restore exactly the portrait state captured at entry.
public struct DashboardSessionCoordinator: Sendable {
    public private(set) var state: DashboardSessionState
    private var lastRequestSequence: UInt64

    public init() {
        state = .inactive
        lastRequestSequence = 0
    }

    init(initialRequestSequence: UInt64) {
        state = .inactive
        lastRequestSequence = initialRequestSequence
    }

    /// Begins an explicit user-authorized Dashboard entry.
    @discardableResult
    public mutating func beginEntry(
        preserving portraitRestorationToken: DashboardPortraitRestorationToken
    ) throws -> DashboardGeometryRequest {
        guard state == .inactive else {
            throw DashboardSessionError.entryRequiresInactiveSession
        }

        let request = try makeRequest(target: .dashboardLandscape)
        state = .opening(
            request: request,
            portraitRestorationToken: portraitRestorationToken
        )
        return request
    }

    /// Begins an explicit exit. Merely observing portrait geometry cannot close
    /// the logical session or release its restoration token.
    @discardableResult
    public mutating func beginExit() throws -> DashboardGeometryRequest {
        guard case let .active(session) = state else {
            throw DashboardSessionError.exitRequiresActiveSession
        }

        let request = try makeRequest(target: .portrait)
        state = .closing(request: request, session: session)
        return request
    }

    /// Applies only the callback for the currently pending request generation.
    /// Superseded callbacks, callbacks after a failure decision, and passive
    /// observations are inert.
    @discardableResult
    public mutating func receive(
        _ receipt: DashboardGeometryReceipt
    ) -> DashboardGeometryReceiptDisposition {
        guard let requestID = receipt.requestID else {
            return .ignoredPassiveObservation
        }

        switch state {
        case let .opening(request, restorationToken):
            guard request.id == requestID else {
                return .ignoredStaleRequest
            }
            switch receipt.outcome {
            case let .observed(geometry):
                guard request.target.isSatisfied(by: geometry) else {
                    return .awaitingTargetGeometry
                }
                let session = DashboardActiveSession(
                    activationRequestID: request.id,
                    portraitRestorationToken: restorationToken
                )
                state = .active(session)
                return .activatedDashboard(session)
            case let .failed(reason):
                let failure = DashboardSessionFailure(
                    failedRequest: request,
                    reason: reason,
                    stablePresentation: .portrait(restorationToken: restorationToken)
                )
                state = .failure(failure)
                return .transitionedToFailure(failure)
            }

        case let .closing(request, session):
            guard request.id == requestID else {
                return .ignoredStaleRequest
            }
            switch receipt.outcome {
            case let .observed(geometry):
                guard request.target.isSatisfied(by: geometry) else {
                    return .awaitingTargetGeometry
                }
                state = .inactive
                return .restoredPortrait(session.portraitRestorationToken)
            case let .failed(reason):
                let failure = DashboardSessionFailure(
                    failedRequest: request,
                    reason: reason,
                    stablePresentation: .dashboard(session: session)
                )
                state = .failure(failure)
                return .transitionedToFailure(failure)
            }

        case .inactive, .active, .failure:
            return .ignoredNoPendingRequest
        }
    }

    /// Executes one of the recovery actions advertised by the current failure.
    /// A retry always mints a new request fence before any platform work starts.
    @discardableResult
    public mutating func recover(
        using action: DashboardSessionRecoveryAction
    ) throws -> DashboardSessionRecoveryResult {
        guard case let .failure(failure) = state else {
            throw DashboardSessionError.recoveryRequiresFailure
        }
        guard failure.availableRecoveryActions.contains(action) else {
            throw DashboardSessionError.recoveryActionUnavailable(action)
        }

        switch (failure.stablePresentation, action) {
        case let (.portrait(restorationToken), .retryGeometryRequest):
            let request = try makeRequest(target: .dashboardLandscape)
            state = .opening(
                request: request,
                portraitRestorationToken: restorationToken
            )
            return .geometryRequest(request)

        case let (.portrait(restorationToken), .stayInPortrait):
            state = .inactive
            return .restorePortrait(restorationToken)

        case let (.dashboard(session), .retryGeometryRequest):
            let request = try makeRequest(target: .portrait)
            state = .closing(request: request, session: session)
            return .geometryRequest(request)

        case let (.dashboard(session), .continueDashboard):
            state = .active(session)
            return .dashboardRemainsActive(session)

        case (.portrait, .continueDashboard), (.dashboard, .stayInPortrait):
            throw DashboardSessionError.recoveryActionUnavailable(action)
        }
    }

    private mutating func makeRequest(
        target: DashboardGeometryTarget
    ) throws -> DashboardGeometryRequest {
        guard lastRequestSequence < UInt64.max else {
            throw DashboardSessionError.requestSequenceExhausted
        }
        lastRequestSequence += 1
        return DashboardGeometryRequest(
            id: DashboardGeometryRequestID(sequence: lastRequestSequence),
            target: target
        )
    }
}
