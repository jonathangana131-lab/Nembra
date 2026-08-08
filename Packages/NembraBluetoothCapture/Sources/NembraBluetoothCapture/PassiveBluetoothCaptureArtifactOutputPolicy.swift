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
    /// Publication is relative to a no-follow directory descriptor rather than a
    /// second mutable pathname resolution. The temporary report is created with
    /// O_EXCL in the exact output directory, flushed, then published with
    /// descriptor-relative rename/link operations. Protected publication uses
    /// linkat so an existing destination can never be replaced. Forced
    /// publication uses renameat only after re-proving that any existing output
    /// is not the raw input filesystem subject.
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
        let output = outputURL.standardizedFileURL
        let outputName = output.lastPathComponent
        guard !outputName.isEmpty, outputName != ".", outputName != ".." else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        let outputParent = output.deletingLastPathComponent()
        let parentFD = try openDirectoryCustody(outputParent)
        defer { _ = close(parentFD) }

        // Re-prove the source as an exact filesystem subject. For forced output,
        // an existing destination that resolves to the same inode is rejected.
        let inputIdentity = try fileIdentity(canonicalInput)
        if allowReplacingExistingOutput,
           let outputIdentity = try existingEntryIdentity(parentFD: parentFD, name: outputName),
           outputIdentity.st_dev == inputIdentity.st_dev,
           outputIdentity.st_ino == inputIdentity.st_ino {
            throw PassiveBluetoothCaptureArtifactOutputPolicyError.outputMatchesInput(
                canonicalInput.path
            )
        }

        let temporaryName = ".\(outputName).nembra-\(UUID().uuidString).tmp"
        let temporaryFD = openat(
            parentFD,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard temporaryFD >= 0 else {
            throw posixError("create derived report staging file")
        }

        var temporaryExists = true
        defer {
            _ = close(temporaryFD)
            if temporaryExists {
                _ = unlinkat(parentFD, temporaryName, 0)
            }
        }

        try writeAll(data, to: temporaryFD)
        guard fsync(temporaryFD) == 0 else {
            throw posixError("fsync derived report staging file")
        }

        var stagedMetadata = stat()
        guard fstat(temporaryFD, &stagedMetadata) == 0,
              (stagedMetadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              stagedMetadata.st_size == off_t(data.count) else {
            throw posixError("verify derived report staging file")
        }

        if allowReplacingExistingOutput {
            // This replaces only the destination directory entry. Because the
            // staged bytes are a distinct inode, renameat cannot mutate the raw
            // input inode even if another name is raced into the destination.
            guard renameat(parentFD, temporaryName, parentFD, outputName) == 0 else {
                throw posixError("publish forced derived report")
            }
            temporaryExists = false
        } else {
            // linkat is our no-replacement publish primitive: EEXIST means the
            // destination won the race and remains untouched.
            if linkat(parentFD, temporaryName, parentFD, outputName, 0) != 0 {
                if errno == EEXIST {
                    throw PassiveBluetoothCaptureArtifactOutputPolicyError.outputAlreadyExists(
                        outputURL.path
                    )
                }
                throw posixError("publish protected derived report")
            }
            guard unlinkat(parentFD, temporaryName, 0) == 0 else {
                throw posixError("remove derived report staging link")
            }
            temporaryExists = false
        }

        guard fsync(parentFD) == 0 else {
            throw posixError("fsync derived report directory")
        }
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Resolve ordinary/system symlink aliases once, then prove that the exact
    /// canonical directory subject opened component-by-component is the same
    /// inode that resolution named. This permits normal macOS `/var` ->
    /// `/private/var` ancestry while still failing closed if a mutable directory
    /// target changes between resolution and descriptor custody.
    private static func openDirectoryCustody(_ url: URL) throws -> Int32 {
        let canonical = canonicalFileURL(url)
        guard canonical.path.hasPrefix("/") else {
            throw CocoaError(.fileReadInvalidFileName)
        }

        var expectedMetadata = stat()
        guard stat(canonical.path, &expectedMetadata) == 0,
              (expectedMetadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw posixError("inspect canonical output directory")
        }

        var currentFD = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard currentFD >= 0 else {
            throw posixError("open filesystem root")
        }

        do {
            for component in canonical.pathComponents.dropFirst() where component != "/" {
                let nextFD = openat(
                    currentFD,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
                guard nextFD >= 0 else {
                    throw posixError("open output directory custody component")
                }
                _ = close(currentFD)
                currentFD = nextFD
            }

            var openedMetadata = stat()
            guard fstat(currentFD, &openedMetadata) == 0,
                  openedMetadata.st_dev == expectedMetadata.st_dev,
                  openedMetadata.st_ino == expectedMetadata.st_ino,
                  (openedMetadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw posixError("re-prove canonical output directory custody")
            }
            return currentFD
        } catch {
            _ = close(currentFD)
            throw error
        }
    }

    private static func fileIdentity(_ url: URL) throws -> stat {
        let canonical = canonicalFileURL(url)
        let parentFD = try openDirectoryCustody(canonical.deletingLastPathComponent())
        defer { _ = close(parentFD) }
        let fd = openat(parentFD, canonical.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            throw posixError("open raw capture subject")
        }
        defer { _ = close(fd) }

        var metadata = stat()
        guard fstat(fd, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw posixError("verify raw capture subject")
        }
        return metadata
    }

    private static func existingEntryIdentity(parentFD: Int32, name: String) throws -> stat? {
        var metadata = stat()
        if fstatat(parentFD, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 {
            return metadata
        }
        if errno == ENOENT {
            return nil
        }
        throw posixError("inspect existing derived report destination")
    }

    private static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = write(fd, baseAddress.advanced(by: offset), rawBuffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw posixError("write derived report staging bytes")
                }
                guard written > 0 else {
                    throw CocoaError(.fileWriteUnknown)
                }
                offset += written
            }
        }
    }

    private static func posixError(_ operation: String) -> NSError {
        let code = errno
        return NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(operation) failed: \(String(cString: strerror(code)))"]
        )
    }
}
