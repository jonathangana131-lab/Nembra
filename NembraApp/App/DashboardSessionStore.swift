import Foundation
import NembraCore
import Observation
import SwiftUI
import UIKit

private enum InactivePortraitOwnershipState: Equatable {
    case awaitingScene
    case ready
    case restoring
    case failed(message: String)
}

private struct DashboardPlatformGeometryAttempt: Equatable, Sendable {
    let id: UUID
    let requestID: DashboardGeometryRequestID
    let sceneIdentity: ObjectIdentifier
}

/// UIKit bridge for the explicit portrait <-> Horizon Dashboard session.
///
/// Device rotation is an observation, never an entry command. Only a matching
/// receipt for a request minted by `DashboardSessionCoordinator` may reveal the
/// cockpit or release its portrait restoration token.
@MainActor
@Observable
final class DashboardSessionStore {
    private(set) var state: DashboardSessionState = .inactive
    private(set) var restoredPortraitToken: DashboardPortraitRestorationToken?
    private(set) var latestSceneGeometry: DashboardSceneGeometry = .indeterminate

    private var inactivePortraitOwnership: InactivePortraitOwnershipState = .awaitingScene
    private var dashboardAuthorizedSceneIdentity: ObjectIdentifier?

    @ObservationIgnored private var coordinator = DashboardSessionCoordinator()
    @ObservationIgnored private weak var windowScene: UIWindowScene?
    @ObservationIgnored private var windowSceneIdentity: ObjectIdentifier?
    @ObservationIgnored private var platformGeometryAttempt: DashboardPlatformGeometryAttempt?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var inactivePortraitRequestID: UUID?
    @ObservationIgnored private var inactivePortraitTimeoutTask: Task<Void, Never>?

    var presentsDashboard: Bool {
        guard hasCurrentDashboardSceneAuthority else { return false }
        return switch state {
        case .active, .closing:
            true
        case let .failure(failure):
            if case .dashboard = failure.stablePresentation { true } else { false }
        case .inactive, .opening:
            false
        }
    }

    var canKeepStablePresentationAfterFailure: Bool {
        guard case let .failure(failure) = state else { return false }
        return switch failure.stablePresentation {
        case .portrait:
            true
        case .dashboard:
            hasCurrentDashboardSceneAuthority
        }
    }

    var isOpening: Bool {
        if case .opening = state { true } else { false }
    }

    var isClosing: Bool {
        if case .closing = state { true } else { false }
    }

    var failure: DashboardSessionFailure? {
        if case let .failure(failure) = state { failure } else { nil }
    }

    /// Portrait content remains opaque until the exact owning scene has reported
    /// portrait geometry. This state is independent from Dashboard's coordinator:
    /// correcting passive Home geometry can never grant cockpit presentation.
    var canPresentPortraitContent: Bool {
        guard !presentsDashboard,
              latestSceneGeometry == .portrait else { return false }
        if case .ready = inactivePortraitOwnership { return true }
        return false
    }

    var isRestoringInactivePortrait: Bool {
        guard case .inactive = state else { return false }
        return switch inactivePortraitOwnership {
        case .awaitingScene, .restoring:
            true
        case .ready, .failed:
            false
        }
    }

    var inactivePortraitFailureMessage: String? {
        guard case .inactive = state,
              case let .failed(message) = inactivePortraitOwnership else {
            return nil
        }
        return message
    }

    func attach(windowScene: UIWindowScene) {
        let identity = ObjectIdentifier(windowScene)
        let sceneChanged = identity != windowSceneIdentity
        let mustRestorePortraitAfterSceneChange = sceneChanged && stateOwnsDashboardPresentation
        let requestToReissue = sceneChanged && !mustRestorePortraitAfterSceneChange
            ? pendingRequest
            : nil
        if sceneChanged {
            cancelInactivePortraitRequest()
            platformGeometryAttempt = nil
            windowSceneIdentity = identity
            latestSceneGeometry = .indeterminate
            if mustRestorePortraitAfterSceneChange {
                // A receipt authorizes only the UIWindowScene that performed its
                // request. Reparenting revokes that authority synchronously so the
                // cockpit cannot flash in a different scene while portrait is
                // restored there.
                dashboardAuthorizedSceneIdentity = nil
            }
            if case .inactive = state {
                inactivePortraitOwnership = .awaitingScene
            }
        }
        self.windowScene = windowScene

        if mustRestorePortraitAfterSceneChange {
            restorePortraitAfterDashboardSceneChange()
            return
        }

        // A representable can be reparented to another window scene without an
        // orientation change. Bind the still-pending request to the new scene
        // before accepting its geometry; otherwise a passive landscape scene
        // could satisfy a request that was performed only on the prior scene.
        if let request = requestToReissue {
            perform(request)
            return
        }

        receiveSceneGeometry(sceneGeometry(for: windowScene))
    }

    func beginEntry(preserving token: DashboardPortraitRestorationToken) {
        restoredPortraitToken = nil
        do {
            let request = try coordinator.beginEntry(preserving: token)
            dashboardAuthorizedSceneIdentity = nil
            cancelInactivePortraitRequest()
            synchronizeState()
            perform(request)
        } catch {
            // Repeated taps while a request/session owns the scene are inert.
            // The pure coordinator remains the authority for legal transitions.
        }
    }

    func beginExit() {
        do {
            let request = try coordinator.beginExit()
            synchronizeState()
            perform(request)
        } catch {
            // Exit is available only from a fully active session.
        }
    }

    func receiveSceneGeometry(_ geometry: DashboardSceneGeometry) {
        latestSceneGeometry = geometry
        let receipt: DashboardGeometryReceipt
        if let request = pendingRequest {
            receipt = DashboardGeometryReceipt(
                requestID: request.id,
                outcome: .observed(geometry)
            )
        } else {
            receipt = .passiveObservation(geometry)
        }
        apply(receipt)
    }

    func retryInactivePortraitRestoration() {
        guard case .inactive = state else { return }
        inactivePortraitOwnership = .awaitingScene
        reconcileInactivePortraitOwnership(forceRequest: true)
    }

    func recover(using action: DashboardSessionRecoveryAction) {
        if action == .continueDashboard, !hasCurrentDashboardSceneAuthority {
            // A dashboard-stable failure from a replaced scene is not stable in
            // the new scene. Never let a stale UI action reauthorize it.
            return
        }
        do {
            let result = try coordinator.recover(using: action)
            synchronizeState()
            switch result {
            case let .geometryRequest(request):
                perform(request)
            case let .restorePortrait(token):
                dashboardAuthorizedSceneIdentity = nil
                restoredPortraitToken = token
            case .dashboardRemainsActive:
                break
            }
            reconcileInactivePortraitOwnership()
        } catch {
            // The UI presents only actions advertised by the current failure.
        }
    }

    func consumeRestoredPortraitToken() {
        restoredPortraitToken = nil
    }

    func failureMessage(_ failure: DashboardSessionFailure) -> String {
        switch failure.reason {
        case .sceneUnavailable:
            "Nembra could not find the active window. Keep the app open and try again."
        case .unsupportedGeometry:
            "This display cannot enter the requested orientation."
        case .requestDenied:
            "iOS did not allow the display to rotate. Check Rotation Lock and try again."
        case .timedOut:
            "The display did not finish rotating. Check Rotation Lock and try again."
        case let .systemRejected(description):
            description.isEmpty
                ? "iOS did not allow the display to rotate."
                : "iOS did not allow the display to rotate: \(description)"
        }
    }

    private var pendingRequest: DashboardGeometryRequest? {
        switch state {
        case let .opening(request, _), let .closing(request, _):
            request
        case .inactive, .active, .failure:
            nil
        }
    }

    private var hasCurrentDashboardSceneAuthority: Bool {
        guard let dashboardAuthorizedSceneIdentity,
              let windowSceneIdentity else { return false }
        return dashboardAuthorizedSceneIdentity == windowSceneIdentity
    }

    private var stateOwnsDashboardPresentation: Bool {
        switch state {
        case .active, .closing:
            true
        case let .failure(failure):
            if case .dashboard = failure.stablePresentation { true } else { false }
        case .inactive, .opening:
            false
        }
    }

    private func perform(_ request: DashboardGeometryRequest) {
        timeoutTask?.cancel()
        platformGeometryAttempt = nil

        guard let windowScene,
              let windowSceneIdentity,
              windowSceneIdentity == ObjectIdentifier(windowScene) else {
            apply(
                DashboardGeometryReceipt(
                    requestID: request.id,
                    outcome: .failed(.sceneUnavailable)
                )
            )
            return
        }

        let attempt = DashboardPlatformGeometryAttempt(
            id: UUID(),
            requestID: request.id,
            sceneIdentity: windowSceneIdentity
        )
        platformGeometryAttempt = attempt

        let orientationMask: UIInterfaceOrientationMask = switch request.target {
        case .dashboardLandscape: .landscape
        case .portrait: .portrait
        }

        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: orientationMask)
        ) { [weak self] error in
            let description = Self.sanitized(error.localizedDescription)
            Task { @MainActor [weak self] in
                self?.failPlatformGeometryAttemptIfCurrent(
                    attempt,
                    reason: .systemRejected(description: description)
                )
            }
        }

        // If the scene already satisfies the explicit request, activation does
        // not wait for an unrelated size-class publication.
        receiveSceneGeometry(sceneGeometry(for: windowScene))
        scheduleTimeout(for: request, attempt: attempt)
    }

    private func scheduleTimeout(
        for request: DashboardGeometryRequest,
        attempt: DashboardPlatformGeometryAttempt
    ) {
        guard pendingRequest?.id == request.id,
              platformGeometryAttempt == attempt else { return }
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  self.pendingRequest?.id == request.id,
                  self.platformGeometryAttempt == attempt else { return }

            // UIKit can publish the final layout callback late while the scene is
            // transitioning. Reconcile the exact scene's effective geometry once
            // more before declaring a timeout.
            if let scene = self.windowScene,
               self.windowSceneIdentity == attempt.sceneIdentity,
               ObjectIdentifier(scene) == attempt.sceneIdentity {
                self.receiveSceneGeometry(self.sceneGeometry(for: scene))
            }
            guard self.pendingRequest?.id == request.id,
                  self.platformGeometryAttempt == attempt else { return }
            self.apply(
                DashboardGeometryReceipt(
                    requestID: request.id,
                    outcome: .failed(.timedOut)
                )
            )
        }
    }

    private func apply(_ receipt: DashboardGeometryReceipt) {
        let receiptSceneIdentity: ObjectIdentifier? = if let requestID = receipt.requestID,
                                                         let attempt = platformGeometryAttempt,
                                                         attempt.requestID == requestID,
                                                         attempt.sceneIdentity == windowSceneIdentity,
                                                         let windowScene,
                                                         ObjectIdentifier(windowScene) == attempt.sceneIdentity {
            attempt.sceneIdentity
        } else {
            nil
        }
        let disposition = coordinator.receive(receipt)
        synchronizeState()
        switch disposition {
        case let .restoredPortrait(token):
            dashboardAuthorizedSceneIdentity = nil
            restoredPortraitToken = token
        case .activatedDashboard:
            dashboardAuthorizedSceneIdentity = receiptSceneIdentity
            if receiptSceneIdentity == nil {
                // Defensive fail-closed path: a matching request ID without an
                // exact current-scene platform attempt cannot present Dashboard.
                restorePortraitAfterDashboardSceneChange()
            }
        case let .transitionedToFailure(failure):
            if case .portrait = failure.stablePresentation {
                dashboardAuthorizedSceneIdentity = nil
            }
        case .ignoredPassiveObservation, .ignoredNoPendingRequest,
             .ignoredStaleRequest, .awaitingTargetGeometry:
            break
        }
        reconcileInactivePortraitOwnership()
    }

    private func restorePortraitAfterDashboardSceneChange() {
        do {
            let request: DashboardGeometryRequest
            switch state {
            case .active:
                request = try coordinator.beginExit()
                synchronizeState()
            case let .closing(pendingRequest, _):
                request = pendingRequest
            case let .failure(failure):
                guard case .dashboard = failure.stablePresentation,
                      case let .geometryRequest(retryRequest) = try coordinator.recover(
                        using: .retryGeometryRequest
                      ) else { return }
                synchronizeState()
                request = retryRequest
            case .inactive, .opening:
                return
            }
            perform(request)
        } catch {
            // Sequence exhaustion or an illegal transition leaves presentation
            // opaque. It must never revive authority from the replaced scene.
        }
    }

    private func synchronizeState() {
        state = coordinator.state
        if pendingRequest == nil {
            timeoutTask?.cancel()
            timeoutTask = nil
            platformGeometryAttempt = nil
        }
    }

    private func failPlatformGeometryAttemptIfCurrent(
        _ attempt: DashboardPlatformGeometryAttempt,
        reason: DashboardGeometryFailureReason
    ) {
        guard platformGeometryAttempt == attempt,
              pendingRequest?.id == attempt.requestID else { return }

        // The error callback can race a successful geometry update. Effective
        // geometry wins when it already satisfies the coordinator-owned request.
        if let scene = windowScene,
           windowSceneIdentity == attempt.sceneIdentity,
           ObjectIdentifier(scene) == attempt.sceneIdentity {
            receiveSceneGeometry(sceneGeometry(for: scene))
        }
        guard platformGeometryAttempt == attempt,
              pendingRequest?.id == attempt.requestID else { return }
        apply(
            DashboardGeometryReceipt(
                requestID: attempt.requestID,
                outcome: .failed(reason)
            )
        )
    }

    private func reconcileInactivePortraitOwnership(forceRequest: Bool = false) {
        guard case .inactive = state else {
            cancelInactivePortraitRequest()
            return
        }

        if latestSceneGeometry == .portrait {
            cancelInactivePortraitRequest()
            inactivePortraitOwnership = .ready
            return
        }

        if !forceRequest {
            switch inactivePortraitOwnership {
            case .restoring, .failed:
                return
            case .awaitingScene, .ready:
                break
            }
        }
        requestInactivePortraitRestoration()
    }

    /// Home's portrait correction is deliberately separate from the Dashboard
    /// coordinator. Its private request token can restore portrait presentation,
    /// but it is structurally incapable of minting a Dashboard geometry receipt.
    private func requestInactivePortraitRestoration() {
        cancelInactivePortraitRequest()
        guard case .inactive = state,
              let scene = windowScene,
              let sceneIdentity = windowSceneIdentity,
              ObjectIdentifier(scene) == sceneIdentity else {
            inactivePortraitOwnership = .awaitingScene
            return
        }

        let requestID = UUID()
        inactivePortraitRequestID = requestID
        inactivePortraitOwnership = .restoring

        scene.requestGeometryUpdate(
            .iOS(interfaceOrientations: .portrait)
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finishInactivePortraitRequestIfCurrent(
                    requestID,
                    sceneIdentity: sceneIdentity,
                    timedOut: false
                )
            }
        }

        receiveSceneGeometry(sceneGeometry(for: scene))
        guard inactivePortraitRequestID == requestID else { return }
        inactivePortraitTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.finishInactivePortraitRequestIfCurrent(
                requestID,
                sceneIdentity: sceneIdentity,
                timedOut: true
            )
        }
    }

    private func finishInactivePortraitRequestIfCurrent(
        _ requestID: UUID,
        sceneIdentity: ObjectIdentifier,
        timedOut: Bool
    ) {
        guard inactivePortraitRequestID == requestID,
              case .inactive = state,
              windowSceneIdentity == sceneIdentity else { return }

        if let scene = windowScene, ObjectIdentifier(scene) == sceneIdentity {
            receiveSceneGeometry(sceneGeometry(for: scene))
        }
        guard inactivePortraitRequestID == requestID else { return }

        cancelInactivePortraitRequest()
        inactivePortraitOwnership = .failed(
            message: timedOut
                ? "Home did not return to portrait. Check Rotation Lock and try again."
                : "iOS did not return Home to portrait. Check Rotation Lock and try again."
        )
    }

    private func cancelInactivePortraitRequest() {
        inactivePortraitRequestID = nil
        inactivePortraitTimeoutTask?.cancel()
        inactivePortraitTimeoutTask = nil
    }

    private func sceneGeometry(for scene: UIWindowScene) -> DashboardSceneGeometry {
        switch scene.effectiveGeometry.interfaceOrientation {
        case .portrait, .portraitUpsideDown:
            .portrait
        case .landscapeLeft, .landscapeRight:
            .landscape
        case .unknown:
            .indeterminate
        @unknown default:
            .indeterminate
        }
    }

    nonisolated private static func sanitized(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .prefix(180)
            .description
    }
}

/// Supplies the exact owning window scene without searching global connected
/// scenes (which is ambiguous once the app supports more than one window).
struct DashboardWindowSceneReader: UIViewRepresentable {
    let onSceneAvailable: @MainActor (UIWindowScene) -> Void

    func makeUIView(context: Context) -> DashboardSceneProbeView {
        DashboardSceneProbeView(onSceneAvailable: onSceneAvailable)
    }

    func updateUIView(_ uiView: DashboardSceneProbeView, context: Context) {
        uiView.onSceneAvailable = onSceneAvailable
        uiView.reportSceneIfAvailable()
    }
}

@MainActor
final class DashboardSceneProbeView: UIView {
    var onSceneAvailable: @MainActor (UIWindowScene) -> Void
    private var lastReportedSceneIdentity: ObjectIdentifier?
    private var lastReportedOrientation: UIInterfaceOrientation?

    init(onSceneAvailable: @escaping @MainActor (UIWindowScene) -> Void) {
        self.onSceneAvailable = onSceneAvailable
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        // Keep the probe in UIKit's layout pass so an orientation update can
        // reach `layoutSubviews`. The SwiftUI wrapper is already a transparent,
        // noninteractive 1x1 accessibility-hidden view, so hiding this UIView
        // would add no presentation benefit and can suppress the callback that
        // supplies the exact post-rotation scene receipt.
        isOpaque = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            lastReportedSceneIdentity = nil
            lastReportedOrientation = nil
        }
        reportSceneIfAvailable()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Geometry updates relayout the exact owning scene. Reporting here
        // delivers the matching post-rotation receipt without global scene
        // searches or treating a passive device rotation as entry authority.
        reportSceneIfAvailable()
    }

    func reportSceneIfAvailable() {
        guard let windowScene = window?.windowScene else { return }
        let sceneIdentity = ObjectIdentifier(windowScene)
        let orientation = windowScene.effectiveGeometry.interfaceOrientation
        guard sceneIdentity != lastReportedSceneIdentity ||
                orientation != lastReportedOrientation else { return }
        lastReportedSceneIdentity = sceneIdentity
        lastReportedOrientation = orientation
        onSceneAvailable(windowScene)
    }
}
