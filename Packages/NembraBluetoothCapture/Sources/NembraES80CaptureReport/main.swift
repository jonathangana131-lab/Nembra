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
        let maximumArtifactBytes: Int
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
        case forceOutputRequiresOutput

        var description: String {
            switch self {
            case .missingInput:
                "missing Nembra Capture final Share JSON path"
            case let .unexpectedArgument(argument):
                "unexpected argument: \(argument)"
            case let .missingOptionValue(option):
                "missing value for \(option)"
            case let .invalidPositiveInteger(option, value):
                "\(option) requires a positive integer, got: \(value)"
            case .forceOutputRequiresOutput:
                "--force-output is valid only together with --output or -o"
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
        if let outputURL = options.outputURL {
            try PassiveBluetoothCaptureArtifactOutputPolicy.validate(
                inputURL: options.inputURL,
                outputURL: outputURL,
                allowReplacingExistingOutput: options.forceOutput
            )
        }

        // Bound the actual final Share file before whole-file JSON decode.
        let finalShareData = try PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes(
            at: options.inputURL,
            maximumBytes: options.maximumArtifactBytes
        )
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: options.maximumMessageBytes,
            maximumFragmentCount: options.maximumFragmentCount
        )
        let artifactReport = try PassiveBluetoothTuyaCaptureArtifactReportBuilder.make(
            finalShareJSON: finalShareData,
            policy: policy,
            maximumArtifactBytes: options.maximumArtifactBytes
        )
        let reportData = try artifactReport.jsonData(prettyPrinted: options.prettyPrinted)

        if let outputURL = options.outputURL {
            try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
                reportData,
                inputURL: options.inputURL,
                outputURL: outputURL,
                allowReplacingExistingOutput: options.forceOutput
            )

            let summary = artifactReport.analysis.outcomeSummary
            writeStderr(
                "wrote framing-candidate report for " +
                "\(artifactReport.analysis.capture.peripheralIdentifier) to \(outputURL.path) " +
                "(final Share sha256 \(artifactReport.sourceArtifact.finalShareSHA256))\n" +
                "candidate outcomes: completed=\(summary.completedCandidateCount) " +
                "rejected=\(summary.rejectedCandidateCount) " +
                "incomplete=\(summary.incompleteCandidateCount) " +
                "unexpected_failures=\(summary.unexpectedAnalyzerFailureCount) " +
                "streams=\(summary.streamCount) fragments=\(summary.fragmentCount)"
            )
        } else {
            FileHandle.standardOutput.write(reportData)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func parseOptions(_ arguments: [String]) throws -> Options {
        var inputPath: String?
        var outputPath: String?
        var maximumArtifactBytes = PassiveBluetoothCaptureArtifactInputPolicy
            .defaultMaximumArtifactBytes
        var maximumMessageBytes = defaultMaximumMessageBytes
        var maximumFragmentCount = defaultMaximumFragmentCount
        var prettyPrinted = true
        var forceOutput = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--output", "-o":
                outputPath = try nextValue(arguments, index: &index, option: argument)

            case "--max-artifact-bytes":
                let value = try nextValue(arguments, index: &index, option: argument)
                maximumArtifactBytes = try positiveInteger(value, option: argument)

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
        guard !forceOutput || outputPath != nil else {
            throw CommandError.forceOutputRequiresOutput
        }

        return Options(
            inputURL: URL(fileURLWithPath: inputPath),
            outputURL: outputPath.map { URL(fileURLWithPath: $0) },
            maximumArtifactBytes: maximumArtifactBytes,
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
        guard arguments.indices.contains(valueIndex),
              !arguments[valueIndex].hasPrefix("-") else {
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
      nembra-es80-capture-report <Nembra-ES80-Fingerprint-....json> [options]

    Input:
      Pass the exact file produced by Nembra Capture's SHARE CAPTURE action.
      The tool verifies the final Share envelope, its exact nested SoftwareExport,
      capture/manifest binding, correlation/build/recipe rendezvous, and then uses
      the manifest's already-verified selected peripheral. Do not extract nested
      JSON and do not type a Bluetooth UUID manually.

    Options:
      --output, -o <report.json> Write report to a file. Existing files are protected
                                 by default; publication is non-replacing. File-output
                                 runs also print candidate outcome counts to stderr.
      --force-output             Replace an existing derived report. Requires --output
                                 and never permits replacing the Nembra Share input path.
      --max-artifact-bytes <n>   Offline final-Share file/decode ceiling (default: 67108864).
                                 This is process safety, not an ES80 capture/protocol limit.
      --max-message-bytes <n>    Offline framing-analysis ceiling (default: 65536).
      --max-fragments <n>        Offline framing-analysis ceiling (default: 256).
      --compact                  Emit compact sorted-key JSON.
      --help, -h                 Show this help.

    Provenance:
      Every report binds the exact final Share SHA-256 and byte count to its
      verified nested SoftwareExport SHA-256, immutable capture SHA-256, experiment,
      recipe, procedure, build instance, and source commit. These are software
      provenance facts; they do not authenticate the physical scooter.

    Resource safety:
      Final Share bytes are read under --max-artifact-bytes before JSON decode.
      Message/fragment ceilings apply later to framing-candidate analysis. These
      are operator-tool resource limits, never claims about physical ES80 packet,
      session, message, or capture maxima.

    Outcome counts:
      completed/rejected/incomplete values describe bounded framing-candidate
      analyzer outcomes only. A completed candidate is not a verified ES80 message.

    Evidence preservation:
      The command refuses to overwrite its source Share even with --force-output.
      Existing derived reports are also protected unless --force-output is explicit.

    Truth boundary:
      The output is PUBLIC-FAMILY FRAMING-CANDIDATE RESEARCH ONLY. It does not
      verify that the physical AOVOPRO ES80 uses this Tuya family and does not
      assign DP IDs, battery, voltage, current, watts, speed, throttle, regen,
      authentication, command authorization, or acknowledgement semantics.
    """
}
