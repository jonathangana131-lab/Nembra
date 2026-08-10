#if SWIFT_PACKAGE
/// Package-internal retained accessibility reconstruction for an already-sealed
/// accepted cockpit measurement. This never mints watts or chronology: it copies
/// the exact immutable accepted subject into the accessibility cadence key while
/// changing currentness only to RETAINED.
extension PropulsionEnergyRailAcceptedRevision {
    init(acceptedMeasurement: PropulsionGaugeCockpitAcceptedMeasurement) {
        authority = acceptedMeasurement.authority
        continuityGeneration = acceptedMeasurement.continuityGeneration
        receiptSequenceNumber = acceptedMeasurement.receiptSequenceNumber
        receivedAtUptimeNanoseconds = acceptedMeasurement.receivedAtUptimeNanoseconds
    }
}

extension PropulsionEnergyRailAccessibilityPresentation {
    static func retained(
        acceptedMeasurement: PropulsionGaugeCockpitAcceptedMeasurement
    ) -> Self {
        let revision = PropulsionEnergyRailAcceptedRevision(
            acceptedMeasurement: acceptedMeasurement
        )
        return Self(
            identity: acceptedMeasurement.identity,
            currentness: .retained,
            acceptedWatts: acceptedMeasurement.watts,
            acceptedRevision: revision
        )
    }
}
#endif
