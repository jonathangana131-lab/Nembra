import Foundation

public enum PassiveBluetoothCaptureArtifactOutputPolicyError: Error, Equatable, Sendable {
    case outputMatchesInput(String)
    case outputAlreadyExists(String)
}

extension PassiveBluetoothCaptureArtifactOutputPolicyError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .outputMatchesInput(path):
            "refusing to overwrite the raw capture artifact with its derived report: \(path)"
        case let .outputAlreadyExists(path):
            "output already exists; choose another path or pass --force-output: \(path)"
        }
    }
}

/// Evidence-preservation policy for derived offline reports.
///
/// A derived report must never replace its source capture, even when explicit
/// replacement of an existing report is requested. Existing derived reports are
/// also protected by default so repeated analysis does not silently erase prior
/// output. The final write should still use Foundation's `.withoutOverwriting`
/// option when replacement is disabled to close the check/write race.
public enum PassiveBluetoothCaptureArtifactOutputPolicy {
    public static func validate(
        inputURL: URL,
        outputURL: URL,
        allowReplacingExistingOutput: Bool,
        fileManager: FileManager = .default
    ) throws {
        let canonicalInput = canonicalFileURL(inputURL)
        let canonicalOutput = canonicalFileURL(outputURL)

        guard canonicalInput != canonicalOutput else {
            throw PassiveBluetoothCaptureArtifactOutputPolicyError.outputMatchesInput(
                canonicalInput.path
            )
        }

        if !allowReplacingExistingOutput,
           fileManager.fileExists(atPath: outputURL.path) {
            throw PassiveBluetoothCaptureArtifactOutputPolicyError.outputAlreadyExists(
                outputURL.path
            )
        }
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
