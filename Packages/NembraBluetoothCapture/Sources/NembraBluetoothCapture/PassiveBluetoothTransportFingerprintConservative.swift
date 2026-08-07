import NembraCore

public extension PassiveBluetoothTransportFingerprint {
    /// Conservative convenience for callers that do not yet have an explicit
    /// peripheral selection. It only returns transport evidence when exactly one
    /// peripheral has produced connected/GATT evidence in the capture.
    ///
    /// Advertisement-only scans can contain unrelated nearby Tuya devices, so
    /// they intentionally return an empty report rather than an aggregate guess.
    static func analyze(
        _ session: PassiveBluetoothCaptureSession
    ) -> PassiveBluetoothTransportFingerprintReport {
        let identifiers = gattEvidencePeripheralIdentifiers(in: session)
        guard identifiers.count == 1, let identifier = identifiers.first else {
            return PassiveBluetoothTransportFingerprintReport(
                peripheralIdentifier: "",
                observedServiceUUIDs: [],
                characteristicUUIDsByService: [:],
                candidateMatches: []
            )
        }
        return analyze(session, peripheralIdentifier: identifier)
    }

    private static func gattEvidencePeripheralIdentifiers(
        in session: PassiveBluetoothCaptureSession
    ) -> Set<String> {
        var identifiers: Set<String> = []
        for record in session.records {
            switch record.event {
            case let .service(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .includedService(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .characteristic(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .descriptor(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .value(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case .advertisement, .stockAppState, .interruption:
                break
            }
        }
        return identifiers
    }
}
