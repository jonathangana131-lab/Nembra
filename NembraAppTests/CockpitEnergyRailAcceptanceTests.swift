import CoreGraphics
import Dispatch
import XCTest
@testable import Nembra

final class CockpitEnergyRailAcceptanceTests: XCTestCase {
    func testPowerRailGeometryIsShallowSymmetricMonotonicAndFullyBounded() {
        for size in [
            CGSize(width: 640, height: 82),
            CGSize(width: 720, height: 92),
            CGSize(width: 896, height: 104)
        ] {
            let geometry = DashboardPropulsionGeometry(size: size)
            let apex = geometry.point(at: 0.5)

            XCTAssertEqual(geometry.start.y, geometry.end.y, accuracy: 0.001)
            XCTAssertEqual(apex.x, size.width / 2, accuracy: 0.001)
            XCTAssertGreaterThan(geometry.start.y - apex.y, 0)
            XCTAssertLessThanOrEqual(geometry.start.y - apex.y, 10.001)
            XCTAssertEqual(geometry.point(at: 0), geometry.start)
            XCTAssertEqual(geometry.point(at: 1), geometry.end)

            var previousX = -CGFloat.infinity
            for index in 0...64 {
                let progress = Double(index) / 64
                let mirror = geometry.point(at: 1 - progress)
                let point = geometry.point(at: progress)
                XCTAssertEqual(point.x + mirror.x, size.width, accuracy: 0.001)
                XCTAssertEqual(point.y, mirror.y, accuracy: 0.001)
                XCTAssertGreaterThan(point.x, previousX)
                previousX = point.x

                let normal = geometry.outwardNormal(at: progress)
                let locatorEdge = CGPoint(
                    x: point.x + normal.dx * 8,
                    y: point.y + normal.dy * 8
                )
                XCTAssertGreaterThanOrEqual(locatorEdge.x, 0)
                XCTAssertLessThanOrEqual(locatorEdge.x, size.width)
                XCTAssertGreaterThanOrEqual(locatorEdge.y, 0)
                XCTAssertLessThanOrEqual(locatorEdge.y, size.height)
            }
        }
    }

    func testPowerSemanticsKeepAcceptedNowSeparateFromIlluminationAndPeak() {
        let state = DashboardEnergyRailVisualState(
            currentness: .live,
            acceptedWatts: 500,
            acceptedCurrentFraction: 0.77,
            illuminatedFraction: 0.43,
            acceptedPeakFraction: 0.92,
            scaleOrigin: .simulator,
            scaleCeilingWatts: 650
        )
        let semantics = DashboardPowerInstrumentSemantics(state: state, isSimulatorQA: true)

        XCTAssertEqual(state.acceptedCurrentFraction, 0.77)
        XCTAssertEqual(state.illuminatedFraction, 0.43)
        XCTAssertEqual(state.acceptedPeakFraction, 0.92)
        XCTAssertEqual(semantics.scaleText, "QA SCALE · 650 W")
        XCTAssertTrue(semantics.accessibilityValue.contains("NOW, 500 accepted watts"))
        XCTAssertTrue(semantics.accessibilityValue.contains("positioned from zero toward positive propulsion"))
        XCTAssertTrue(semantics.accessibilityValue.contains("hollow marker"))

        for rejectedClaim in ["throttle", "regen", "rated", "motor capacity", "negative", "-18", "kW"] {
            XCTAssertFalse(semantics.accessibilityValue.localizedCaseInsensitiveContains(rejectedClaim))
            XCTAssertFalse(semantics.scaleText?.localizedCaseInsensitiveContains(rejectedClaim) == true)
        }
    }

    func testPowerSemanticsMentionPeakOnlyWhenMarkerIsRendered() {
        let nearCurrent = DashboardEnergyRailVisualState(
            currentness: .live,
            acceptedWatts: 500,
            acceptedCurrentFraction: 0.77,
            illuminatedFraction: 0.70,
            acceptedPeakFraction: 0.78,
            scaleOrigin: .simulator,
            scaleCeilingWatts: 650
        )
        let distinctPeak = DashboardEnergyRailVisualState(
            currentness: .live,
            acceptedWatts: 500,
            acceptedCurrentFraction: 0.77,
            illuminatedFraction: 0.70,
            acceptedPeakFraction: 0.92,
            scaleOrigin: .simulator,
            scaleCeilingWatts: 650
        )

        XCTAssertNil(DashboardPowerPeakMarkerPolicy.visiblePeakFraction(
            current: nearCurrent.acceptedCurrentFraction,
            peak: nearCurrent.acceptedPeakFraction
        ))
        XCTAssertFalse(
            DashboardPowerInstrumentSemantics(state: nearCurrent, isSimulatorQA: true)
                .accessibilityValue.localizedCaseInsensitiveContains("peak")
        )
        XCTAssertEqual(DashboardPowerPeakMarkerPolicy.visiblePeakFraction(
            current: distinctPeak.acceptedCurrentFraction,
            peak: distinctPeak.acceptedPeakFraction
        ), 0.92)
        XCTAssertNil(
            DashboardPowerPeakMarkerPolicy.visiblePeakFraction(current: 0.77, peak: 0.40),
            "A lower historical sample cannot be presented as a peak ahead of NOW."
        )
        XCTAssertTrue(
            DashboardPowerInstrumentSemantics(state: distinctPeak, isSimulatorQA: true)
                .accessibilityValue.localizedCaseInsensitiveContains("hollow marker")
        )
    }

    func testRetainedAndUnavailablePowerNeverInventLiveGeometryOrZero() {
        let retained = DashboardEnergyRailVisualState(
            currentness: .retained,
            acceptedWatts: 280,
            acceptedCurrentFraction: nil,
            illuminatedFraction: nil,
            acceptedPeakFraction: nil,
            scaleOrigin: nil,
            scaleCeilingWatts: nil
        )
        let unavailable = DashboardEnergyRailVisualState.unavailable

        XCTAssertNil(retained.acceptedCurrentFraction)
        XCTAssertNil(retained.illuminatedFraction)
        XCTAssertNil(retained.acceptedPeakFraction)
        XCTAssertTrue(
            DashboardPowerInstrumentSemantics(state: retained, isSimulatorQA: false)
                .accessibilityValue.contains("Last known")
        )
        XCTAssertNil(unavailable.acceptedWatts)
        XCTAssertNil(unavailable.acceptedCurrentFraction)
        XCTAssertTrue(
            DashboardPowerInstrumentSemantics(state: unavailable, isSimulatorQA: false)
                .accessibilityValue.contains("No zero value")
        )
    }

    func testPowerPresentationFailsClosedForMalformedOrUnrenderableStates() {
        let malformedStates = [
            DashboardEnergyRailVisualState(
                currentness: .live,
                acceptedWatts: .greatestFiniteMagnitude,
                acceptedCurrentFraction: 0.5,
                illuminatedFraction: 0.5,
                acceptedPeakFraction: nil,
                scaleOrigin: .simulator,
                scaleCeilingWatts: 650
            ),
            DashboardEnergyRailVisualState(
                currentness: .live,
                acceptedWatts: 320,
                acceptedCurrentFraction: .nan,
                illuminatedFraction: 0.5,
                acceptedPeakFraction: nil,
                scaleOrigin: .simulator,
                scaleCeilingWatts: 650
            ),
            DashboardEnergyRailVisualState(
                currentness: .live,
                acceptedWatts: 320,
                acceptedCurrentFraction: 0.5,
                illuminatedFraction: .infinity,
                acceptedPeakFraction: nil,
                scaleOrigin: .simulator,
                scaleCeilingWatts: 650
            ),
            DashboardEnergyRailVisualState(
                currentness: .retained,
                acceptedWatts: 280,
                acceptedCurrentFraction: 0.4,
                illuminatedFraction: nil,
                acceptedPeakFraction: nil,
                scaleOrigin: nil,
                scaleCeilingWatts: nil
            )
        ]

        for malformed in malformedStates {
            XCTAssertEqual(malformed.validatedForPresentation, .unavailable)
            XCTAssertTrue(
                DashboardPowerInstrumentSemantics(state: malformed, isSimulatorQA: false)
                    .accessibilityValue.contains("unavailable")
            )
        }
    }

#if targetEnvironment(simulator)
    @MainActor
    func testPowerModelBindsNowToExactSourceReceiptWhileIlluminationSettles() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let store = VehicleStore(
            service: service,
            initialState: await service.snapshot(),
            shouldAutoConnectOnStart: false,
            speedInstrumentInterpolationPolicy: .simulatorQA
        )
        await store.start()

        let initialProjectionArrived = await waitUntil {
            store.simulatorPowerStoreProjection.currentness == .live
        }
        XCTAssertTrue(initialProjectionArrived)
        let initialProjection = store.simulatorPowerStoreProjection
        let initialReceipt = try XCTUnwrap(initialProjection.observation)

        let model = DashboardEnergyRailModel()
        model.synchronize(initialProjection, sourceCapabilityIsOwned: true)
        let initial = model.presentation(
            atUptimeNanoseconds: initialReceipt.receivedAtUptimeNanoseconds,
            prefersReducedMotion: false
        )
        XCTAssertEqual(initial.currentness, .live)
        XCTAssertEqual(initial.acceptedWatts, initialReceipt.watts)

        await service.simulateRide(speedKilometersPerHour: 36, elapsedSeconds: 0)
        let advancedReceiptArrived = await waitUntil {
            guard let observation = store.simulatorPowerStoreProjection.observation else { return false }
            return observation.receiptSequenceNumber > initialReceipt.receiptSequenceNumber
        }
        XCTAssertTrue(advancedReceiptArrived)

        let advancedProjection = store.simulatorPowerStoreProjection
        let advancedReceipt = try XCTUnwrap(advancedProjection.observation)
        model.synchronize(advancedProjection, sourceCapabilityIsOwned: true)
        let rising = model.presentation(
            atUptimeNanoseconds: advancedReceipt.receivedAtUptimeNanoseconds,
            prefersReducedMotion: false
        )

        XCTAssertEqual(rising.currentness, .live)
        XCTAssertEqual(rising.acceptedWatts, advancedReceipt.watts)
        XCTAssertEqual(
            rising.acceptedCurrentFraction ?? -1,
            advancedReceipt.watts / 650,
            accuracy: 0.000_1
        )
        let illuminatedFraction = try XCTUnwrap(rising.illuminatedFraction)
        let acceptedCurrentFraction = try XCTUnwrap(rising.acceptedCurrentFraction)
        XCTAssertNotEqual(
            illuminatedFraction,
            acceptedCurrentFraction,
            "Render-only illumination may settle, but NOW must move to the newly accepted receipt immediately."
        )
        XCTAssertTrue(model.shouldTick)

        let reducedMotion = model.presentation(
            atUptimeNanoseconds: advancedReceipt.receivedAtUptimeNanoseconds,
            prefersReducedMotion: true
        )
        XCTAssertEqual(reducedMotion.illuminatedFraction, reducedMotion.acceptedCurrentFraction)

        let renderWindowRetired = await waitUntil { !model.shouldTick }
        XCTAssertTrue(renderWindowRetired, "Accepted power settling must retire its Timeline window.")

        await service.disconnect()
        let retainedProjectionArrived = await waitUntil {
            store.simulatorPowerStoreProjection.currentness == .retained
        }
        XCTAssertTrue(retainedProjectionArrived)
        model.synchronize(store.simulatorPowerStoreProjection, sourceCapabilityIsOwned: true)
        let retained = model.presentation(
            atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            prefersReducedMotion: false
        )
        XCTAssertEqual(retained.currentness, .retained)
        XCTAssertEqual(retained.acceptedWatts, advancedReceipt.watts)
        XCTAssertNil(retained.acceptedCurrentFraction)
        XCTAssertNil(retained.illuminatedFraction)
        XCTAssertNil(retained.acceptedPeakFraction)
        XCTAssertFalse(model.shouldTick)

        model.synchronize(.unavailable, sourceCapabilityIsOwned: true)
        XCTAssertEqual(
            model.presentation(
                atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                prefersReducedMotion: false
            ),
            .unavailable
        )
        model.stop()
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return condition()
    }
#endif
}
