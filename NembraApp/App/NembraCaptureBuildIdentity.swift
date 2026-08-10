import Foundation

struct NembraCaptureBuildIdentity: Codable, Equatable, Sendable {
    static let buildIdentifierInfoKey = "NembraCaptureBuildIdentifier"
    static let sourceCommitSHAInfoKey = "NembraCaptureSourceCommitSHA"
    static let tuyaDependencyLockSHA256InfoKey = "NembraCaptureTuyaDependencyLockSHA256"
    static let procedureIdentifierInfoKey = "NembraCaptureProcedureIdentifier"
    static let requiredProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"

    let buildIdentifier: String
    let sourceCommitSHA: String
    let tuyaDependencyLockSHA256: String
    let procedureIdentifier: String

    static var current: Self {
        from(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    /// The app-visible/exported procedure value is the value compiled into the
    /// built app's Info.plist, not a second presentation-only constant.
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

    var isAuthoritativeFieldBuild: Bool {
        guard procedureIdentifier == Self.requiredProcedureIdentifier,
              sourceCommitSHA.count == 40,
              sourceCommitSHA.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
              }),
              tuyaDependencyLockSHA256.count == 64,
              tuyaDependencyLockSHA256.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
              }) else { return false }

        let expectedIdentifier = "capture-v14-\(sourceCommitSHA.prefix(12))"
        return buildIdentifier == expectedIdentifier
    }

    var blocker: String? {
        guard isAuthoritativeFieldBuild else {
            return "This build has no valid exact Git + reviewed Tuya dependency + canonical stationary procedure provenance. Install Capture through the repository field installer before physical evidence collection."
        }
        return nil
    }
}
