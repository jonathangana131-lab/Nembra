import Foundation
import Testing
@testable import NembraCore

@Suite("Battery primary readout state")
struct BatteryPrimaryReadoutStateTests {
    private let availableInputs = BatteryPrimaryReadoutInputs(
        displaySOCPercent: 73,
        estimatedRange: .valueMeters(13_518.5)
    )

    @Test("percentage is the default primary representation")
    func defaultsToPercentage() {
        let state = BatteryPrimaryReadoutState()
        let presentation = state.presentation(for: availableInputs)

        #expect(state.mode == .percentage)
        #expect(presentation.primaryValue == .percentage(73))
        #expect(presentation.batteryFillPercent == 73)
    }

    @Test("normal tap toggles percentage to estimated range and back")
    func normalTapTogglesRepresentation() {
        var state = BatteryPrimaryReadoutState()

        state.toggle()
        #expect(state.mode == .estimatedRange)
        #expect(state.presentation(for: availableInputs).primaryValue == .estimatedRangeMeters(13_518.5))

        state.toggle()
        #expect(state.mode == .percentage)
        #expect(state.presentation(for: availableInputs).primaryValue == .percentage(73))
    }

    @Test("battery fill remains charge-oriented while the number shows range")
    func fillRemainsVisibleInRangeMode() {
        let state = BatteryPrimaryReadoutState(mode: .estimatedRange)
        let presentation = state.presentation(for: availableInputs)

        #expect(presentation.primaryValue == .estimatedRangeMeters(13_518.5))
        #expect(presentation.batteryFillPercent == 73)
    }

    @Test("range remains unit-neutral for formatting above the core domain")
    func rangeRemainsUnitNeutral() {
        let state = BatteryPrimaryReadoutState(mode: .estimatedRange)
        let presentation = state.presentation(for: availableInputs)

        #expect(presentation.primaryValue == .estimatedRangeMeters(13_518.5))
    }

    @Test("range mode never invents advertised-range math when estimate is unavailable")
    func unavailableRangeStaysUnavailable() {
        let state = BatteryPrimaryReadoutState(mode: .estimatedRange)
        let inputs = BatteryPrimaryReadoutInputs(
            displaySOCPercent: 90,
            estimatedRange: .unavailable
        )

        let presentation = state.presentation(for: inputs)
        #expect(presentation.primaryValue == .unavailable)
        #expect(presentation.batteryFillPercent == 90)
    }

    @Test("learning range is explicit instead of fake numeric precision")
    func learningRangeIsExplicit() {
        let state = BatteryPrimaryReadoutState(mode: .estimatedRange)
        let inputs = BatteryPrimaryReadoutInputs(
            displaySOCPercent: 64,
            estimatedRange: .learning
        )

        #expect(state.presentation(for: inputs).primaryValue == .learningRange)
    }

    @Test("invalid display SoC is rejected rather than clamped")
    func invalidDisplaySOCIsRejected() {
        let state = BatteryPrimaryReadoutState()

        let overFull = state.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: 104,
                estimatedRange: .unavailable
            )
        )
        let negative = state.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: -2,
                estimatedRange: .unavailable
            )
        )

        #expect(overFull.primaryValue == .unavailable)
        #expect(overFull.batteryFillPercent == nil)
        #expect(negative.primaryValue == .unavailable)
        #expect(negative.batteryFillPercent == nil)
    }

    @Test("invalid numeric range is rejected instead of shown")
    func invalidEstimatedRangeIsRejected() {
        let state = BatteryPrimaryReadoutState(mode: .estimatedRange)

        let negative = state.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: 50,
                estimatedRange: .valueMeters(-1)
            )
        )
        let infinite = state.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: 50,
                estimatedRange: .valueMeters(.infinity)
            )
        )
        let nan = state.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: 50,
                estimatedRange: .valueMeters(.nan)
            )
        )

        #expect(negative.primaryValue == .unavailable)
        #expect(infinite.primaryValue == .unavailable)
        #expect(nan.primaryValue == .unavailable)
    }

    @Test("zero and full boundary values remain legitimate")
    func validBoundaryValuesArePreserved() {
        let percentageState = BatteryPrimaryReadoutState()
        let empty = percentageState.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: 0,
                estimatedRange: .unavailable
            )
        )
        let full = percentageState.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: 100,
                estimatedRange: .unavailable
            )
        )
        let rangeState = BatteryPrimaryReadoutState(mode: .estimatedRange)
        let noRemainingDistance = rangeState.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: 0,
                estimatedRange: .valueMeters(0)
            )
        )

        #expect(empty.primaryValue == .percentage(0))
        #expect(empty.batteryFillPercent == 0)
        #expect(full.primaryValue == .percentage(100))
        #expect(full.batteryFillPercent == 100)
        #expect(noRemainingDistance.primaryValue == .estimatedRangeMeters(0))
    }

    @Test("range preference can be selected before range evidence exists")
    func rangePreferenceSurvivesUnavailableEvidence() {
        var state = BatteryPrimaryReadoutState()
        state.toggle()

        let unavailable = state.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: 81,
                estimatedRange: .unavailable
            )
        )
        let laterAvailable = state.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: 80,
                estimatedRange: .valueMeters(14_645.0)
            )
        )

        #expect(state.mode == .estimatedRange)
        #expect(unavailable.primaryValue == .unavailable)
        #expect(laterAvailable.primaryValue == .estimatedRangeMeters(14_645.0))
    }

    @Test("readout preference is codable for shared persisted presentation state")
    func modeRoundTripsThroughCodable() throws {
        let original = BatteryPrimaryReadoutState(mode: .estimatedRange)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BatteryPrimaryReadoutState.self, from: data)

        #expect(decoded == original)
        #expect(decoded.mode == .estimatedRange)
    }

    @Test("presentation does not mutate readout state or evidence inputs")
    func presentationIsPure() {
        let state = BatteryPrimaryReadoutState(mode: .estimatedRange)
        let inputs = availableInputs

        _ = state.presentation(for: inputs)

        #expect(state.mode == .estimatedRange)
        #expect(inputs == availableInputs)
    }
}
