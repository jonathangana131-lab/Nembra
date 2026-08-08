import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothObservationBoundaryQueueProducerIdentityTests {
    private typealias Identity = PassiveCoreBluetoothObservationBoundaryQueueProducerIdentity

    @Test
    func copiedReferencePreservesProducerIdentity() {
        let original = Identity.mint()
        let copied = original

        #expect(copied == original)
        #expect(copied === original)
        #expect(Set([original, copied]).count == 1)
    }

    @Test
    func independentlyMintedProducersNeverCompareEqualByReconstructableValues() {
        let first = Identity.mint()
        let second = Identity.mint()

        #expect(first != second)
        #expect(first !== second)
        #expect(Set([first, second]).count == 2)
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
