import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum PassiveBluetoothCaptureArtifactOutputPolicyError: Error, Equatable, Sendable {
    case outputMatchesInput(String)
    case outputAlreadyExists(String)
    case inputSourceChangedSinceAdmission(String)
}

extension PassiveBluetoothCaptureArtifactOutputPolicyError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .outputMatchesInput(path):
            "refusing to overwrite the raw capture artifact with its derived report: \(path)"
        case let .outputAlreadyExists(path):
            "output already exists; choose another path or pass --force-output: \(path)"
        case let .inputSourceChangedSinceAdmission(path):
            "raw capture path no longer names the exact filesystem subject admitted for analysis: \(path)"
        }
    }
}

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

    /// Publishes a report only while the raw input pathname still names the exact
    /// filesystem subject that supplied `inputReceipt.bytes`.
    ///
    /// This receipt closes the read -> analyze -> publish custody boundary. Output
    /// protection is therefore anchored to the admitted source inode, not to a
    /// later untrusted reinterpretation of the input pathname.
    public static func writeDerivedReport(
        _ data: Data,
        inputURL: URL,
        inputReceipt: PassiveBluetoothCaptureArtifactInputReceipt,
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

        let currentInputIdentity = try fileIdentity(canonicalInput)
        guard currentInputIdentity == inputReceipt.admittedSourceIdentity else {
            throw PassiveBluetoothCaptureArtifactOutputPolicyError
                .inputSourceChangedSinceAdmission(canonicalInput.path)
        }

        if allowReplacingExistingOutput,
           let outputIdentity = try existingEntryIdentity(parentFD: parentFD, name: outputName),
           sameFilesystemSubject(outputIdentity, inputReceipt.admittedSourceIdentity) {
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

        // Re-prove the admitted source again immediately before publication so a
        // pathname swap during report staging cannot change the protected subject.
        guard try fileIdentity(canonicalInput) == inputReceipt.admittedSourceIdentity else {
            throw PassiveBluetoothCaptureArtifactOutputPolicyError
                .inputSourceChangedSinceAdmission(canonicalInput.path)
        }

        if allowReplacingExistingOutput {
            if let outputIdentity = try existingEntryIdentity(parentFD: parentFD, name: outputName),
               sameFilesystemSubject(outputIdentity, inputReceipt.admittedSourceIdentity) {
                throw PassiveBluetoothCaptureArtifactOutputPolicyError.outputMatchesInput(
                    canonicalInput.path
                )
            }
            guard renameat(parentFD, temporaryName, parentFD, outputName) == 0 else {
                throw posixError("publish forced derived report")
            }
            temporaryExists = false
        } else {
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

    /// Package-internal compatibility helper for focused policy tests. Production
    /// callers outside this module must carry the admission receipt explicitly.
    static func writeDerivedReport(
        _ data: Data,
        inputURL: URL,
        outputURL: URL,
        allowReplacingExistingOutput: Bool,
        fileManager: FileManager = .default
    ) throws {
        let inputReceipt = try PassiveBluetoothCaptureArtifactInputPolicy.readExactArtifact(
            at: inputURL
        )
        try writeDerivedReport(
            data,
            inputURL: inputURL,
            inputReceipt: inputReceipt,
            outputURL: outputURL,
            allowReplacingExistingOutput: allowReplacingExistingOutput,
            fileManager: fileManager
        )
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

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

    private static func fileIdentity(
        _ url: URL
    ) throws -> PassiveBluetoothCaptureArtifactSourceIdentity {
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
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              metadata.st_size >= 0 else {
            throw posixError("verify raw capture subject")
        }
        return sourceIdentity(metadata)
    }

    private static func sourceIdentity(
        _ metadata: stat
    ) -> PassiveBluetoothCaptureArtifactSourceIdentity {
        #if canImport(Darwin)
        let modifiedSeconds = Int64(metadata.st_mtimespec.tv_sec)
        let modifiedNanoseconds = Int64(metadata.st_mtimespec.tv_nsec)
        let changedSeconds = Int64(metadata.st_ctimespec.tv_sec)
        let changedNanoseconds = Int64(metadata.st_ctimespec.tv_nsec)
        #else
        let modifiedSeconds = Int64(metadata.st_mtim.tv_sec)
        let modifiedNanoseconds = Int64(metadata.st_mtim.tv_nsec)
        let changedSeconds = Int64(metadata.st_ctim.tv_sec)
        let changedNanoseconds = Int64(metadata.st_ctim.tv_nsec)
        #endif

        return PassiveBluetoothCaptureArtifactSourceIdentity(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            mode: UInt64(metadata.st_mode),
            ownerUser: UInt64(metadata.st_uid),
            ownerGroup: UInt64(metadata.st_gid),
            byteCount: Int64(metadata.st_size),
            modifiedSeconds: modifiedSeconds,
            modifiedNanoseconds: modifiedNanoseconds,
            changedSeconds: changedSeconds,
            changedNanoseconds: changedNanoseconds
        )
    }

    private static func sameFilesystemSubject(
        _ metadata: stat,
        _ sourceIdentity: PassiveBluetoothCaptureArtifactSourceIdentity
    ) -> Bool {
        UInt64(metadata.st_dev) == sourceIdentity.device &&
            UInt64(metadata.st_ino) == sourceIdentity.inode
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
