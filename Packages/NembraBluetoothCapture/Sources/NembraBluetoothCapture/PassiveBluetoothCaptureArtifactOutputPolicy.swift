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
/// output.
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

    /// Publishes derived report bytes while preserving the source evidence and,
    /// by default, any existing report at the destination.
    ///
    /// Foundation does not support combining `.atomic` and
    /// `.withoutOverwriting` on all supported Swift/Foundation runtimes. For
    /// protected output, write an atomic uniquely named sibling first, then use
    /// `FileManager.moveItem` to publish it. The move fails when the destination
    /// already exists instead of replacing it, closing the preflight/write race
    /// without relying on the unsupported option combination.
    public static func writeDerivedReport(
        _ data: Data,
        inputURL: URL,
        outputURL: URL,
        allowReplacingExistingOutput: Bool,
        fileManager: FileManager = .default
    ) throws {
        try validate(
            inputURL: inputURL,
            outputURL: outputURL,
            allowReplacingExistingOutput: allowReplacingExistingOutput,
            fileManager: fileManager
        )

        if allowReplacingExistingOutput {
            try data.write(to: outputURL, options: [.atomic])
            return
        }

        let temporaryURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(outputURL.lastPathComponent).nembra-\(UUID().uuidString).tmp"
            )
        var shouldRemoveTemporary = true
        defer {
            if shouldRemoveTemporary {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try data.write(to: temporaryURL, options: [.atomic])

        do {
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
            shouldRemoveTemporary = false
        } catch {
            if fileManager.fileExists(atPath: outputURL.path) {
                throw PassiveBluetoothCaptureArtifactOutputPolicyError.outputAlreadyExists(
                    outputURL.path
                )
            }
            throw error
        }
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
