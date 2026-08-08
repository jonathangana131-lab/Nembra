import Testing

@testable import NembraCore

@Suite("Vehicle command user feedback correlation")
@MainActor
struct VehicleCommandUserFeedbackCorrelationTests {
    @Test("confirmed outcome is emitted once only for exact local request")
    func confirmedExactRequest() throws {
        let gate = VehicleCommandUserFeedbackCorrelation()
        let request = try gate.beginUserRequest()

        #expect(gate.hasPendingUserRequest)
        #expect(try gate.resolve(request, as: .confirmed) == .confirmed)
        #expect(!gate.hasPendingUserRequest)
        #expect(throws: VehicleCommandUserFeedbackCorrelationError.noPendingRequest) {
            _ = try gate.resolve(request, as: .confirmed)
        }
    }

    @Test("failed outcome remains correlated to exact user request")
    func failedExactRequest() throws {
        let gate = VehicleCommandUserFeedbackCorrelation()
        let request = try gate.beginUserRequest()

        #expect(try gate.resolve(request, as: .failed) == .failed)
        #expect(!gate.hasPendingUserRequest)
    }

    @Test("second local request cannot overwrite unresolved provenance")
    func duplicateBeginFailsClosed() throws {
        let gate = VehicleCommandUserFeedbackCorrelation()
        let first = try gate.beginUserRequest()

        #expect(throws: VehicleCommandUserFeedbackCorrelationError.requestAlreadyPending) {
            _ = try gate.beginUserRequest()
        }
        #expect(try gate.resolve(first, as: .confirmed) == .confirmed)
    }

    @Test("foreign coordinator token cannot satisfy current request")
    func foreignTokenFailsClosed() throws {
        let gate = VehicleCommandUserFeedbackCorrelation()
        let foreignGate = VehicleCommandUserFeedbackCorrelation()
        let current = try gate.beginUserRequest()
        let foreign = try foreignGate.beginUserRequest()

        #expect(current != foreign)
        #expect(throws: VehicleCommandUserFeedbackCorrelationError.requestDoesNotMatch) {
            _ = try gate.resolve(foreign, as: .confirmed)
        }
        #expect(gate.hasPendingUserRequest)
        #expect(try gate.resolve(current, as: .confirmed) == .confirmed)
    }

    @Test("stale prior request cannot resolve a newer local request")
    func staleTokenFailsClosed() throws {
        let gate = VehicleCommandUserFeedbackCorrelation()
        let first = try gate.beginUserRequest()
        _ = try gate.resolve(first, as: .failed)
        let second = try gate.beginUserRequest()

        #expect(second != first)
        #expect(throws: VehicleCommandUserFeedbackCorrelationError.requestDoesNotMatch) {
            _ = try gate.resolve(first, as: .confirmed)
        }
        #expect(gate.hasPendingUserRequest)
        #expect(try gate.resolve(second, as: .confirmed) == .confirmed)
    }

    @Test("abandon clears exact request without manufacturing outcome")
    func abandonExactRequest() throws {
        let gate = VehicleCommandUserFeedbackCorrelation()
        let request = try gate.beginUserRequest()

        try gate.abandon(request)
        #expect(!gate.hasPendingUserRequest)
        #expect(throws: VehicleCommandUserFeedbackCorrelationError.noPendingRequest) {
            _ = try gate.resolve(request, as: .confirmed)
        }
    }

    @Test("mismatched abandon leaves current request intact")
    func mismatchedAbandonPreservesPending() throws {
        let gate = VehicleCommandUserFeedbackCorrelation()
        let other = VehicleCommandUserFeedbackCorrelation()
        let current = try gate.beginUserRequest()
        let foreign = try other.beginUserRequest()

        #expect(throws: VehicleCommandUserFeedbackCorrelationError.requestDoesNotMatch) {
            try gate.abandon(foreign)
        }
        #expect(gate.hasPendingUserRequest)
        #expect(try gate.resolve(current, as: .confirmed) == .confirmed)
    }
}
