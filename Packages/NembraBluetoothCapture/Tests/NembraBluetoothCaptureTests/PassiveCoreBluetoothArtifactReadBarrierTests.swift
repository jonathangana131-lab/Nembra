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
    func queuePolicyExcludesPostCutEventUntilArtifactReadEndsThenDrainsItExactlyOnce() throws {
        var barrier = PassiveCoreBluetoothArtifactReadBarrier()
        var pending = [10]
        var recorded: [Int] = []

        try barrier.begin(through: 10)
        let firstPending = try #require(pending.first)
        let firstTail = try #require(pending.last)
        let firstUpperBound = try #require(
            barrier.permittedDrainUpperBound(
                firstPending: UInt64(firstPending),
                pendingTail: UInt64(firstTail)
            )
        )
        recorded.append(contentsOf: pending.filter { UInt64($0) <= firstUpperBound })
        pending.removeAll { UInt64($0) <= firstUpperBound }

        // N+1 arrives after the immutable artifact cut while the read is active.
        pending.append(11)
        #expect(
            barrier.permittedDrainUpperBound(
                firstPending: 11,
                pendingTail: 11
            ) == nil
        )
        #expect(recorded == [10])
        #expect(pending == [11])

        barrier.end()
        let resumedPending = try #require(pending.first)
        let resumedTail = try #require(pending.last)
        let resumedUpperBound = try #require(
            barrier.permittedDrainUpperBound(
                firstPending: UInt64(resumedPending),
                pendingTail: UInt64(resumedTail)
            )
        )
        recorded.append(contentsOf: pending.filter { UInt64($0) <= resumedUpperBound })
        pending.removeAll { UInt64($0) <= resumedUpperBound }

        #expect(recorded == [10, 11])
        #expect(pending.isEmpty)
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
        #expect(barrier.permittedDrainUpperBound(firstPending: 1, pendingTail: 1) == nil)
    }

    @Test
    func barrierNeverExtendsDrainPastPendingTail() throws {
        var barrier = PassiveCoreBluetoothArtifactReadBarrier()

        try barrier.begin(through: 50)
        #expect(barrier.drainUpperBound(pendingTail: 12) == 12)
        #expect(barrier.permittedDrainUpperBound(firstPending: 10, pendingTail: 12) == 12)
    }
}
