import NembraCore

public extension PassiveBluetoothTransportFingerprint {
    /// Conservative convenience for callers that do not yet have an explicit
    /// peripheral selection. It only returns transport evidence when exactly one
    /// peripheral has produced GATT-path evidence in the capture.
    ///
    /// Advertisement-only scans and connection-only records can contain unrelated
    /// nearby devices or prove only link identity, so they intentionally return an
    /// empty report rather than an aggregate transport guess. Structured
    /// subscription evidence may count because it names an exact service and
    /// characteristic path.
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
            case let .subscription(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .value(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case .advertisement, .connection, .stockAppState, .interruption:
                break
            }
        }
        return identifiers
    }
}
