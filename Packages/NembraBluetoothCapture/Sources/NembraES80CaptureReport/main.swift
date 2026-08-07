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
    }

    private enum CommandError: Error, CustomStringConvertible {
        case missingInput
        case unexpectedArgument(String)
        case missingOptionValue(String)
        case invalidPositiveInteger(option: String, value: String)
        case emptyPeripheralIdentifier
        case noAttributablePeripheral
        case ambiguousPeripherals([String])
        case requestedPeripheralNotPresent(requested: String, available: [String])

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
            case .noAttributablePeripheral:
                "capture contains no target-attributable connection/GATT/value peripheral evidence"
            case let .ambiguousPeripherals(identifiers):
                "capture contains multiple attributable peripherals; pass --peripheral with one exact identifier: \(identifiers.joined(separator: ", "))"
            case let .requestedPeripheralNotPresent(requested, available):
                "requested peripheral \(requested) is not present in target-attributable capture evidence; available: \(available.joined(separator: ", "))"
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
        let artifactData = try Data(contentsOf: options.inputURL)
        let session = try PassiveBluetoothCaptureJSON.decode(artifactData)
        let attributablePeripherals = PassiveBluetoothTuyaCaptureReportBuilder
            .attributablePeripheralIdentifiers(in: session)
        let selectedPeripheral = try selectPeripheral(
            requested: options.peripheralIdentifier,
            available: attributablePeripherals
        )
        let policy = try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: options.maximumMessageBytes,
            maximumFragmentCount: options.maximumFragmentCount
        )
        let report = try PassiveBluetoothTuyaCaptureReportBuilder.make(
            session: session,
            peripheralIdentifier: selectedPeripheral,
            policy: policy
        )
        let reportData = try report.jsonData(prettyPrinted: options.prettyPrinted)

        if let outputURL = options.outputURL {
            try reportData.write(to: outputURL, options: .atomic)
            writeStderr(
                "wrote framing-candidate report for \(selectedPeripheral) to \(outputURL.path)"
            )
        } else {
            FileHandle.standardOutput.write(reportData)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func selectPeripheral(
        requested: String?,
        available: [String]
    ) throws -> String {
        if let requested {
            guard available.contains(requested) else {
                throw CommandError.requestedPeripheralNotPresent(
                    requested: requested,
                    available: available
                )
            }
            return requested
        }

        switch available.count {
        case 0:
            throw CommandError.noAttributablePeripheral
        case 1:
            return available[0]
        default:
            throw CommandError.ambiguousPeripherals(available)
        }
    }

    private static func parseOptions(_ arguments: [String]) throws -> Options {
        var inputPath: String?
        var outputPath: String?
        var peripheralIdentifier: String?
        var maximumMessageBytes = defaultMaximumMessageBytes
        var maximumFragmentCount = defaultMaximumFragmentCount
        var prettyPrinted = true
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
                peripheralIdentifier = value

            case "--max-message-bytes":
                let value = try nextValue(arguments, index: &index, option: argument)
                maximumMessageBytes = try positiveInteger(value, option: argument)

            case "--max-fragments":
                let value = try nextValue(arguments, index: &index, option: argument)
                maximumFragmentCount = try positiveInteger(value, option: argument)

            case "--compact":
                prettyPrinted = false

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
            outputURL: outputPath.map(URL.init(fileURLWithPath:)),
            peripheralIdentifier: peripheralIdentifier,
            maximumMessageBytes: maximumMessageBytes,
            maximumFragmentCount: maximumFragmentCount,
            prettyPrinted: prettyPrinted
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
      --max-message-bytes <n>    Offline analysis ceiling (default: 65536).
      --max-fragments <n>        Offline analysis ceiling (default: 256).
      --compact                  Emit compact sorted-key JSON.
      --help, -h                 Show this help.

    Truth boundary:
      The output is PUBLIC-FAMILY FRAMING-CANDIDATE RESEARCH ONLY. It does not
      verify that the physical AOVOPRO ES80 uses this Tuya family and does not
      assign DP IDs, battery, voltage, current, watts, speed, throttle, regen,
      authentication, command authorization, or acknowledgement semantics.
    """
}
