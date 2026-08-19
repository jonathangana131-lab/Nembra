import Foundation

struct NembraCaptureBuildIdentity: Codable, Equatable, Sendable {
    static let buildIdentifierInfoKey = "NembraCaptureBuildIdentifier"
    static let sourceCommitSHAInfoKey = "NembraCaptureSourceCommitSHA"
    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"
    static let procedureIdentifierInfoKey = "NembraCaptureProcedureIdentifier"
    static let requiredFieldProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"

    let buildIdentifier: String
    let sourceCommitSHA: String
    let tuyaDependencyLockSHA256: String
    let procedureIdentifier: String

    static var current: Self {
        from(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    /// App-visible and exported procedure provenance must describe the built app,
    /// including failed/non-authoritative diagnostic builds, rather than echoing
    /// the procedure Nembra expected the installer to stamp.
    static var fieldProcedureIdentifier: String {
        current.procedureIdentifier
    }

    static func from(infoDictionary: [String: Any]) -> Self {
        Self(
            buildIdentifier: (infoDictionary[buildIdentifierInfoKey] as? String) ?? "",
            sourceCommitSHA: ((infoDictionary[sourceCommitSHAInfoKey] as? String) ?? "").lowercased(),
            tuyaDependencyLockSHA256: ((infoDictionary[tuyaDependencyLockSHA256InfoKey] as? String) ?? "").lowercased(),
            procedureIdentifier: (infoDictionary[procedureIdentifierInfoKey] as? String) ?? ""
        )
    }

    /// Verifies only the self-described build metadata tuple carried by the app bundle.
    ///
    /// These values are useful provenance and remain required inputs to the private installer,
    /// but they come from ordinary build settings. A caller who can modify, sign, and install a
    /// local build can choose another internally consistent tuple, so this predicate must never
    /// be promoted into runtime physical authorization by itself.
    var hasCompleteFieldBuildMetadata: Bool {
        guard sourceCommitSHA.count == 40,
              sourceCommitSHA.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
              }),
              tuyaDependencyLockSHA256.count == 64,
              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
              }),
              procedureIdentifier == Self.requiredFieldProcedureIdentifier else { return false }

        let expectedIdentifier = "capture-v14-\(sourceCommitSHA.prefix(12))"
        return buildIdentifier == expectedIdentifier
    }

    /// Physical OFF1 authority intentionally remains fail-closed.
    ///
    /// `hasCompleteFieldBuildMetadata` proves that the bundle is internally consistent, not that
    /// an independent actor accepted this exact installed binary. The current field caller can
    /// control local source/build settings/signing, so no caller-constructible plist value or
    /// verifier embedded in the same modifiable app can close that trust boundary. A future
    /// external authorization mechanism must become the root of trust before this may return true.
    var isAuthoritativeFieldBuild: Bool {
        false
    }

    var blocker: String? {
        guard hasCompleteFieldBuildMetadata else {
            return "This build has no valid exact Git + reviewed Tuya dependency + canonical stationary procedure metadata. Install Capture through the repository field installer before physical evidence collection."
        }
        return "Build metadata is complete, but independent physical-build authorization is not available yet. Physical Capture remains locked before OFF1."
    }
}
