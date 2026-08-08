import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
    /// Publication authority is bound to stable filesystem subjects rather than
    /// re-resolving the destination pathname after validation. The source is held
    /// open while the output parent directory is pinned by descriptor. A hard-link
    /// alias of the source is rejected by device/inode identity. Temporary report
    /// bytes are written through `openat(... O_NOFOLLOW | O_EXCL ...)` in that
    /// pinned directory. Protected publication uses `linkat` so a destination that
    /// appears after preflight cannot be replaced. Explicit force uses `renameat`
    /// only inside the same already-open directory after re-checking that the
    /// current destination subject is not the held source subject.
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

        let canonicalInput = canonicalFileURL(inputURL)
        let outputParent = canonicalFileURL(outputURL.deletingLastPathComponent())
        let outputName = outputURL.lastPathComponent
        guard !outputName.isEmpty,
              outputName != ".",
              outputName != "..",
              !outputName.contains("/") else {
            throw posixError(
                operation: "validate output filename",
                path: outputURL.path,
                code: EINVAL
            )
        }

        let sourceDescriptor = try openFileDescriptor(
            path: canonicalInput.path,
            flags: O_RDONLY | O_NOFOLLOW | O_CLOEXEC,
            operation: "open raw capture source"
        )
        defer { _ = close(sourceDescriptor) }

        var sourceMetadata = stat()
        guard fstat(sourceDescriptor, &sourceMetadata) == 0 else {
            throw posixError(
                operation: "inspect raw capture source",
                path: canonicalInput.path
            )
        }
        guard (sourceMetadata.st_mode & S_IFMT) == S_IFREG else {
            throw posixError(
                operation: "require regular raw capture source",
                path: canonicalInput.path,
                code: EINVAL
            )
        }

        let outputDirectoryDescriptor = try openFileDescriptor(
            path: outputParent.path,
            flags: O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
            operation: "open derived-report output directory"
        )
        defer { _ = close(outputDirectoryDescriptor) }

        try rejectDestinationIfItMatchesSource(
            parentDescriptor: outputDirectoryDescriptor,
            outputName: outputName,
            sourceMetadata: sourceMetadata,
            sourcePath: canonicalInput.path
        )

        if !allowReplacingExistingOutput,
           try destinationMetadata(
               parentDescriptor: outputDirectoryDescriptor,
               outputName: outputName
           ) != nil {
            throw PassiveBluetoothCaptureArtifactOutputPolicyError.outputAlreadyExists(
                outputURL.path
            )
        }

        let temporaryName = ".\(outputName).nembra-\(UUID().uuidString).tmp"
        let temporaryDescriptor = try openRelativeFileDescriptor(
            parentDescriptor: outputDirectoryDescriptor,
            name: temporaryName,
            flags: O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode: 0o600,
            operation: "create derived-report staging file",
            displayPath: outputParent.appendingPathComponent(temporaryName).path
        )
        var stagingNameStillExists = true
        defer {
            _ = close(temporaryDescriptor)
            if stagingNameStillExists {
                temporaryName.withCString { namePointer in
                    _ = unlinkat(outputDirectoryDescriptor, namePointer, 0)
                }
            }
        }

        try writeAll(
            data,
            to: temporaryDescriptor,
            displayPath: outputParent.appendingPathComponent(temporaryName).path
        )
        guard fsync(temporaryDescriptor) == 0 else {
            throw posixError(
                operation: "sync derived-report staging file",
                path: outputParent.appendingPathComponent(temporaryName).path
            )
        }

        if allowReplacingExistingOutput {
            // Re-prove the destination immediately before the descriptor-relative
            // replacement. The parent directory itself cannot be retargeted after
            // this point because publication is relative to its open descriptor.
            try rejectDestinationIfItMatchesSource(
                parentDescriptor: outputDirectoryDescriptor,
                outputName: outputName,
                sourceMetadata: sourceMetadata,
                sourcePath: canonicalInput.path
            )

            let renameResult = temporaryName.withCString { temporaryPointer in
                outputName.withCString { outputPointer in
                    renameat(
                        outputDirectoryDescriptor,
                        temporaryPointer,
                        outputDirectoryDescriptor,
                        outputPointer
                    )
                }
            }
            guard renameResult == 0 else {
                throw posixError(
                    operation: "publish replacement derived report",
                    path: outputURL.path
                )
            }
            stagingNameStillExists = false
            return
        }

        let linkResult = temporaryName.withCString { temporaryPointer in
            outputName.withCString { outputPointer in
                linkat(
                    outputDirectoryDescriptor,
                    temporaryPointer,
                    outputDirectoryDescriptor,
                    outputPointer,
                    0
                )
            }
        }
        guard linkResult == 0 else {
            let code = errno
            if code == EEXIST {
                throw PassiveBluetoothCaptureArtifactOutputPolicyError.outputAlreadyExists(
                    outputURL.path
                )
            }
            throw posixError(
                operation: "publish protected derived report",
                path: outputURL.path,
                code: code
            )
        }

        let unlinkResult = temporaryName.withCString { temporaryPointer in
            unlinkat(outputDirectoryDescriptor, temporaryPointer, 0)
        }
        guard unlinkResult == 0 else {
            throw posixError(
                operation: "remove derived-report staging link",
                path: outputParent.appendingPathComponent(temporaryName).path
            )
        }
        stagingNameStillExists = false
    }

    private static func rejectDestinationIfItMatchesSource(
        parentDescriptor: Int32,
        outputName: String,
        sourceMetadata: stat,
        sourcePath: String
    ) throws {
        guard let outputMetadata = try destinationMetadata(
            parentDescriptor: parentDescriptor,
            outputName: outputName
        ) else {
            return
        }

        if sourceMetadata.st_dev == outputMetadata.st_dev,
           sourceMetadata.st_ino == outputMetadata.st_ino {
            throw PassiveBluetoothCaptureArtifactOutputPolicyError.outputMatchesInput(
                sourcePath
            )
        }
    }

    private static func destinationMetadata(
        parentDescriptor: Int32,
        outputName: String
    ) throws -> stat? {
        var metadata = stat()
        let result = outputName.withCString { outputPointer in
            fstatat(
                parentDescriptor,
                outputPointer,
                &metadata,
                AT_SYMLINK_NOFOLLOW
            )
        }
        if result == 0 {
            return metadata
        }

        let code = errno
        if code == ENOENT {
            return nil
        }
        throw posixError(
            operation: "inspect derived-report destination",
            path: outputName,
            code: code
        )
    }

    private static func openFileDescriptor(
        path: String,
        flags: Int32,
        operation: String
    ) throws -> Int32 {
        let descriptor = path.withCString { pointer in
            open(pointer, flags)
        }
        guard descriptor >= 0 else {
            throw posixError(operation: operation, path: path)
        }
        return descriptor
    }

    private static func openRelativeFileDescriptor(
        parentDescriptor: Int32,
        name: String,
        flags: Int32,
        mode: mode_t,
        operation: String,
        displayPath: String
    ) throws -> Int32 {
        let descriptor = name.withCString { pointer in
            openat(parentDescriptor, pointer, flags, mode)
        }
        guard descriptor >= 0 else {
            throw posixError(operation: operation, path: displayPath)
        }
        return descriptor
    }

    private static func writeAll(
        _ data: Data,
        to descriptor: Int32,
        displayPath: String
    ) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if written < 0 {
                    let code = errno
                    if code == EINTR {
                        continue
                    }
                    throw posixError(
                        operation: "write derived-report staging file",
                        path: displayPath,
                        code: code
                    )
                }
                guard written > 0 else {
                    throw posixError(
                        operation: "write derived-report staging file",
                        path: displayPath,
                        code: EIO
                    )
                }
                offset += written
            }
        }
    }

    private static func posixError(
        operation: String,
        path: String,
        code: Int32 = errno
    ) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [
                NSLocalizedDescriptionKey: "\(operation) failed for \(path) (errno \(code))"
            ]
        )
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
