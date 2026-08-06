import Foundation
import Testing
@testable import NembraCore

@Suite("Battery primary readout state")
struct BatteryPrimaryReadoutStateTests {
    private let availableInputs = BatteryPrimaryReadoutInputs(
        displaySOCPercent: 73,
        estimatedRange: .valueMiles(8.4)
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
        #expect(state.presentation(for: availableInputs).primaryValue == .estimatedRangeMiles(8.4))

        state.toggle()
        #expect(state.mode == .percentage)
        #expect(state.presentation(for: availableInputs).primaryValue == .percentage(73))
    }

    @Test("battery fill remains charge-oriented while the number shows range")
    func fillRemainsVisibleInRangeMode() {
        let state = BatteryPrimaryReadoutState(mode: .estimatedRange)
        let presentation = state.presentation(for: availableInputs)

        #expect(presentation.primaryValue == .estimatedRangeMiles(8.4))
        #expect(presentation.batteryFillPercent == 73)
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
                estimatedRange: .valueMiles(-1)
            )
        )
        let infinite = state.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: 50,
                estimatedRange: .valueMiles(.infinity)
            )
        )
        let nan = state.presentation(
            for: BatteryPrimaryReadoutInputs(
                displaySOCPercent: 50,
                estimatedRange: .valueMiles(.nan)
            )
        )

        #expect(negative.primaryValue == .unavailable)
        #expect(infinite.primaryValue == .unavailable)
        #expect(nan.primaryValue == .unavailable)
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
                estimatedRange: .valueMiles(9.1)
            )
        )

        #expect(state.mode == .estimatedRange)
        #expect(unavailable.primaryValue == .unavailable)
        #expect(laterAvailable.primaryValue == .estimatedRangeMiles(9.1))
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
