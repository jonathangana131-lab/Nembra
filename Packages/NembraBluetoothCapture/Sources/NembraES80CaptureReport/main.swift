import Foundation
import NembraBluetoothCapture
import NembraCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct NembraES80CaptureReportCommand {
    /// Offline resource ceilings only. These are intentionally generous process
    /// safety bounds, not ES80 protocol/message-size/fragment-count claims.
    private static let defaultMaximumMessageBytes = 65_536
    private static let defaultMaximumFragmentCount = 256

    private struct Options {
        let inputURL: URL
        let outputURL: URL?
        let peripheralIdentifier: String?
        let maximumMessageBytes: Int
        let maximumFragmentCount: Int
        let prettyPrinted: Bool
        let forceOutput: Bool
    }

    private enum CommandError: Error, CustomStringConvertible {
        case missingInput
        case unexpectedArgument(String)
        case missingOptionValue(String)
        case invalidPositiveInteger(option: String, value: String)
        case emptyPeripheralIdentifier

        var description: String {
            switch self {
            case .missingInput:
                "missing capture JSON path"
            case let .unexpectedArgument(argument):
                "unexpected argument: \(argument)"
            case let .missingOptionValue(option):
                "missing value for \(option)"
            case let .invalidPositiveInteger(option, value):
                "\(option) requires a positive integer, got: \(value)"
            case .emptyPeripheralIdentifier:
                "--peripheral requires a non-empty exact peripheral identifier"
            }
        }
    }

    static func main() {
        do {
            if CommandLine.arguments.dropFirst().contains("--help") ||
                CommandLine.arguments.dropFirst().contains("-h") {
                writeStdout(usage)
                return
            }

            let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
            try run(options)
        } catch {
            writeStderr("error: \(error)\n\n\(usage)")
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ options: Options) throws {
        let artifactData = try Data(contentsOf: options.inputURL, options: [.mappedIfSafe])
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: options.maximumMessageBytes,
            maximumFragmentCount: options.maximumFragmentCount
        )
        let artifactReport = try PassiveBluetoothTuyaCaptureArtifactReportBuilder.make(
            captureJSON: artifactData,
            peripheralIdentifier: options.peripheralIdentifier,
            policy: policy
        )
        let reportData = try artifactReport.jsonData(prettyPrinted: options.prettyPrinted)

        if let outputURL = options.outputURL {
            try PassiveBluetoothCaptureArtifactOutputPolicy.validate(
                inputURL: options.inputURL,
                outputURL: outputURL,
                allowReplacingExistingOutput: options.forceOutput
            )
            let writeOptions: Data.WritingOptions = options.forceOutput
                ? [.atomic]
                : [.atomic, .withoutOverwriting]
            try reportData.write(to: outputURL, options: writeOptions)
            writeStderr(
                "wrote framing-candidate report for " +
                "\(artifactReport.analysis.capture.peripheralIdentifier) to \(outputURL.path) " +
                "(source sha256 \(artifactReport.sourceArtifact.sha256))"
            )
        } else {
            FileHandle.standardOutput.write(reportData)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func parseOptions(_ arguments: [String]) throws -> Options {
        var inputPath: String?
        var outputPath: String?
        var peripheralIdentifier: String?
        var maximumMessageBytes = defaultMaximumMessageBytes
        var maximumFragmentCount = defaultMaximumFragmentCount
        var prettyPrinted = true
        var forceOutput = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--output", "-o":
                let value = try nextValue(arguments, index: &index, option: argument)
                outputPath = value

            case "--peripheral":
                let value = try nextValue(arguments, index: &index, option: argument)
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw CommandError.emptyPeripheralIdentifier
                }
                peripheralIdentifier = trimmed

            case "--max-message-bytes":
                let value = try nextValue(arguments, index: &index, option: argument)
                maximumMessageBytes = try positiveInteger(value, option: argument)

            case "--max-fragments":
                let value = try nextValue(arguments, index: &index, option: argument)
                maximumFragmentCount = try positiveInteger(value, option: argument)

            case "--compact":
                prettyPrinted = false

            case "--force-output":
                forceOutput = true

            default:
                if argument.hasPrefix("-") || inputPath != nil {
                    throw CommandError.unexpectedArgument(argument)
                }
                inputPath = argument
            }
            index += 1
        }

        guard let inputPath else {
            throw CommandError.missingInput
        }

        return Options(
            inputURL: URL(fileURLWithPath: inputPath),
            outputURL: outputPath.map { URL(fileURLWithPath: $0) },
            peripheralIdentifier: peripheralIdentifier,
            maximumMessageBytes: maximumMessageBytes,
            maximumFragmentCount: maximumFragmentCount,
            prettyPrinted: prettyPrinted,
            forceOutput: forceOutput
        )
    }

    private static func nextValue(
        _ arguments: [String],
        index: inout Int,
        option: String
    ) throws -> String {
        let valueIndex = index + 1
        guard arguments.indices.contains(valueIndex) else {
            throw CommandError.missingOptionValue(option)
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func positiveInteger(_ value: String, option: String) throws -> Int {
        guard let parsed = Int(value), parsed > 0 else {
            throw CommandError.invalidPositiveInteger(option: option, value: value)
        }
        return parsed
    }

    private static func writeStdout(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    private static func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    private static let usage = """
    Nembra ES80 passive-capture framing report

    Usage:
      nembra-es80-capture-report <capture.json> [options]

    Options:
      --peripheral <id>          Exact captured peripheral identifier. Omit only
                                 when target-attributable evidence names one unique peripheral.
      --output, -o <report.json> Write report atomically to a file instead of stdout.
                                 Existing files are protected by default.
      --force-output             Replace an existing derived report. This never permits
                                 the output path to equal the raw capture input path.
      --max-message-bytes <n>    Offline analysis ceiling (default: 65536).
      --max-fragments <n>        Offline analysis ceiling (default: 256).
      --compact                  Emit compact sorted-key JSON.
      --help, -h                 Show this help.

    Provenance:
      Every report includes the exact source capture artifact byte count and
      lowercase SHA-256 digest so analysis can be traced back to the precise JSON
      bytes that were decoded. The digest identifies the artifact; it does not
      authenticate the scooter, recorder, or person who produced the capture.

    Evidence preservation:
      The command refuses to overwrite its source capture even with --force-output.
      Existing derived reports are also protected unless --force-output is explicit.

    Truth boundary:
      The output is PUBLIC-FAMILY FRAMING-CANDIDATE RESEARCH ONLY. It does not
      verify that the physical AOVOPRO ES80 uses this Tuya family and does not
      assign DP IDs, battery, voltage, current, watts, speed, throttle, regen,
      authentication, command authorization, or acknowledgement semantics.
    """
}
