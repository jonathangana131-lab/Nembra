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

    private let simulatorService: SimulatedScooterService?
    private let simulationScenario: ScooterSimulationScenario?
    private let simulatorAutoCompletesRide: Bool
    private let simulatorStartsWithSpeedEvidenceGap: Bool
    private let simulatorStartsWithRetainedPowerAfterReconnect: Bool
    private let simulatorDrivesDashboardStress: Bool
    private let simulatorRouteRecorder: RideRouteRecorder?
    private var didStart = false
    private var simulatorRideDriverTask: Task<Void, Never>?

    init(
        vehicleStore: VehicleStore,
        rideStore: RideApplicationStore,
        rideHistoryStore: RideHistoryPresentationStore,
        rideRouteStore: RideRoutePresentationStore,
        simulatorService: SimulatedScooterService?,
        simulationScenario: ScooterSimulationScenario?,
        simulatorAutoCompletesRide: Bool,
        simulatorStartsWithSpeedEvidenceGap: Bool,
        simulatorStartsWithRetainedPowerAfterReconnect: Bool,
        simulatorDrivesDashboardStress: Bool,
        simulatorRouteRecorder: RideRouteRecorder?
    ) {
        self.vehicleStore = vehicleStore
        self.rideStore = rideStore
        self.rideHistoryStore = rideHistoryStore
        self.rideRouteStore = rideRouteStore
        self.simulatorService = simulatorService
        self.simulationScenario = simulationScenario
        self.simulatorAutoCompletesRide = simulatorAutoCompletesRide
        self.simulatorStartsWithSpeedEvidenceGap = simulatorStartsWithSpeedEvidenceGap
        self.simulatorStartsWithRetainedPowerAfterReconnect = simulatorStartsWithRetainedPowerAfterReconnect
        self.simulatorDrivesDashboardStress = simulatorDrivesDashboardStress
        self.simulatorRouteRecorder = simulatorRouteRecorder
    }

    deinit {
        simulatorRideDriverTask?.cancel()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

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

        // Deterministic Simulator-only retained-power fixture. The riding scenario
        // begins with a legitimate fixture-owned 356 W source receipt. Exercise the
        // real synthetic transport-loss path and then reconnect. Reconnect supplies
        // fresh speed but deliberately does not mint a new power receipt, leaving the
        // exact prior propulsion receipt RETAINED while aggregate transport is again
        // connected. Returning prevents the ride driver from refreshing propulsion.
        if simulatorStartsWithRetainedPowerAfterReconnect,
           let simulatorService {
            await simulatorService.simulateConnectionDrop()
            await simulatorService.connect()
            return
        }

        guard simulationScenario == .riding,
              let simulatorService else { return }

        // Simulator-only sustained Dashboard stress fixture. This cadence is an
        // intentionally synthetic QA load and makes no claim about AOVOPRO ES80
        // packet cadence. `elapsedSeconds: 0` means every call mints genuine
        // Simulator-owned speed/power source receipts through the normal source
        // boundary while adding zero synthetic trip/odometer distance. Run the
        // driver detached so the harness itself does not schedule its 10 Hz loop on
        // the app MainActor that the hitch metric is trying to evaluate.
        if simulatorDrivesDashboardStress {
            let speedsKilometersPerHour: [Double] = [
                8, 16, 22, 12, 19, 6, 24, 14, 18, 10
            ]
            simulatorRideDriverTask = Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }

                for index in 0..<120 {
                    guard !Task.isCancelled else { return }
                    await simulatorService.simulateRide(
                        speedKilometersPerHour: speedsKilometersPerHour[index % speedsKilometersPerHour.count],
                        elapsedSeconds: 0
                    )
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            return
        }

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

            // The opt-in history fixture then advances a real Simulator ODO/trip
            // delta through the production service/ride path. `elapsedSeconds`
            // affects simulated distance only; packet timestamps still use the
            // real monotonic arrival clock and never fabricate cadence.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await simulatorService.simulateRide(
                speedKilometersPerHour: speed,
                elapsedSeconds: 60
            )

            // The route fixture is also explicit Simulator-only evidence. It is
            // written through RideRouteRecorder and the production route-store
            // contract; it never mutates completed-history distance evidence and
            // is classified partial because recording starts only after the ride
            // has already reached confirmed active state.
            if let sessionID = await waitForActiveRideSessionID(),
               let simulatorRouteRecorder {
                do {
                    try await simulatorRouteRecorder.begin(
                        sessionID: sessionID,
                        coverageAlreadyPartial: true
                    )
                    let now = Date()
                    let route = [
                        (37.33490, -122.00902),
                        (37.33535, -122.00840),
                        (37.33586, -122.00773),
                        (37.33642, -122.00712)
                    ]
                    for (index, coordinate) in route.enumerated() {
                        try await simulatorRouteRecorder.append(
                            latitude: coordinate.0,
                            longitude: coordinate.1,
                            capturedAtDate: now.addingTimeInterval(Double(index)),
                            sourceMeasurementDate: now.addingTimeInterval(Double(index)),
                            horizontalAccuracyMeters: 4
                        )
                    }
                    _ = try await simulatorRouteRecorder.finish(requestedCoverage: .partial)
                } catch {
                    // The UI test requires route evidence for this opt-in QA
                    // scenario, so a recorder failure remains observable as the
                    // truthful no-route/error state instead of being fabricated.
                }
            }

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
}

enum AppBootstrap {
    static let simulationStorageNamespaceEnvironmentKey = "NEMBRA_SIMULATION_STORAGE_NAMESPACE"
    static let simulationAutoCompleteRideEnvironmentKey = "NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE"
    static let simulationSpeedEvidenceGapEnvironmentKey = "NEMBRA_SIMULATION_SPEED_EVIDENCE_GAP"
    static let simulationRetainedPowerAfterReconnectEnvironmentKey = "NEMBRA_SIMULATION_RETAINED_POWER_AFTER_RECONNECT"
    static let simulationDashboardStressEnvironmentKey = "NEMBRA_SIMULATION_DASHBOARD_STRESS"

    private struct VehicleBootstrap {
        let service: any ScooterService
        let simulatorService: SimulatedScooterService?
        let initialState: VehicleState
        let scenario: ScooterSimulationScenario?
        let shouldAutoConnectOnStart: Bool
        let speedInterpolationPolicy: SpeedInstrumentInterpolationPolicy
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
            speedInstrumentInterpolationPolicy: bootstrap.speedInterpolationPolicy
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
            retainedBatteryStorage: retainedBatteryStorage
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
                        historyStore: persistence.historyStore
                    )
                } catch {
                    rideStore = RideApplicationStore(
                        service: bootstrap.service,
                        initialState: bootstrap.initialState,
                        configuration: nil,
                        checkpointStore: nil,
                        historyStore: nil,
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
                historyStore: nil
            )
        }

        let simulatorAutoCompletesRide = bootstrap.scenario == .riding
            && environment[simulationAutoCompleteRideEnvironmentKey] == "1"
        let simulatorStartsWithSpeedEvidenceGap = bootstrap.scenario == .connectedStopped
            && environment[simulationSpeedEvidenceGapEnvironmentKey] == "1"
        let simulatorStartsWithRetainedPowerAfterReconnect = bootstrap.scenario == .riding
            && environment[simulationRetainedPowerAfterReconnectEnvironmentKey] == "1"
        let simulatorDrivesDashboardStress = bootstrap.scenario == .riding
            && environment[simulationDashboardStressEnvironmentKey] == "1"
        let simulatorRouteRecorder: RideRouteRecorder?
        if bootstrap.scenario != nil,
           let routeStore = persistence?.routeStore {
            simulatorRouteRecorder = try? RideRouteRecorder(
                store: routeStore,
                chunkSize: 2
            )
        } else {
            simulatorRouteRecorder = nil
        }

        return AppRuntime(
            vehicleStore: vehicleStore,
            rideStore: rideStore,
            rideHistoryStore: rideHistoryStore,
            rideRouteStore: rideRouteStore,
            simulatorService: bootstrap.simulatorService,
            simulationScenario: bootstrap.scenario,
            simulatorAutoCompletesRide: simulatorAutoCompletesRide,
            simulatorStartsWithSpeedEvidenceGap: simulatorStartsWithSpeedEvidenceGap,
            simulatorStartsWithRetainedPowerAfterReconnect: simulatorStartsWithRetainedPowerAfterReconnect,
            simulatorDrivesDashboardStress: simulatorDrivesDashboardStress,
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
                speedInterpolationPolicy: .disabled
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
            speedInterpolationPolicy: .simulatorQA
        )
    }
}