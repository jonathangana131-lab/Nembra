import Foundation

@MainActor
final class NembraRuntime {
    let vehicleStore: VehicleStore
    let rideStore: RideStore

    private let qaRideScript: (@Sendable () async -> Void)?
    private var didStart = false

    init(
        vehicleStore: VehicleStore,
        rideStore: RideStore,
        qaRideScript: (@Sendable () async -> Void)? = nil
    ) {
        self.vehicleStore = vehicleStore
        self.rideStore = rideStore
        self.qaRideScript = qaRideScript
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        // Ride recovery/history handoff must be ready before vehicle auto-connect
        // or any QA movement begins, otherwise the app could miss the first
        // evidence after a process relaunch.
        await rideStore.start()
        await vehicleStore.start()

        guard rideStore.lastErrorMessage == nil else { return }
        await qaRideScript?()
    }
}

enum AppBootstrap {
    @MainActor
    static func makeRuntime(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NembraRuntime {
        guard let scenario = simulationScenario(arguments: arguments, environment: environment) else {
            let service = UnverifiedScooterService()
            let state = UnverifiedScooterService.initialState()
            return NembraRuntime(
                vehicleStore: VehicleStore(
                    service: service,
                    initialState: state,
                    shouldAutoConnectOnStart: false,
                    speedInstrumentInterpolationPolicy: .disabled
                ),
                // Automatic ride timing remains hardware-calibration gated for
                // ordinary production/unverified launches.
                rideStore: RideStore(runtimeFactory: nil)
            )
        }

        let state = SimulatedScooterService.state(for: scenario)
        let service = SimulatedScooterService(initialState: state)
        let vehicleStore = VehicleStore(
            service: service,
            initialState: state,
            shouldAutoConnectOnStart: scenario.shouldAutoConnectOnLaunch,
            speedInstrumentInterpolationPolicy: .simulatorQA
        )
        let rideStore = makeSimulationRideStore(
            service: service,
            scenario: scenario,
            environment: environment
        )
        let script = makeQARideScript(
            service: service,
            environment: environment
        )

        return NembraRuntime(
            vehicleStore: vehicleStore,
            rideStore: rideStore,
            qaRideScript: script
        )
    }

    /// Kept for focused app tests. Production `NembraApp` uses `makeRuntime()` so
    /// VehicleStore and RideStore share one transport instance.
    @MainActor
    static func makeVehicleStore(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> VehicleStore {
        makeRuntime(arguments: arguments, environment: environment).vehicleStore
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
    private static func makeSimulationRideStore(
        service: SimulatedScooterService,
        scenario: ScooterSimulationScenario,
        environment: [String: String]
    ) -> RideStore {
        let namespace = sanitizedStorageNamespace(
            environment["NEMBRA_RIDE_QA_NAMESPACE"] ?? scenario.rawValue
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NembraRideQA", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)

        if environment["NEMBRA_RIDE_QA_PRESERVE"] != "1" {
            try? FileManager.default.removeItem(at: root)
        }

        let checkpointDirectory = root.appendingPathComponent("checkpoint", isDirectory: true)
        let historyDirectory = root.appendingPathComponent("history", isDirectory: true)

        return RideStore(runtimeFactory: {
            let detectionPolicy = try RideDetectionPolicy(
                candidateSpeedKilometersPerHour: 1,
                confirmationSpeedKilometersPerHour: 4,
                confirmationDurationNanoseconds: 250_000_000,
                confirmationOdometerDeltaKilometers: 0.02,
                confirmationGPSDistanceMeters: 8,
                endingDurationNanoseconds: 800_000_000,
                maximumSpeedSampleAgeNanoseconds: 500_000_000
            )
            let checkpointCadence = try RideCheckpointCadence(
                minimumIntervalNanoseconds: 1_000_000_000
            )
            return try await RideApplicationRuntime.restoring(
                service: service,
                detectionPolicy: detectionPolicy,
                checkpointStore: AtomicRideCheckpointStore(directoryURL: checkpointDirectory),
                checkpointCadence: checkpointCadence,
                historyStore: AtomicRideHistoryStore(directoryURL: historyDirectory)
            )
        })
    }

    private static func makeQARideScript(
        service: SimulatedScooterService,
        environment: [String: String]
    ) -> (@Sendable () async -> Void)? {
        guard environment["NEMBRA_RIDE_QA_SCRIPT"] == "active" else { return nil }

        return {
            // QA-only packet timing. This exercises the real ride runtime and is
            // not a claim about MAXSHOT notification cadence or detection timing.
            try? await Task.sleep(nanoseconds: 350_000_000)
            await service.simulateRide(speedKilometersPerHour: 6, elapsedSeconds: 1)
            try? await Task.sleep(nanoseconds: 300_000_000)
            await service.simulateRide(speedKilometersPerHour: 9, elapsedSeconds: 1)
        }
    }

    private static func sanitizedStorageNamespace(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(scalars)
        return result.isEmpty ? "default" : result
    }
}
