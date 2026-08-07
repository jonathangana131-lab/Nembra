import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothArtifactReadBarrierTests {
    @Test
    func activeBarrierClampsDrainToFrozenWatermarkAndLaterEventsResumeAfterEnd() throws {
        var barrier = PassiveCoreBluetoothArtifactReadBarrier()

        try barrier.begin(through: 10)
        #expect(barrier.isActive)
        #expect(barrier.watermark == 10)
        #expect(barrier.drainUpperBound(pendingTail: 10) == 10)
        #expect(barrier.drainUpperBound(pendingTail: 14) == 10)

        barrier.end()
        #expect(!barrier.isActive)
        #expect(barrier.watermark == nil)
        #expect(barrier.drainUpperBound(pendingTail: 14) == 14)
    }

    @Test
    func overlappingArtifactReadFailsClosedWithoutMovingFirstWatermark() throws {
        var barrier = PassiveCoreBluetoothArtifactReadBarrier()
        try barrier.begin(through: 7)

        #expect(throws: PassiveCoreBluetoothArtifactReadBarrier.StateError.alreadyActive) {
            try barrier.begin(through: 9)
        }
        #expect(barrier.isActive)
        #expect(barrier.watermark == 7)
        #expect(barrier.drainUpperBound(pendingTail: 12) == 7)
    }

    @Test
    func zeroWatermarkStillFormsAnActiveBarrier() throws {
        var barrier = PassiveCoreBluetoothArtifactReadBarrier()

        try barrier.begin(through: 0)
        #expect(barrier.isActive)
        #expect(barrier.watermark == 0)
        #expect(barrier.drainUpperBound(pendingTail: 1) == 0)
    }

    @Test
    func barrierNeverExtendsDrainPastPendingTail() throws {
        var barrier = PassiveCoreBluetoothArtifactReadBarrier()

        try barrier.begin(through: 50)
        #expect(barrier.drainUpperBound(pendingTail: 12) == 12)
    }
}
