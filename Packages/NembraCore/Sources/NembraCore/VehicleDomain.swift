import Foundation

public enum RideMode: String, CaseIterable, Codable, Sendable {
    case walk
    case eco
    case drive
    case sport

    public var displayName: String {
        switch self {
        case .walk: "Walk"
        case .eco: "Eco"
        case .drive: "Drive"
        case .sport: "Sport"
        }
    }
}

public enum StartMode: String, CaseIterable, Codable, Sendable {
    case kickStart
    case zeroStart

    public var displayName: String {
        switch self {
        case .kickStart: "Kick Start"
        case .zeroStart: "Zero Start"
        }
    }
}

public enum VehicleConnectionState: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

public enum VehicleConnectionIssue: String, Codable, Sendable {
    case bluetoothPoweredOff
    case bluetoothPermissionDenied
    case scooterUnavailable
    case unsupportedConfiguration

    public var blocksConnectionAttempt: Bool {
        switch self {
        case .bluetoothPoweredOff, .bluetoothPermissionDenied, .unsupportedConfiguration:
            true
        case .scooterUnavailable:
            false
        }
    }
}

/// A protocol-level speed-limit slot exposed by a scooter profile.
///
/// The deferred MAXSHOT protocol audit verified three independent writable
/// Tuya datapoints (DP101/102/103), but never established a trustworthy mapping
/// between those slots and DP15 ride modes. Keep that distinction explicit.
/// AOVOPRO ES80 slot/range semantics remain empty until real capture proves them.
public enum SpeedLimitSlot: Int, CaseIterable, Codable, Sendable {
    case limit1 = 1
    case limit2 = 2
    case limit3 = 3

    public var displayName: String { "Limit \(rawValue)" }
}

public struct SpeedLimitRange: Equatable, Codable, Sendable {
    public let minimumKilometersPerHour: Int
    public let maximumKilometersPerHour: Int

    private enum CodingKeys: String, CodingKey {
        case minimumKilometersPerHour
        case maximumKilometersPerHour
    }

    public init(minimumKilometersPerHour: Int, maximumKilometersPerHour: Int) {
        precondition(minimumKilometersPerHour <= maximumKilometersPerHour)
        self.minimumKilometersPerHour = minimumKilometersPerHour
        self.maximumKilometersPerHour = maximumKilometersPerHour
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let minimum = try container.decode(Int.self, forKey: .minimumKilometersPerHour)
        let maximum = try container.decode(Int.self, forKey: .maximumKilometersPerHour)
        guard minimum <= maximum else {
            throw DecodingError.dataCorruptedError(
                forKey: .maximumKilometersPerHour,
                in: container,
                debugDescription: "Maximum speed must be greater than or equal to minimum speed."
            )
        }
        minimumKilometersPerHour = minimum
        maximumKilometersPerHour = maximum
    }

    public func contains(_ value: Int) -> Bool {
        guard minimumKilometersPerHour <= maximumKilometersPerHour else { return false }
        return (minimumKilometersPerHour...maximumKilometersPerHour).contains(value)
    }
}

public struct VehicleCapabilities: Equatable, Codable, Sendable {
    public let supportsLock: Bool
    public let supportsHeadlight: Bool
    public let supportsCruise: Bool
    public let supportsStartMode: Bool
    public let supportsSpeedLimit: Bool
    public let supportsOdometer: Bool
    public let supportsLiveSpeed: Bool
    public let supportsBatteryPercent: Bool
    public let supportsPowerWatts: Bool
    public let supportsCurrentAmps: Bool
    public let supportedRideModes: Set<RideMode>
    public let speedLimitRangesBySlot: [SpeedLimitSlot: SpeedLimitRange]

    /// Only mappings proven from hardware/protocol observation belong here.
    /// An empty mapping intentionally means the app must not present a
    /// mode-specific speed-limit control in normal user-facing UI.
    public let verifiedSpeedLimitSlotByRideMode: [RideMode: SpeedLimitSlot]

    public init(
        supportsLock: Bool,
        supportsHeadlight: Bool,
        supportsCruise: Bool,
        supportsStartMode: Bool,
        supportsSpeedLimit: Bool,
        supportsOdometer: Bool,
        supportsLiveSpeed: Bool,
        supportsBatteryPercent: Bool,
        supportsPowerWatts: Bool,
        supportsCurrentAmps: Bool,
        supportedRideModes: Set<RideMode>,
        speedLimitRangesBySlot: [SpeedLimitSlot: SpeedLimitRange],
        verifiedSpeedLimitSlotByRideMode: [RideMode: SpeedLimitSlot] = [:]
    ) {
        self.supportsLock = supportsLock
        self.supportsHeadlight = supportsHeadlight
        self.supportsCruise = supportsCruise
        self.supportsStartMode = supportsStartMode
        self.supportsSpeedLimit = supportsSpeedLimit
        self.supportsOdometer = supportsOdometer
        self.supportsLiveSpeed = supportsLiveSpeed
        self.supportsBatteryPercent = supportsBatteryPercent
        self.supportsPowerWatts = supportsPowerWatts
        self.supportsCurrentAmps = supportsCurrentAmps
        self.supportedRideModes = supportedRideModes
        self.speedLimitRangesBySlot = speedLimitRangesBySlot
        self.verifiedSpeedLimitSlotByRideMode = verifiedSpeedLimitSlotByRideMode
    }

    public var hasUserFacingSpeedLimitMapping: Bool {
        !verifiedSpeedLimitSlotByRideMode.isEmpty
    }
}

public struct VehicleIdentity: Equatable, Codable, Sendable {
    public let manufacturer: String
    public let model: String
    public let displayName: String
    public let protocolFamily: String

    public init(manufacturer: String, model: String, displayName: String, protocolFamily: String) {
        self.manufacturer = manufacturer
        self.model = model
        self.displayName = displayName
        self.protocolFamily = protocolFamily
    }
}

public enum VehicleDataAvailability: String, Equatable, Codable, Sendable {
    /// The app has not yet observed any confirmed vehicle value.
    case unavailable
    /// Confirmed values belong to the currently connected vehicle session.
    case live
    /// Confirmed values are retained from an earlier connected state and must
    /// be presented read-only until the vehicle reports fresh data again.
    case retained
}

public struct VehicleState: Equatable, Codable, Sendable {
    public var connection: VehicleConnectionState
    public var connectionIssue: VehicleConnectionIssue?
    public var batteryPercent: Int?
    public var speedKilometersPerHour: Double?
    public var odometerKilometers: Double?
    public var tripKilometers: Double?
    public var rideMode: RideMode?
    public var startMode: StartMode?
    public var speedLimitsKilometersPerHour: [SpeedLimitSlot: Int]
    public var isLocked: Bool?
    public var isHeadlightOn: Bool?
    public var isCruiseEnabled: Bool?
    public var powerWatts: Int?
    public var currentAmps: Double?
    public var lastUpdated: Date

    public init(
        connection: VehicleConnectionState,
        connectionIssue: VehicleConnectionIssue? = nil,
        batteryPercent: Int?,
        speedKilometersPerHour: Double?,
        odometerKilometers: Double?,
        tripKilometers: Double?,
        rideMode: RideMode?,
        startMode: StartMode?,
        speedLimitsKilometersPerHour: [SpeedLimitSlot: Int],
        isLocked: Bool?,
        isHeadlightOn: Bool?,
        isCruiseEnabled: Bool?,
        powerWatts: Int?,
        currentAmps: Double?,
        lastUpdated: Date = .now
    ) {
        self.connection = connection
        self.connectionIssue = connectionIssue
        self.batteryPercent = batteryPercent
        self.speedKilometersPerHour = speedKilometersPerHour
        self.odometerKilometers = odometerKilometers
        self.tripKilometers = tripKilometers
        self.rideMode = rideMode
        self.startMode = startMode
        self.speedLimitsKilometersPerHour = speedLimitsKilometersPerHour
        self.isLocked = isLocked
        self.isHeadlightOn = isHeadlightOn
        self.isCruiseEnabled = isCruiseEnabled
        self.powerWatts = powerWatts
        self.currentAmps = currentAmps
        self.lastUpdated = lastUpdated
    }
}

public extension VehicleState {
    var hasConfirmedVehicleData: Bool {
        batteryPercent != nil ||
            speedKilometersPerHour != nil ||
            odometerKilometers != nil ||
            tripKilometers != nil ||
            rideMode != nil ||
            startMode != nil ||
            !speedLimitsKilometersPerHour.isEmpty ||
            isLocked != nil ||
            isHeadlightOn != nil ||
            isCruiseEnabled != nil ||
            powerWatts != nil ||
            currentAmps != nil
    }

    var dataAvailability: VehicleDataAvailability {
        guard hasConfirmedVehicleData else { return .unavailable }
        return connection == .connected ? .live : .retained
    }
}

public struct VehicleProfile: Equatable, Sendable {
    public let identity: VehicleIdentity
    public let capabilities: VehicleCapabilities

    public init(identity: VehicleIdentity, capabilities: VehicleCapabilities) {
        self.identity = identity
        self.capabilities = capabilities
    }

    /// Primary real hardware-validation target.
    ///
    /// Public/user-observed app behavior corroborates lock, light, cruise,
    /// start-mode/speed configuration, speed, mileage, and a user-facing battery
    /// percentage. Their exact ES80 BLE/Tuya data points, scales, mode mapping,
    /// limiter ranges, acknowledgement semantics, and whether the battery value
    /// is direct or Tuya-derived remain hardware-validation work. Therefore this
    /// profile advertises broad product capabilities but intentionally leaves
    /// protocol-specific ride-mode/range mappings empty and does not claim
    /// current/power telemetry despite some stock-app detail screens showing it.
    public static let aovoproES80 = VehicleProfile(
        identity: VehicleIdentity(
            manufacturer: "AOVOPRO",
            model: "ES80",
            displayName: "AOVOPRO ES80",
            protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
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
            supportsPowerWatts: false,
            supportsCurrentAmps: false,
            supportedRideModes: [],
            speedLimitRangesBySlot: [:],
            verifiedSpeedLimitSlotByRideMode: [:]
        )
    )

    /// Explicitly synthetic capability profile for Simulator and deterministic QA.
    ///
    /// This profile exists so UI/runtime tests can exercise control, telemetry,
    /// ride-mode, limiter, and electrical presentation paths without borrowing
    /// capability claims from either the primary AOVOPRO ES80 target or the
    /// deferred MAXSHOT profile. Values produced under this profile are
    /// SIMULATOR evidence only and must never be promoted to physical hardware
    /// verification.
    public static let simulatorQA = VehicleProfile(
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

    /// Deferred/unverified profile retained from the original first target.
    public static let maxshotV1SPro = VehicleProfile(
        identity: VehicleIdentity(
            manufacturer: "MAXSHOT",
            model: "V1S Pro",
            displayName: "MAXSHOT V1S Pro",
            protocolFamily: "Tuya / YouFS (hardware validation deferred)"
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
