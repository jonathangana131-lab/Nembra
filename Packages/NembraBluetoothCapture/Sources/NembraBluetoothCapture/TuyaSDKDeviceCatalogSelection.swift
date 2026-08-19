import Foundation

/// Allow-listed, non-secret SDK fields used only to present a Capture target choice.
/// A catalog locator is not current account membership authority; the app must perform
/// a fresh complete membership enumeration immediately before Bluetooth discovery.
public struct TuyaSDKDeviceLocator: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let productID: String
    public let uuid: String

    public init(id: String, name: String, productID: String, uuid: String) {
        self.id = id
        self.name = name
        self.productID = productID
        self.uuid = uuid
    }

    public var displayName: String {
        name.isEmpty ? "Unnamed scooter" : name
    }

    public var hasCompleteLocator: Bool {
        !id.isEmpty && !productID.isEmpty && !uuid.isEmpty
    }
}

public struct TuyaSDKDeviceCatalogSnapshot: Equatable, Sendable {
    public let devices: [TuyaSDKDeviceLocator]
    public let encounteredDeviceCount: Int
    public let incompleteDeviceCount: Int

    public init(
        devices: [TuyaSDKDeviceLocator],
        encounteredDeviceCount: Int,
        incompleteDeviceCount: Int
    ) {
        self.devices = devices
        self.encounteredDeviceCount = encounteredDeviceCount
        self.incompleteDeviceCount = incompleteDeviceCount
    }

}

public enum TuyaSDKDeviceCatalogSelectionError: Error, Equatable, LocalizedError, Sendable {
    case incompleteHomeEnumeration
    case conflictingRequiredLocator

    public var errorDescription: String? {
        switch self {
        case .incompleteHomeEnumeration:
            return "Tuya could not finish loading every home. Capture will not guess from a partial scooter list."
        case .conflictingRequiredLocator:
            return "Tuya returned conflicting Bluetooth locator data for one device. Capture stopped before scooter selection."
        }
    }
}

/// Deterministically merges owned and shared device records from a complete SDK home walk.
/// It deliberately carries no account token, UID, local key, DPS, or membership verdict.
public struct TuyaSDKDeviceCatalogAccumulator: Sendable {
    private var encounteredDeviceIDs: Set<String> = []
    private var incompleteDeviceCount = 0
    private var devicesByID: [String: TuyaSDKDeviceLocator] = [:]
    private var hasConflictingRequiredLocator = false

    public init() {}

    public mutating func admit(
        id rawID: String?,
        name rawName: String?,
        productID rawProductID: String?,
        uuid rawUUID: String?
    ) {
        let id = Self.normalized(rawID)
        guard !id.isEmpty else {
            incompleteDeviceCount += 1
            return
        }

        encounteredDeviceIDs.insert(id)
        let candidate = TuyaSDKDeviceLocator(
            id: id,
            name: Self.normalized(rawName),
            productID: Self.normalized(rawProductID),
            uuid: Self.normalized(rawUUID)
        )
        guard candidate.hasCompleteLocator else {
            incompleteDeviceCount += 1
            return
        }

        guard let existing = devicesByID[id] else {
            devicesByID[id] = candidate
            return
        }
        guard existing.productID == candidate.productID,
              existing.uuid == candidate.uuid else {
            hasConflictingRequiredLocator = true
            return
        }

        // Name is descriptive only. Select a deterministic non-empty spelling without
        // weakening the exact required locator comparison above.
        if existing.name.isEmpty || (!candidate.name.isEmpty && candidate.name < existing.name) {
            devicesByID[id] = candidate
        }
    }

    public func finish(
        expectedHomeCount: Int,
        loadedHomeCount: Int,
        homeLoadFailureCount: Int
    ) throws -> TuyaSDKDeviceCatalogSnapshot {
        guard !hasConflictingRequiredLocator else {
            throw TuyaSDKDeviceCatalogSelectionError.conflictingRequiredLocator
        }
        guard expectedHomeCount >= 0,
              loadedHomeCount == expectedHomeCount,
              homeLoadFailureCount == 0 else {
            throw TuyaSDKDeviceCatalogSelectionError.incompleteHomeEnumeration
        }
        let devices = devicesByID.values.sorted {
            let ordering = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            return ordering == .orderedSame ? $0.id < $1.id : ordering == .orderedAscending
        }
        return TuyaSDKDeviceCatalogSnapshot(
            devices: devices,
            encounteredDeviceCount: encounteredDeviceIDs.count,
            incompleteDeviceCount: incompleteDeviceCount
        )
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
