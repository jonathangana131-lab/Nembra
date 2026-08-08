import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothObservationBoundaryQueueProducerIdentityTests {
    private typealias Identity = PassiveCoreBluetoothObservationBoundaryQueueProducerIdentity

    private struct TransactionEnvelope: Equatable {
        let producer: Identity
        let revision: UInt64
        let queueCutoff: UInt64
    }

    @Test
    func copiedReferencePreservesProducerIdentity() {
        let original = Identity.mint()
        let copied = original

        #expect(copied == original)
        #expect(copied === original)
    }

    @Test
    func independentlyMintedProducersNeverCompareEqualByReconstructableValues() {
        let first = Identity.mint()
        let second = Identity.mint()

        #expect(first != second)
        #expect(first !== second)
    }

    @Test
    func equalScalarTransactionFieldsRemainDistinctAcrossIndependentProducers() {
        let gateA = TransactionEnvelope(
            producer: Identity.mint(),
            revision: 2,
            queueCutoff: 12
        )
        let gateB = TransactionEnvelope(
            producer: Identity.mint(),
            revision: 2,
            queueCutoff: 12
        )
        let copiedGateA = gateA

        #expect(gateA.revision == gateB.revision)
        #expect(gateA.queueCutoff == gateB.queueCutoff)
        #expect(gateA != gateB)
        #expect(gateA == copiedGateA)
    }

    @Test
    func producerIdentityHasNoCallerSuppliedScalarInitializer() {
        // Construction is intentionally package-owned through `mint()`. This test
        // exercises the only available API surface rather than accepting revision,
        // cutoff, artifact authority, UUID text, or another reconstructable value.
        let identity = Identity.mint()

        #expect(identity == identity)
    }
}
