import Foundation

/// Exact source/build provenance for a physical Nembra Capture artifact.
///
/// A field artifact is authoritative only when both the human-readable build label
/// and the full Git commit SHA were stamped into the built product. This type is
/// deliberately independent of Bundle so package tests can exercise the fail-closed
/// validation contract without an app host.
public struct CaptureFieldBuildIdentity: Codable, Equatable, Sendable {
    public static let buildIdentifierInfoKey = "NembraCaptureBuildIdentifier"
    public static let commitSHAInfoKey = "NembraCaptureBuildCommitSHA"

    public let buildIdentifier: String
    public let commitSHA: String

    public init?(buildIdentifier: String?, commitSHA: String?) {
        guard let buildIdentifier = Self.normalizedBuildIdentifier(buildIdentifier),
              let commitSHA = Self.normalizedCommitSHA(commitSHA) else {
            return nil
        }
        self.buildIdentifier = buildIdentifier
        self.commitSHA = commitSHA
    }

    public static func from(infoDictionary: [String: Any]) -> CaptureFieldBuildIdentity? {
        CaptureFieldBuildIdentity(
            buildIdentifier: infoDictionary[buildIdentifierInfoKey] as? String,
            commitSHA: infoDictionary[commitSHAInfoKey] as? String
        )
    }

    public var shortCommitSHA: String {
        String(commitSHA.prefix(12))
    }

    private static func normalizedBuildIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.localizedCaseInsensitiveContains("unstamped"),
              !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }

    private static func normalizedCommitSHA(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count == 40,
              normalized.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.value {
                  case 48...57, 97...102:
                      true
                  default:
                      false
                  }
              }) else {
            return nil
        }
        return normalized
    }
}
