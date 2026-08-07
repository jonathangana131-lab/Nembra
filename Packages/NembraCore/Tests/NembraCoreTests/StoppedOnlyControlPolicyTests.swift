import Testing
@testable import NembraCore

@Suite("Stopped-only control truth policy")
struct StoppedOnlyControlPolicyTests {
    private let policy = try! StoppedOnlyControlPolicy(
        stoppedThresholdKilometersPerHour: 0.5
    )

    @Test("connected without speed evidence is not proven stopped")
    func unavailableSpeedFailsClosed() {
        let state = policy.motionState(
            connection: .connected,
            speedEvidence: .unavailable
        )

        #expect(state == .notProvenStopped(.speedUnavailable))
        #expect(!state.permitsStoppedOnlyControls)
    }

    @Test("retained zero speed cannot prove the current vehicle is stopped")
    func retainedZeroFailsClosed() {
        let state = policy.motionState(
            connection: .connected,
            speedEvidence: .retained(kilometersPerHour: 0)
        )

        #expect(state == .notProvenStopped(.speedRetained))
        #expect(!state.permitsStoppedOnlyControls)
    }

    @Test("current accepted speed below the injected threshold proves stopped")
    func liveStoppedEvidenceAllowsControls() {
        let zero = policy.motionState(
            connection: .connected,
            speedEvidence: .liveAuthoritative(kilometersPerHour: 0)
        )
        let justBelowThreshold = policy.motionState(
            connection: .connected,
            speedEvidence: .liveAuthoritative(kilometersPerHour: 0.499)
        )

        #expect(zero == .confirmedStopped(kilometersPerHour: 0))
        #expect(justBelowThreshold == .confirmedStopped(kilometersPerHour: 0.499))
        #expect(zero.permitsStoppedOnlyControls)
        #expect(justBelowThreshold.permitsStoppedOnlyControls)
    }

    @Test("threshold and faster current measurements are moving, not unavailable")
    func movingEvidenceRemainsDistinct() {
        let atThreshold = policy.motionState(
            connection: .connected,
            speedEvidence: .liveAuthoritative(kilometersPerHour: 0.5)
        )
        let riding = policy.motionState(
            connection: .connected,
            speedEvidence: .liveAuthoritative(kilometersPerHour: 21.7)
        )

        #expect(atThreshold == .moving(kilometersPerHour: 0.5))
        #expect(riding == .moving(kilometersPerHour: 21.7))
        #expect(!atThreshold.permitsStoppedOnlyControls)
        #expect(!riding.permitsStoppedOnlyControls)
    }

    @Test("non-connected states cannot be overridden by a zero speed value", arguments: [
        VehicleConnectionState.disconnected,
        .connecting,
        .reconnecting
    ])
    func connectionMustBeLive(connection: VehicleConnectionState) {
        let state = policy.motionState(
            connection: connection,
            speedEvidence: .liveAuthoritative(kilometersPerHour: 0)
        )

        #expect(state == .notProvenStopped(.vehicleNotConnected(connection)))
        #expect(!state.permitsStoppedOnlyControls)
    }

    @Test("malformed live speed values fail closed", arguments: [
        -0.01,
        Double.nan,
        Double.infinity,
        -Double.infinity
    ])
    func malformedLiveSpeedFailsClosed(kilometersPerHour: Double) {
        let state = policy.motionState(
            connection: .connected,
            speedEvidence: .liveAuthoritative(kilometersPerHour: kilometersPerHour)
        )

        #expect(state == .notProvenStopped(.invalidLiveSpeedEvidence))
        #expect(!state.permitsStoppedOnlyControls)
    }

    @Test("stopped threshold is explicit and cannot be malformed")
    func thresholdValidation() throws {
        #expect(throws: StoppedOnlyControlPolicyError.invalidStoppedThreshold) {
            try StoppedOnlyControlPolicy(stoppedThresholdKilometersPerHour: 0)
        }
        #expect(throws: StoppedOnlyControlPolicyError.invalidStoppedThreshold) {
            try StoppedOnlyControlPolicy(stoppedThresholdKilometersPerHour: -0.1)
        }
        #expect(throws: StoppedOnlyControlPolicyError.invalidStoppedThreshold) {
            try StoppedOnlyControlPolicy(stoppedThresholdKilometersPerHour: .infinity)
        }
        #expect(throws: StoppedOnlyControlPolicyError.invalidStoppedThreshold) {
            try StoppedOnlyControlPolicy(stoppedThresholdKilometersPerHour: .nan)
        }

        let custom = try StoppedOnlyControlPolicy(
            stoppedThresholdKilometersPerHour: 1.25
        )
        #expect(custom.stoppedThresholdKilometersPerHour == 1.25)
    }

    @Test("retained moving value remains stale rather than becoming current motion truth")
    func retainedMovingValueDoesNotClaimCurrentMotion() {
        let state = policy.motionState(
            connection: .connected,
            speedEvidence: .retained(kilometersPerHour: 18)
        )

        #expect(state == .notProvenStopped(.speedRetained))
        #expect(!state.permitsStoppedOnlyControls)
    }
}
