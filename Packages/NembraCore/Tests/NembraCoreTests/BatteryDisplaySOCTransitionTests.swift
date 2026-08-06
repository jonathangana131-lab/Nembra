import Testing
@testable import NembraCore

@Suite("Battery display SoC transition")
struct BatteryDisplaySOCTransitionTests {
    @Test("descending jump traverses each integer without fabricating endpoint provenance")
    func descendingJump() {
        let transition = BatteryDisplaySOCTransitionPlanner.plan(from: 84, to: 80)

        #expect(
            transition == .animate([
                BatteryDisplaySOCFrame(percent: 83, role: .presentationIntermediate),
                BatteryDisplaySOCFrame(percent: 82, role: .presentationIntermediate),
                BatteryDisplaySOCFrame(percent: 81, role: .presentationIntermediate),
                BatteryDisplaySOCFrame(percent: 80, role: .targetDisplayValue),
            ])
        )
    }

    @Test("ascending correction traverses each integer")
    func ascendingCorrection() {
        let transition = BatteryDisplaySOCTransitionPlanner.plan(from: 80, to: 84)

        #expect(
            transition == .animate([
                BatteryDisplaySOCFrame(percent: 81, role: .presentationIntermediate),
                BatteryDisplaySOCFrame(percent: 82, role: .presentationIntermediate),
                BatteryDisplaySOCFrame(percent: 83, role: .presentationIntermediate),
                BatteryDisplaySOCFrame(percent: 84, role: .targetDisplayValue),
            ])
        )
    }

    @Test("one point movement contains only the caller supplied target")
    func onePointMovement() {
        #expect(
            BatteryDisplaySOCTransitionPlanner.plan(from: 73, to: 72) == .animate([
                BatteryDisplaySOCFrame(percent: 72, role: .targetDisplayValue)
            ])
        )
    }

    @Test("same display value snaps instead of manufacturing animation")
    func unchangedValue() {
        #expect(BatteryDisplaySOCTransitionPlanner.plan(from: 73, to: 73) == .snap(73))
    }

    @Test("unknown or invalid current display snaps to a legitimate target")
    func invalidCurrentDisplay() {
        #expect(BatteryDisplaySOCTransitionPlanner.plan(from: nil, to: 73) == .snap(73))
        #expect(BatteryDisplaySOCTransitionPlanner.plan(from: -1, to: 73) == .snap(73))
        #expect(BatteryDisplaySOCTransitionPlanner.plan(from: 101, to: 73) == .snap(73))
    }

    @Test("unknown or invalid target clears rather than animating toward fake zero")
    func invalidTargetClears() {
        #expect(BatteryDisplaySOCTransitionPlanner.plan(from: 73, to: nil) == .clear)
        #expect(BatteryDisplaySOCTransitionPlanner.plan(from: 73, to: -1) == .clear)
        #expect(BatteryDisplaySOCTransitionPlanner.plan(from: 73, to: 101) == .clear)
    }

    @Test("zero and full scale endpoints remain valid")
    func boundaries() {
        let descending = BatteryDisplaySOCTransitionPlanner.plan(from: 1, to: 0)
        let ascending = BatteryDisplaySOCTransitionPlanner.plan(from: 99, to: 100)

        #expect(descending == .animate([BatteryDisplaySOCFrame(percent: 0, role: .targetDisplayValue)]))
        #expect(ascending == .animate([BatteryDisplaySOCFrame(percent: 100, role: .targetDisplayValue)]))
    }

    @Test("full scale correction remains bounded to the normalized percentage domain")
    func fullScaleCorrectionIsBounded() {
        let transition = BatteryDisplaySOCTransitionPlanner.plan(from: 100, to: 0)
        guard case let .animate(frames) = transition else {
            Issue.record("Expected an animated full-scale correction")
            return
        }

        #expect(frames.count == 100)
        #expect(frames.first == BatteryDisplaySOCFrame(percent: 99, role: .presentationIntermediate))
        #expect(frames.last == BatteryDisplaySOCFrame(percent: 0, role: .targetDisplayValue))
        #expect(frames.dropLast().allSatisfy { $0.role == .presentationIntermediate })
    }

    @Test("interrupted animation can restart from the currently rendered integer")
    func interruptionRestart() {
        let replacement = BatteryDisplaySOCTransitionPlanner.plan(from: 82, to: 85)

        #expect(
            replacement == .animate([
                BatteryDisplaySOCFrame(percent: 83, role: .presentationIntermediate),
                BatteryDisplaySOCFrame(percent: 84, role: .presentationIntermediate),
                BatteryDisplaySOCFrame(percent: 85, role: .targetDisplayValue),
            ])
        )
    }

    @Test("every valid endpoint pair stays bounded, sequential, and target-terminated")
    func exhaustiveValidEndpointInvariant() {
        for current in 0...100 {
            for target in 0...100 where target != current {
                let transition = BatteryDisplaySOCTransitionPlanner.plan(from: current, to: target)
                guard case let .animate(frames) = transition else {
                    Issue.record("Every changed valid endpoint pair must animate")
                    continue
                }

                let direction = target > current ? 1 : -1
                let expectedPercents = Array(stride(
                    from: current + direction,
                    through: target,
                    by: direction
                ))

                #expect(
                    frames.map(\.percent) == expectedPercents &&
                    frames.allSatisfy { (0...100).contains($0.percent) } &&
                    frames.dropLast().allSatisfy { $0.role == .presentationIntermediate } &&
                    frames.last?.role == .targetDisplayValue
                )
            }
        }
    }
}
