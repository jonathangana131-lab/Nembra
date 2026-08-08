import Foundation

extension PassiveBluetoothExperimentOneSoftwareExportCodec {
    /// Package-only compatibility seam for the existing adversarial package suite while callers
    /// migrate to the explicit contract names. This performs self-consistency validation only.
    /// App/UI consumers cannot call this overload because it is not public.
    package static func decodeAndVerify(
        _ data: Data
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try decodeAndValidateSelfConsistency(data)
    }
}
