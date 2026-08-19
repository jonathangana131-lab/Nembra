import Testing
@testable import NembraCore

@Suite("Dashboard session request authority")
struct DashboardSessionStateTests {
    private func activate(
        _ coordinator: inout DashboardSessionCoordinator,
        token: DashboardPortraitRestorationToken
    ) throws -> (DashboardGeometryRequest, DashboardActiveSession) {
        let request = try coordinator.beginEntry(preserving: token)
        let result = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: request.id,
                outcome: .observed(.landscape)
            )
        )
        guard case let .activatedDashboard(session) = result else {
            Issue.record("Expected matching explicit entry receipt to activate Dashboard")
            throw DashboardSessionError.entryRequiresInactiveSession
        }
        return (request, session)
    }

    @Test("passive landscape rotation cannot activate Dashboard")
    func passiveLandscapeCannotActivate() {
        var coordinator = DashboardSessionCoordinator()

        let disposition = coordinator.receive(.passiveObservation(.landscape))

        #expect(disposition == .ignoredPassiveObservation)
        #expect(coordinator.state == .inactive)
    }

    @Test("explicit entry requires a matching landscape receipt")
    func explicitEntryRequiresMatchingReceipt() throws {
        var coordinator = DashboardSessionCoordinator()
        let token = DashboardPortraitRestorationToken()
        let request = try coordinator.beginEntry(preserving: token)

        #expect(request.target == .dashboardLandscape)
        #expect(
            coordinator.state == .opening(
                request: request,
                portraitRestorationToken: token
            )
        )

        let earlyPortrait = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: request.id,
                outcome: .observed(.portrait)
            )
        )
        #expect(earlyPortrait == .awaitingTargetGeometry)
        #expect(
            coordinator.state == .opening(
                request: request,
                portraitRestorationToken: token
            )
        )

        let accepted = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: request.id,
                outcome: .observed(.landscape)
            )
        )
        guard case let .activatedDashboard(session) = accepted else {
            Issue.record("Expected Dashboard activation")
            return
        }
        #expect(session.activationRequestID == request.id)
        #expect(session.portraitRestorationToken == token)
        #expect(coordinator.state == .active(session))
    }

    @Test("stale receipt cannot satisfy a retried entry generation")
    func staleEntryReceiptIsFenced() throws {
        var coordinator = DashboardSessionCoordinator()
        let token = DashboardPortraitRestorationToken()
        let first = try coordinator.beginEntry(preserving: token)
        _ = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: first.id,
                outcome: .failed(.timedOut)
            )
        )

        let recovery = try coordinator.recover(using: .retryGeometryRequest)
        guard case let .geometryRequest(second) = recovery else {
            Issue.record("Expected a retry geometry request")
            return
        }
        #expect(second.id != first.id)

        let stale = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: first.id,
                outcome: .observed(.landscape)
            )
        )
        #expect(stale == .ignoredStaleRequest)
        #expect(
            coordinator.state == .opening(
                request: second,
                portraitRestorationToken: token
            )
        )

        let current = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: second.id,
                outcome: .observed(.landscape)
            )
        )
        guard case let .activatedDashboard(session) = current else {
            Issue.record("Expected current retry to activate Dashboard")
            return
        }
        #expect(session.activationRequestID == second.id)
    }

    @Test("explicit exit restores the same opaque portrait token")
    func explicitExitRestoresPortraitToken() throws {
        var coordinator = DashboardSessionCoordinator()
        let token = DashboardPortraitRestorationToken()
        _ = try activate(&coordinator, token: token)
        let exit = try coordinator.beginExit()

        #expect(exit.target == .portrait)

        let passivePortrait = coordinator.receive(.passiveObservation(.portrait))
        #expect(passivePortrait == .ignoredPassiveObservation)
        guard case .closing = coordinator.state else {
            Issue.record("Passive rotation must not close the logical session")
            return
        }

        let completed = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: exit.id,
                outcome: .observed(.portrait)
            )
        )
        #expect(completed == .restoredPortrait(token))
        #expect(coordinator.state == .inactive)
    }

    @Test("failed entry offers retry or an explicit return to portrait")
    func failedEntryHasActionableRecovery() throws {
        var coordinator = DashboardSessionCoordinator()
        let token = DashboardPortraitRestorationToken()
        let request = try coordinator.beginEntry(preserving: token)
        let disposition = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: request.id,
                outcome: .failed(.requestDenied)
            )
        )

        guard case let .transitionedToFailure(failure) = disposition else {
            Issue.record("Expected entry failure state")
            return
        }
        #expect(failure.reason == .requestDenied)
        #expect(failure.stablePresentation == .portrait(restorationToken: token))
        #expect(
            failure.availableRecoveryActions == [
                .retryGeometryRequest,
                .stayInPortrait,
            ]
        )
        #expect(coordinator.state == .failure(failure))

        let recovery = try coordinator.recover(using: .stayInPortrait)
        #expect(recovery == .restorePortrait(token))
        #expect(coordinator.state == .inactive)
    }

    @Test("failed exit can return to the still-active Dashboard session")
    func failedExitCanContinueDashboard() throws {
        var coordinator = DashboardSessionCoordinator()
        let token = DashboardPortraitRestorationToken()
        let (_, activeSession) = try activate(&coordinator, token: token)
        let exit = try coordinator.beginExit()
        let disposition = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: exit.id,
                outcome: .failed(.sceneUnavailable)
            )
        )

        guard case let .transitionedToFailure(failure) = disposition else {
            Issue.record("Expected exit failure state")
            return
        }
        #expect(failure.stablePresentation == .dashboard(session: activeSession))
        #expect(
            failure.availableRecoveryActions == [
                .retryGeometryRequest,
                .continueDashboard,
            ]
        )

        let recovery = try coordinator.recover(using: .continueDashboard)
        #expect(recovery == .dashboardRemainsActive(activeSession))
        #expect(coordinator.state == .active(activeSession))
    }

    @Test("stale exit receipt cannot close a retried exit generation")
    func staleExitReceiptIsFenced() throws {
        var coordinator = DashboardSessionCoordinator()
        let token = DashboardPortraitRestorationToken()
        let (_, activeSession) = try activate(&coordinator, token: token)
        let firstExit = try coordinator.beginExit()
        _ = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: firstExit.id,
                outcome: .failed(.timedOut)
            )
        )

        let recovery = try coordinator.recover(using: .retryGeometryRequest)
        guard case let .geometryRequest(secondExit) = recovery else {
            Issue.record("Expected a retried exit request")
            return
        }
        #expect(secondExit.id != firstExit.id)

        let stale = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: firstExit.id,
                outcome: .observed(.portrait)
            )
        )
        #expect(stale == .ignoredStaleRequest)
        #expect(coordinator.state == .closing(request: secondExit, session: activeSession))

        let current = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: secondExit.id,
                outcome: .observed(.portrait)
            )
        )
        #expect(current == .restoredPortrait(token))
        #expect(coordinator.state == .inactive)
    }

    @Test("entry and exit commands enforce their stable source phase")
    func commandsEnforceSourcePhase() throws {
        var coordinator = DashboardSessionCoordinator()
        #expect(throws: DashboardSessionError.exitRequiresActiveSession) {
            _ = try coordinator.beginExit()
        }

        let token = DashboardPortraitRestorationToken()
        _ = try coordinator.beginEntry(preserving: token)
        #expect(throws: DashboardSessionError.entryRequiresInactiveSession) {
            _ = try coordinator.beginEntry(preserving: token)
        }
        #expect(throws: DashboardSessionError.exitRequiresActiveSession) {
            _ = try coordinator.beginExit()
        }
    }

    @Test("receipts after a completed transition have no pending authority")
    func completedReceiptCannotReplay() throws {
        var coordinator = DashboardSessionCoordinator()
        let token = DashboardPortraitRestorationToken()
        let (entry, _) = try activate(&coordinator, token: token)

        let replay = coordinator.receive(
            DashboardGeometryReceipt(
                requestID: entry.id,
                outcome: .failed(.systemRejected(description: "late callback"))
            )
        )
        #expect(replay == .ignoredNoPendingRequest)
        guard case .active = coordinator.state else {
            Issue.record("A completed entry request must stay retired")
            return
        }
    }

    @Test("request sequence exhaustion fails before mutating state")
    func requestSequenceExhaustionFailsClosed() {
        var coordinator = DashboardSessionCoordinator(initialRequestSequence: UInt64.max)
        let token = DashboardPortraitRestorationToken()

        #expect(throws: DashboardSessionError.requestSequenceExhausted) {
            _ = try coordinator.beginEntry(preserving: token)
        }
        #expect(coordinator.state == .inactive)
    }
}
