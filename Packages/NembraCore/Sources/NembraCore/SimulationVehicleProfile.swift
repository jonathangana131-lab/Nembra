import Foundation

public extension VehicleProfile {
    /// Explicitly synthetic capability profile for Simulator and deterministic QA.
    ///
    /// This profile exists so UI/runtime tests can exercise control, telemetry,
    /// ride-mode, limiter, and electrical presentation paths without borrowing
    /// capability claims from either the primary AOVOPRO ES80 target or the
    /// deferred MAXSHOT profile. Values produced under this profile are
    /// SIMULATOR evidence only and must never be promoted to physical hardware
    /// verification.
    static let simulatorQA = VehicleProfile(
        identity: VehicleIdentity(
            manufacturer: "NEMBRA",
            model: "Simulator",
            displayName: "Nembra Simulator",
            protocolFamily: "Synthetic QA (not physical scooter protocol)"
        ),
        capabilities: VehicleCapabilities(
            supportsLock: true,
            supportsHeadlight: true,
            supportsCruise: true,
            supportsStartMode: true,
            supportsSpeedLimit: true,
            supportsOdometer: true,
            supportsLiveSpeed: true,
            supportsBatteryPercent: true,
            supportsPowerWatts: true,
            supportsCurrentAmps: true,
            supportedRideModes: Set(RideMode.allCases),
            speedLimitRangesBySlot: [
                .limit1: SpeedLimitRange(minimumKilometersPerHour: 5, maximumKilometersPerHour: 15),
                .limit2: SpeedLimitRange(minimumKilometersPerHour: 10, maximumKilometersPerHour: 24),
                .limit3: SpeedLimitRange(minimumKilometersPerHour: 20, maximumKilometersPerHour: 35)
            ],
            verifiedSpeedLimitSlotByRideMode: [:]
        )
    )
}
