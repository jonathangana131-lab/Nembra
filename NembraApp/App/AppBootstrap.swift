import Dispatch
import Foundation
import NembraCore

// The app target still directly compiles selected NembraCore vehicle/ride sources while the
// package migration is incremental. Keep the Battery truth/persistence slice package-owned and
// expose only the exact missing names needed by the existing app source. This avoids copying or
// redefining Battery authority semantics inside the app module while leaving overlapping
// direct-compiled vehicle/speed declarations unqualified and local.
typealias RetainedBatterySnapshotStorage = NembraCore.RetainedBatterySnapshotStorage
typealias UserDefaultsRetainedBatterySnapshotStorage = NembraCore.UserDefaultsRetainedBatterySnapshotStorage
typealias BatteryObservationAuthority = NembraCore.BatteryObservationAuthority
typealias AuthoritativeBatteryObservation = NembraCore.AuthoritativeBatteryObservation

@MainActor
final class AppRuntime {
    let vehicleStore: VehicleStore
    let rideStore: RideApplicationStore
    let rideHistoryStore: RideHistoryPresentationStore
    let rideRouteStore: RideRoutePresentationStore
    let dailyRideStore: DailyRidePresentationStore
    let automaticCaptureReadiness: AutomaticCaptureReadinessStore

    private let simulatorService: SimulatedScooterService?
    private let simulationScenario: ScooterSimulationScenario?
    private let simulatorAutoCompletesRide: Bool
    private let simulatorStartsWithSpeedEvidenceGap: Bool
    private let simulatorDashboardRenderStressIsAuthorized: Bool
    private let simulatorRoutePointCount: Int
    private let simulatorRouteRecorder: RideRouteRecorder?
    private var didStart = false
    private var simulatorRideDriverTask: Task<Void, Never>?
    private var simulatorDashboardRenderStressTask: Task<Void, Never>?

    init(
        vehicleStore: VehicleStore,
        rideStore: RideApplicationStore,
        rideHistoryStore: RideHistoryPresentationStore,
        rideRouteStore: RideRoutePresentationStore,
        dailyRideStore: DailyRidePresentationStore,
        automaticCaptureReadiness: AutomaticCaptureReadinessStore,
        simulatorService: SimulatedScooterService?,
        simulationScenario: ScooterSimulationScenario?,
        simulatorAutoCompletesRide: Bool,
        simulatorStartsWithSpeedEvidenceGap: Bool,
        simulatorDashboardRenderStressIsAuthorized: Bool,
        simulatorRoutePointCount: Int,
        simulatorRouteRecorder: RideRouteRecorder?
    ) {
        self.vehicleStore = vehicleStore
        self.rideStore = rideStore
        self.rideHistoryStore = rideHistoryStore
        self.rideRouteStore = rideRouteStore
        self.dailyRideStore = dailyRideStore
        self.automaticCaptureReadiness = automaticCaptureReadiness
        self.simulatorService = simulatorService
        self.simulationScenario = simulationScenario
        self.simulatorAutoCompletesRide = simulatorAutoCompletesRide
        self.simulatorStartsWithSpeedEvidenceGap = simulatorStartsWithSpeedEvidenceGap
        self.simulatorDashboardRenderStressIsAuthorized = simulatorDashboardRenderStressIsAuthorized
        self.simulatorRoutePointCount = simulatorRoutePointCount
        self.simulatorRouteRecorder = simulatorRouteRecorder
    }

    deinit {
        simulatorRideDriverTask?.cancel()
        simulatorDashboardRenderStressTask?.cancel()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        automaticCaptureReadiness.refresh()

        // Ride evidence subscribes first so explicit QA telemetry emitted after
        // launch cannot race past the automatic ride application layer.
        await rideStore.start()
        await vehicleStore.start()

        // Explicit Simulator-only visual/runtime fixture. A connected-stopped
        // launch owns a valid synthetic speed sample; this opt-in then opens the
        // existing source-owned evidence-gap primitive while transport remains
        // connected. The app must therefore project `.retained` speed specifically,
        // without changing aggregate connection/data state or inventing a timeout.
        if simulatorStartsWithSpeedEvidenceGap,
           let simulatorService {
            await simulatorService.simulateSpeedEvidenceGap()
        }

        guard simulationScenario == .riding,
              let simulatorService else { return }

#if targetEnvironment(simulator)
        if simulatorDashboardRenderStressIsAuthorized {
            // Explicit Simulator-only offered load. This independent clock keeps
            // producing broad synthetic source updates even when rendering hitches;
            // it is stress cadence, never a claim about BLE packet frequency.
            let stressSpeedsKilometersPerHour: [Double] = [
                11.2, 14.8, 18.4, 22.0, 25.6, 29.2, 26.8, 23.2, 19.6, 16.0, 12.4
            ]
            simulatorDashboardRenderStressTask = Task.detached(priority: .userInitiated) {
                let clock = ContinuousClock()
                var sampleIndex = 0

                while !Task.isCancelled {
                    await simulatorService.simulateRide(
                        speedKilometersPerHour: stressSpeedsKilometersPerHour[
                            sampleIndex % stressSpeedsKilometersPerHour.count
                        ],
                        elapsedSeconds: 0
                    )
                    sampleIndex &+= 1

                    do {
                        try await clock.sleep(
                            for: .milliseconds(67),
                            tolerance: .milliseconds(3)
                        )
                    } catch {
                        return
                    }
                }
            }
        }
#endif

        simulatorRideDriverTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }

            let snapshot = await simulatorService.snapshot()
            guard snapshot.connection == .connected,
                  let speed = snapshot.speedKilometersPerHour,
                  speed > 0 else { return }

            // First establish fresh authoritative motion without advancing the
            // simulated odometer. This lets RideEngine establish the ride's ODO
            // baseline before the completed-history fixture adds movement.
            await simulatorService.simulateRide(
                speedKilometersPerHour: speed,
                elapsedSeconds: 0
            )

            guard simulatorAutoCompletesRide else { return }
            guard let sessionID = await waitForActiveRideSessionID() else { return }

            // Let the initial active-ride anchor age past the injected QA
            // checkpoint cadence. The first screened route delta can then
            // establish a partial GPS baseline before later deltas are counted;
            // the ledger never backfills movement across an unavailable source.
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }

            // The route fixture is also explicit Simulator-only evidence. Its
            // geometry is written through RideRouteRecorder, while the same
            // coordinates are screened independently below before any distance
            // delta enters RideEngine. Coverage stays partial because this
            // fixture begins only after the ride reaches confirmed active state.
            if let simulatorRouteRecorder {
                do {
                    try await simulatorRouteRecorder.begin(
                        sessionID: sessionID,
                        coverageAlreadyPartial: true
                    )
                    let now = Date()
                    let route = simulatorRouteCoordinates()

#if DEBUG && targetEnvironment(simulator)
                    var remainingQualityScreenedDistanceMeters: Double?
                    // Keep the explicit QA route and the accepted daily-distance
                    // ledger on the same truthful boundary as production: only
                    // coordinate deltas accepted by RideLocationQualityScreen enter
                    // RideApplicationStore. The screen's synthetic monotonic clock
                    // exists only to evaluate this deterministic fixture; it is not
                    // persisted and is not a claim about physical GPS cadence.
                    if let distanceDeltas = simulatorQualityScreenedDistanceDeltas(
                        route,
                        receivedAtDate: now
                    ) {
                        await rideStore.ingestQualityScreenedGPSDistanceDelta(
                            distanceDeltas[0],
                            receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                            receivedAtDate: .now,
                            for: sessionID
                        )
                        remainingQualityScreenedDistanceMeters = distanceDeltas
                            .dropFirst()
                            .reduce(0, +)
                    }
#endif

                    for (index, coordinate) in route.enumerated() {
                        // The canonical four-point fixture keeps its historical
                        // one-second spacing. A long-route load fixture intentionally
                        // shares one finite fixture timestamp across all points: its
                        // sequence is the ordering authority, and the load fixture
                        // must not fabricate minutes of physical sampling cadence.
                        let fixtureDate = simulatorRoutePointCount > 4
                            ? now
                            : now.addingTimeInterval(Double(index))
                        try await simulatorRouteRecorder.append(
                            latitude: coordinate.0,
                            longitude: coordinate.1,
                            capturedAtDate: fixtureDate,
                            sourceMeasurementDate: fixtureDate,
                            horizontalAccuracyMeters: 4
                        )
                    }

#if DEBUG && targetEnvironment(simulator)
                    // Persisting the route points separates the two real receipt
                    // dates without inventing an arbitrary wall-clock offset.
                    // The second batch is the sum of only the remaining accepted
                    // adjacent deltas; the unavailable pre-route interval stays
                    // excluded and the daily result remains honestly partial.
                    if let remainingQualityScreenedDistanceMeters {
                        await rideStore.ingestQualityScreenedGPSDistanceDelta(
                            remainingQualityScreenedDistanceMeters,
                            receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                            receivedAtDate: .now,
                            for: sessionID
                        )
                    }
#endif

                    _ = try await simulatorRouteRecorder.finish(requestedCoverage: .partial)
                } catch {
                    // The UI test requires route evidence for this opt-in QA
                    // scenario, so a recorder failure remains observable as the
                    // truthful no-route/error state instead of being fabricated.
                }
            }

            // The opt-in history fixture then advances a real Simulator ODO/trip
            // delta through the production service/ride path. `elapsedSeconds`
            // affects simulated distance only; packet timestamps still use the
            // real monotonic arrival clock and never fabricate cadence.
            await simulatorService.simulateRide(
                speedKilometersPerHour: speed,
                elapsedSeconds: 60
            )

            // Explicit end-to-end history fixture used only when a UI/QA launch
            // opts in through the Simulator environment. It drives the real ride
            // engine and persistence path instead of inserting a fake row.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await simulatorService.simulateRide(
                speedKilometersPerHour: 0,
                elapsedSeconds: 0
            )

            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            await simulatorService.simulateRide(
                speedKilometersPerHour: 0,
                elapsedSeconds: 0
            )

        }
    }

    private func waitForActiveRideSessionID() async -> UUID? {
        for _ in 0..<20 {
            if let sessionID = rideStore.activeSessionID {
                return sessionID
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled { return nil }
        }
        return nil
    }

    private func simulatorRouteCoordinates() -> [(Double, Double)] {
        let canonicalShortRoute = [
            (37.33490, -122.00902),
            (37.33535, -122.00840),
            (37.33586, -122.00773),
            (37.33642, -122.00712)
        ]
        guard simulatorRoutePointCount > canonicalShortRoute.count else {
            return canonicalShortRoute
        }

        // Long-route QA remains explicit Simulator evidence. Generate a bounded,
        // deterministic path near the canonical fixture so MapKit sees realistic
        // coordinate volume without claiming these points came from a physical ride.
        let finalIndex = simulatorRoutePointCount - 1
        return (0..<simulatorRoutePointCount).map { index in
            let progress = Double(index) / Double(finalIndex)
            let phase = progress * Double.pi * 6
            let latitude = 37.33490 + (0.0060 * progress) + (sin(phase) * 0.00012)
            let longitude = -122.00902 + (0.0080 * progress) + (cos(phase) * 0.00012)
            return (latitude, longitude)
        }
    }

#if DEBUG && targetEnvironment(simulator)
    private func simulatorQualityScreenedDistanceDeltas(
        _ route: [(Double, Double)],
        receivedAtDate: Date
    ) -> [Double]? {
        guard route.count > 2,
              let policy = try? RideLocationQualityPolicy.simulatorQA() else {
            return nil
        }

        var qualityScreen = RideLocationQualityScreen(policy: policy)
        var distanceDeltas: [Double] = []
        let baseUptimeNanoseconds: UInt64 = 1_000_000_000
        // Four seconds keeps the canonical fixture below the injected QA
        // policy's speed ceiling without crossing its five-second continuity
        // gap. This clock is screening input only and is never persisted.
        let screeningIntervalNanoseconds: UInt64 = 4_000_000_000

        for (index, coordinate) in route.enumerated() {
            guard let index = UInt64(exactly: index),
                  index <= (UInt64.max - baseUptimeNanoseconds) / screeningIntervalNanoseconds,
                  let sample = try? RideLocationSample(
                      latitude: coordinate.0,
                      longitude: coordinate.1,
                      sourceMeasurementDate: receivedAtDate,
                      receivedAtDate: receivedAtDate,
                      receivedAtUptimeNanoseconds: baseUptimeNanoseconds
                          + (index * screeningIntervalNanoseconds),
                      horizontalAccuracyMeters: 4,
                      isSimulatedBySoftware: true
                  ) else {
                return nil
            }

            switch qualityScreen.screen(sample) {
            case .rejected:
                return nil
            case .accepted(let accepted):
                if let distanceDeltaMeters = accepted.distanceDeltaMeters {
                    distanceDeltas.append(distanceDeltaMeters)
                }
            }
        }

        guard distanceDeltas.count > 1,
              distanceDeltas.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return nil
        }
        return distanceDeltas
    }
#endif
}

enum AppBootstrap {
    static let simulationStorageNamespaceEnvironmentKey = "NEMBRA_SIMULATION_STORAGE_NAMESPACE"
    static let simulationAutoCompleteRideEnvironmentKey = "NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE"
    static let simulationSpeedEvidenceGapEnvironmentKey = "NEMBRA_SIMULATION_SPEED_EVIDENCE_GAP"
    static let simulationRoutePointCountEnvironmentKey = "NEMBRA_SIMULATION_ROUTE_POINT_COUNT"
    static let simulationDashboardRenderStressEnvironmentKey = "NEMBRA_SIMULATION_DASHBOARD_RENDER_STRESS"

    private struct VehicleBootstrap {
        let service: any ScooterService
        let simulatorService: SimulatedScooterService?
        let initialState: VehicleState
        let scenario: ScooterSimulationScenario?
        let shouldAutoConnectOnStart: Bool
        let speedInterpolationPolicy: SpeedInstrumentInterpolationPolicy
        let batteryObservationAuthority: BatteryObservationAuthority?
    }

    @MainActor
    static func makeVehicleStore(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VehicleStore {
        let bootstrap = makeVehicleBootstrap(arguments: arguments, environment: environment)
        return VehicleStore(
            service: bootstrap.service,
            initialState: bootstrap.initialState,
            shouldAutoConnectOnStart: bootstrap.shouldAutoConnectOnStart,
            speedInstrumentInterpolationPolicy: bootstrap.speedInterpolationPolicy,
            batteryObservationAuthority: bootstrap.batteryObservationAuthority
        )
    }

    @MainActor
    static func makeRuntime(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppRuntime {
        let bootstrap = makeVehicleBootstrap(arguments: arguments, environment: environment)
        let retainedBatteryStorage: (any RetainedBatterySnapshotStorage)? = bootstrap.scenario == nil
            ? UserDefaultsRetainedBatterySnapshotStorage()
            : nil
        let vehicleStore = VehicleStore(
            service: bootstrap.service,
            initialState: bootstrap.initialState,
            shouldAutoConnectOnStart: bootstrap.shouldAutoConnectOnStart,
            speedInstrumentInterpolationPolicy: bootstrap.speedInterpolationPolicy,
            retainedBatteryStorage: retainedBatteryStorage,
            batteryObservationAuthority: bootstrap.batteryObservationAuthority
        )

        let persistenceScope: RidePersistenceScope
        if let scenario = bootstrap.scenario {
            persistenceScope = .simulation(
                scenario: scenario,
                namespace: environment[simulationStorageNamespaceEnvironmentKey]
            )
        } else {
            persistenceScope = .production
        }

        let persistence: RidePersistenceStack?
        let persistenceError: String?
        do {
            persistence = try RidePersistenceFactory.make(scope: persistenceScope)
            persistenceError = nil
        } catch {
            persistence = nil
            persistenceError = "Local ride storage could not be opened."
        }

        let rideHistoryStore = RideHistoryPresentationStore(
            historyStore: persistence?.historyStore,
            startupPersistenceError: persistenceError
        )
        let rideRouteStore = RideRoutePresentationStore(
            routeStore: persistence?.routeStore,
            startupPersistenceError: persistenceError
        )
        let dailyRideStore = DailyRidePresentationStore(
            store: persistence?.dailyRideStore,
            startupError: persistence?.dailyRideStore == nil
                ? (persistenceError ?? "Daily ride storage could not be opened.")
                : nil
        )

        let rideStore: RideApplicationStore
        if bootstrap.scenario != nil {
            if let persistence {
                do {
                    let configuration = try RideApplicationConfiguration.simulatorQA()
                    rideStore = RideApplicationStore(
                        service: bootstrap.service,
                        initialState: bootstrap.initialState,
                        configuration: configuration,
                        checkpointStore: persistence.checkpointStore,
                        historyStore: persistence.historyStore,
                        dailyRideStore: persistence.dailyRideStore,
                        dailyRidePresentationStore: dailyRideStore
                    )
                } catch {
                    rideStore = RideApplicationStore(
                        service: bootstrap.service,
                        initialState: bootstrap.initialState,
                        configuration: nil,
                        checkpointStore: nil,
                        historyStore: nil,
                        dailyRideStore: nil,
                        dailyRidePresentationStore: dailyRideStore,
                        startupPersistenceError: "Simulator ride tracking could not be configured."
                    )
                }
            } else {
                rideStore = RideApplicationStore(
                    service: bootstrap.service,
                    initialState: bootstrap.initialState,
                    configuration: try? RideApplicationConfiguration.simulatorQA(),
                    checkpointStore: nil,
                    historyStore: nil,
                    dailyRideStore: nil,
                    dailyRidePresentationStore: dailyRideStore,
                    startupPersistenceError: persistenceError ?? "Local ride recovery storage could not be opened."
                )
            }
        } else {
            // Production history/route storage may be opened for truthful
            // read-only presentation, but no production ride detector or
            // location-capture policy is selected until real AOVOPRO ES80 timing
            // and field location behavior are measured.
            rideStore = RideApplicationStore(
                service: bootstrap.service,
                initialState: bootstrap.initialState,
                configuration: nil,
                checkpointStore: nil,
                historyStore: nil,
                dailyRideStore: persistence?.dailyRideStore,
                dailyRidePresentationStore: dailyRideStore
            )
        }

        let simulatorAutoCompletesRide = bootstrap.scenario == .riding
            && environment[simulationAutoCompleteRideEnvironmentKey] == "1"
        let simulatorStartsWithSpeedEvidenceGap = bootstrap.scenario == .connectedStopped
            && environment[simulationSpeedEvidenceGapEnvironmentKey] == "1"
        let simulatorDashboardRenderStressIsAuthorized = simulatorDashboardRenderStressIsAuthorized(
            scenario: bootstrap.scenario,
            hasExactSimulatorService: bootstrap.simulatorService != nil,
            environment: environment
        )
        let simulatorRoutePointCount = simulatorAutoCompletesRide
            ? simulationRoutePointCount(environment: environment)
            : 4
        let simulatorRouteRecorder: RideRouteRecorder?
        if bootstrap.scenario != nil,
           let routeStore = persistence?.routeStore {
            let chunkSize = simulatorRoutePointCount > 4
                ? min(simulatorRoutePointCount, 256)
                : 2
            simulatorRouteRecorder = try? RideRouteRecorder(
                store: routeStore,
                chunkSize: chunkSize
            )
        } else {
            simulatorRouteRecorder = nil
        }

        return AppRuntime(
            vehicleStore: vehicleStore,
            rideStore: rideStore,
            rideHistoryStore: rideHistoryStore,
            rideRouteStore: rideRouteStore,
            dailyRideStore: dailyRideStore,
            automaticCaptureReadiness: AutomaticCaptureReadinessStore(
                factsProvider: SystemAutomaticCapturePlatformFactsProvider(
                    startupStorageUnavailable: persistence == nil
                )
            ),
            simulatorService: bootstrap.simulatorService,
            simulationScenario: bootstrap.scenario,
            simulatorAutoCompletesRide: simulatorAutoCompletesRide,
            simulatorStartsWithSpeedEvidenceGap: simulatorStartsWithSpeedEvidenceGap,
            simulatorDashboardRenderStressIsAuthorized: simulatorDashboardRenderStressIsAuthorized,
            simulatorRoutePointCount: simulatorRoutePointCount,
            simulatorRouteRecorder: simulatorRouteRecorder
        )
    }

    static func simulationScenario(
        arguments: [String],
        environment: [String: String]
    ) -> ScooterSimulationScenario? {
        switch ScooterSimulationConfiguration.resolve(
            arguments: arguments,
            environment: environment
        ) {
        case .selected(let scenario):
            return scenario
        case .disabled, .invalid:
            return nil
        }
    }

    static func simulatorDashboardRenderStressIsAuthorized(
        scenario: ScooterSimulationScenario?,
        hasExactSimulatorService: Bool,
        environment: [String: String]
    ) -> Bool {
#if targetEnvironment(simulator)
        scenario == .riding
            && hasExactSimulatorService
            && environment[simulationDashboardRenderStressEnvironmentKey] == "1"
            && environment[simulationAutoCompleteRideEnvironmentKey] != "1"
#else
        false
#endif
    }

    private static func simulationRoutePointCount(environment: [String: String]) -> Int {
        guard let rawValue = environment[simulationRoutePointCountEnvironmentKey],
              let requested = Int(rawValue),
              (4...5_000).contains(requested) else {
            return 4
        }
        return requested
    }

    @MainActor
    private static func makeVehicleBootstrap(
        arguments: [String],
        environment: [String: String]
    ) -> VehicleBootstrap {
        guard let scenario = simulationScenario(arguments: arguments, environment: environment) else {
            let service = UnverifiedScooterService()
            return VehicleBootstrap(
                service: service,
                simulatorService: nil,
                initialState: UnverifiedScooterService.initialState(),
                scenario: nil,
                shouldAutoConnectOnStart: false,
                speedInterpolationPolicy: .disabled,
                batteryObservationAuthority: nil
            )
        }

        let state = SimulatedScooterService.state(for: scenario)
        let service = SimulatedScooterService(initialState: state)
        return VehicleBootstrap(
            service: service,
            simulatorService: service,
            initialState: state,
            scenario: scenario,
            shouldAutoConnectOnStart: scenario.shouldAutoConnectOnLaunch,
            speedInterpolationPolicy: .simulatorQA,
            batteryObservationAuthority: .displayOnly
        )
    }
}
