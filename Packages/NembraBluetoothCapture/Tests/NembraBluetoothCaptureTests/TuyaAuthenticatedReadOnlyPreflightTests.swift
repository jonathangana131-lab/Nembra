import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated read-only preflight")
struct TuyaAuthenticatedReadOnlyPreflightTests {
    private let stableAt: UInt64 = 100_000_000_000

    @Test("missing connection generation fails closed")
    func missingConnectionGenerationBlocks() {
        let verdict = TuyaAuthenticatedReadOnlyPreflight.verdict(
            for: snapshot(
                state: .authenticated,
                generation: 0,
                authenticatedAt: stableAt,
                latest: stableAt + 45_000_000_000,
                payloads: 1
            )
        )
        #expect(verdict == .blocked(reason: "No current Bluetooth connection generation."))
    }

    @Test("unavailable and failed authentication reasons pass through")
    func unavailableAndFailedReasonsPassThrough() {
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(
                for: snapshot(state: .unavailable(reason: "SDK unavailable"))
            ) == .blocked(reason: "SDK unavailable")
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(
                for: snapshot(state: .failed(reason: "Authentication rejected"))
            ) == .blocked(reason: "Authentication rejected")
        )
    }

    @Test("in-progress authentication states fail closed")
    func inProgressAuthenticationStatesBlock() {
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(
                for: snapshot(state: .waitingForAuthentication)
            ) == .blocked(reason: "Tuya authentication required.")
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(
                for: snapshot(state: .authenticating)
            ) == .blocked(reason: "Tuya authentication is still in progress.")
        )
    }

    @Test("authenticated session requires a real application payload")
    func payloadRequired() {
        let verdict = TuyaAuthenticatedReadOnlyPreflight.verdict(
            for: snapshot(
                state: .authenticated,
                authenticatedAt: stableAt,
                latest: stableAt + 60_000_000_000,
                payloads: 0
            )
        )
        #expect(verdict == .blocked(reason: "Authenticated session has not produced an application payload yet."))
    }

    @Test("negative payload count is clamped and cannot unlock gate")
    func negativePayloadCountFailsClosed() {
        let value = snapshot(
            state: .authenticated,
            authenticatedAt: stableAt,
            latest: stableAt + 60_000_000_000,
            payloads: -5
        )
        #expect(value.applicationPayloadCount == 0)
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(for: value)
                == .blocked(reason: "Authenticated session has not produced an application payload yet.")
        )
    }

    @Test("missing or regressed monotonic time fails closed")
    func invalidDurationEvidenceBlocks() {
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(
                for: snapshot(
                    state: .authenticated,
                    authenticatedAt: nil,
                    latest: stableAt + 60_000_000_000,
                    payloads: 1
                )
            ) == .blocked(reason: "Authenticated connection duration is unavailable.")
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(
                for: snapshot(
                    state: .authenticated,
                    authenticatedAt: stableAt,
                    latest: nil,
                    payloads: 1
                )
            ) == .blocked(reason: "Authenticated connection duration is unavailable.")
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(
                for: snapshot(
                    state: .authenticated,
                    authenticatedAt: stableAt,
                    latest: stableAt - 1,
                    payloads: 1
                )
            ) == .blocked(reason: "Authenticated connection duration is unavailable.")
        )
    }

    @Test("one nanosecond below stability boundary stays blocked")
    func justBelowDurationRequired() {
        let verdict = TuyaAuthenticatedReadOnlyPreflight.verdict(
            for: snapshot(
                state: .authenticated,
                authenticatedAt: stableAt,
                latest: stableAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds - 1,
                payloads: 1
            )
        )
        #expect(verdict == .blocked(reason: "Authenticated connection has not survived the physical stability window yet."))
    }

    @Test("authenticated payload at exact 45 second boundary unlocks stationary mapping")
    func exactPhysicalGateBoundary() {
        let verdict = TuyaAuthenticatedReadOnlyPreflight.verdict(
            for: snapshot(
                state: .authenticated,
                authenticatedAt: stableAt,
                latest: stableAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds,
                payloads: 1
            )
        )
        #expect(verdict == .readyForStationaryMapping)
    }

    @Test("authenticated payload beyond stability boundary remains ready")
    func beyondPhysicalGateBoundary() {
        let verdict = TuyaAuthenticatedReadOnlyPreflight.verdict(
            for: snapshot(
                state: .authenticated,
                authenticatedAt: stableAt,
                latest: stableAt + 60_000_000_000,
                payloads: 3
            )
        )
        #expect(verdict == .readyForStationaryMapping)
    }

    private func snapshot(
        state: TuyaAuthenticatedReadOnlyPreflightSnapshot.AuthenticationState,
        generation: UInt64 = 1,
        authenticatedAt: UInt64? = nil,
        latest: UInt64? = nil,
        payloads: Int = 0
    ) -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: state,
            connectionStartedAtUptimeNanoseconds: stableAt - 10_000_000_000,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: latest,
            applicationPayloadCount: payloads,
            connectionGeneration: generation
        )
    }
}
