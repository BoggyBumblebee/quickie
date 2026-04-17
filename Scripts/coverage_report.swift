#!/usr/bin/env swift

import Darwin
import Foundation

struct CoverageLine: Decodable {
    let line: Int
    let isExecutable: Bool
    let executionCount: Int?
}

struct FileCoverage {
    let executableLines: Int
    let coveredLines: Int
    let lines: [Int: Bool]
}

struct Options {
    let xcresultPath: String
    let repoRoot: URL
    let exclusionsFile: URL
    let overallThreshold: Double
    let changedThreshold: Double
    let diffBase: String?
    let sonarXMLPath: URL?
}

enum CoverageError: Error, LocalizedError {
    case missingValue(String)
    case invalidArgument(String)
    case commandFailed(String, Int32, String)
    case missingPath(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            "Missing value for \(flag)."
        case .invalidArgument(let message):
            message
        case .commandFailed(let command, let status, let output):
            "Command failed (\(status)): \(command)\n\(output)"
        case .missingPath(let path):
            "Expected path was not found: \(path)"
        }
    }
}

func parseOptions(arguments: [String]) throws -> Options {
    var xcresultPath: String?
    var repoRootPath: String?
    var exclusionsPath: String?
    var overallThreshold = 80.0
    var changedThreshold = 80.0
    var diffBase: String?
    var sonarXMLPath: String?

    var index = 1
    while index < arguments.count {
        let argument = arguments[index]
        let nextValue: () throws -> String = {
            guard index + 1 < arguments.count else {
                throw CoverageError.missingValue(argument)
            }
            index += 1
            return arguments[index]
        }

        switch argument {
        case "--xcresult":
            xcresultPath = try nextValue()
        case "--repo-root":
            repoRootPath = try nextValue()
        case "--exclusions-file":
            exclusionsPath = try nextValue()
        case "--overall-threshold":
            overallThreshold = Double(try nextValue()) ?? overallThreshold
        case "--changed-threshold":
            changedThreshold = Double(try nextValue()) ?? changedThreshold
        case "--diff-base":
            diffBase = try nextValue()
        case "--sonar-xml":
            sonarXMLPath = try nextValue()
        default:
            throw CoverageError.invalidArgument("Unknown argument: \(argument)")
        }

        index += 1
    }

    guard let xcresultPath else {
        throw CoverageError.invalidArgument("Missing required argument: --xcresult")
    }
    guard let repoRootPath else {
        throw CoverageError.invalidArgument("Missing required argument: --repo-root")
    }
    guard let exclusionsPath else {
        throw CoverageError.invalidArgument("Missing required argument: --exclusions-file")
    }

    let repoRoot = URL(fileURLWithPath: repoRootPath).standardizedFileURL
    let exclusionsFile = URL(fileURLWithPath: exclusionsPath).standardizedFileURL
    let sonarURL = sonarXMLPath.map { URL(fileURLWithPath: $0).standardizedFileURL }

    return Options(
        xcresultPath: xcresultPath,
        repoRoot: repoRoot,
        exclusionsFile: exclusionsFile,
        overallThreshold: overallThreshold,
        changedThreshold: changedThreshold,
        diffBase: diffBase,
        sonarXMLPath: sonarURL
    )
}

@discardableResult
func runCommand(_ command: [String], currentDirectory: URL? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command
    process.currentDirectoryURL = currentDirectory

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
    let stdoutText = String(decoding: stdoutData, as: UTF8.self)
    let stderrText = String(decoding: stderrData, as: UTF8.self)

    guard process.terminationStatus == 0 else {
        throw CoverageError.commandFailed(command.joined(separator: " "), process.terminationStatus, stdoutText + stderrText)
    }

    return stdoutText
}

func loadExclusions(from url: URL) throws -> Set<String> {
    let contents = try String(contentsOf: url, encoding: .utf8)
    return Set(
        contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    )
}

func relativePath(for absolutePath: String, repoRoot: URL) -> String? {
    let absoluteURL = URL(fileURLWithPath: absolutePath).standardizedFileURL
    let repoPath = repoRoot.path.hasSuffix("/") ? repoRoot.path : repoRoot.path + "/"

    guard absoluteURL.path.hasPrefix(repoPath) else {
        return nil
    }

    return String(absoluteURL.path.dropFirst(repoPath.count))
}

func loadCoverage(for absolutePath: String, xcresultPath: String) throws -> FileCoverage {
    let output = try runCommand([
        "xcrun", "xccov", "view", "--archive", "--file", absolutePath, "--json", xcresultPath
    ])

    let data = Data(output.utf8)
    let decoded = try JSONDecoder().decode([String: [CoverageLine]].self, from: data)
    let lines = decoded[absolutePath] ?? []

    var executable = 0
    var covered = 0
    var mappedLines: [Int: Bool] = [:]

    for line in lines where line.isExecutable {
        executable += 1
        let isCovered = (line.executionCount ?? 0) > 0
        if isCovered {
            covered += 1
        }
        mappedLines[line.line] = isCovered
    }

    return FileCoverage(executableLines: executable, coveredLines: covered, lines: mappedLines)
}

func parseChangedLines(diffText: String) -> [String: Set<Int>] {
    var changedLines: [String: Set<Int>] = [:]
    var currentFile: String?

    let hunkPattern = try! NSRegularExpression(pattern: #"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@"#)

    for rawLine in diffText.split(whereSeparator: \.isNewline) {
        let line = String(rawLine)

        if line.hasPrefix("+++ b/") {
            currentFile = String(line.dropFirst(6))
            continue
        }

        guard let currentFile, line.hasPrefix("@@") else {
            continue
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = hunkPattern.firstMatch(in: line, range: range),
              let startRange = Range(match.range(at: 1), in: line) else {
            continue
        }

        let start = Int(line[startRange]) ?? 0
        let count: Int
        if let countRange = Range(match.range(at: 2), in: line) {
            count = Int(line[countRange]) ?? 1
        } else {
            count = 1
        }

        guard count > 0 else { continue }

        for lineNumber in start..<(start + count) {
            changedLines[currentFile, default: []].insert(lineNumber)
        }
    }

    return changedLines
}

func xmlEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func main() throws {
    let options = try parseOptions(arguments: CommandLine.arguments)

    guard FileManager.default.fileExists(atPath: options.xcresultPath) else {
        throw CoverageError.missingPath(options.xcresultPath)
    }

    let exclusions = try loadExclusions(from: options.exclusionsFile)
    let fileListOutput = try runCommand([
        "xcrun", "xccov", "view", "--archive", "--file-list", options.xcresultPath
    ])

    var coverageByFile: [(path: String, coverage: FileCoverage)] = []

    for absolutePath in fileListOutput.split(whereSeparator: \.isNewline).map(String.init) {
        guard let relative = relativePath(for: absolutePath, repoRoot: options.repoRoot),
              relative.hasPrefix("Sources/"),
              relative.hasSuffix(".swift"),
              !exclusions.contains(relative) else {
            continue
        }

        let coverage = try loadCoverage(for: absolutePath, xcresultPath: options.xcresultPath)
        coverageByFile.append((relative, coverage))
    }

    let overallExecutable = coverageByFile.reduce(0) { $0 + $1.coverage.executableLines }
    let overallCovered = coverageByFile.reduce(0) { $0 + $1.coverage.coveredLines }
    let overallCoverage = overallExecutable == 0 ? 100.0 : (Double(overallCovered) / Double(overallExecutable) * 100.0)

    print(String(format: "Scoped overall unit-test coverage: %.2f%% (%d/%d)", overallCoverage, overallCovered, overallExecutable))
    for item in coverageByFile.sorted(by: { $0.path < $1.path }) {
        let fileCoverage = item.coverage.executableLines == 0
            ? 100.0
            : Double(item.coverage.coveredLines) / Double(item.coverage.executableLines) * 100.0
        print(String(format: "  %@ %.2f%% (%d/%d)", item.path, fileCoverage, item.coverage.coveredLines, item.coverage.executableLines))
    }

    var changedCoverageDescription = "Changed-code unit-test coverage: n/a"
    var changedCoverageValue: Double?

    if let diffBase = options.diffBase, !diffBase.isEmpty {
        let diffText = try runCommand([
            "git", "diff", "--unified=0", "\(diffBase)...HEAD", "--", "Sources", "Tests"
        ], currentDirectory: options.repoRoot)
        let changedLines = parseChangedLines(diffText: diffText)

        var changedExecutable = 0
        var changedCovered = 0

        for item in coverageByFile {
            guard let fileChangedLines = changedLines[item.path] else { continue }

            for lineNumber in fileChangedLines {
                guard let isCovered = item.coverage.lines[lineNumber] else { continue }
                changedExecutable += 1
                if isCovered {
                    changedCovered += 1
                }
            }
        }

        if changedExecutable > 0 {
            let coverage = Double(changedCovered) / Double(changedExecutable) * 100.0
            changedCoverageValue = coverage
            changedCoverageDescription = String(
                format: "Changed-code unit-test coverage: %.2f%% (%d/%d)",
                coverage,
                changedCovered,
                changedExecutable
            )
        } else {
            changedCoverageDescription += " (no changed executable included lines)"
        }
    }

    print(changedCoverageDescription)

    if let sonarXMLPath = options.sonarXMLPath {
        var xml = ["<coverage version=\"1\">"]
        for item in coverageByFile.sorted(by: { $0.path < $1.path }) {
            xml.append("  <file path=\"\(xmlEscaped(item.path))\">")
            for lineNumber in item.coverage.lines.keys.sorted() {
                let covered = item.coverage.lines[lineNumber] == true ? "true" : "false"
                xml.append("    <lineToCover lineNumber=\"\(lineNumber)\" covered=\"\(covered)\"/>")
            }
            xml.append("  </file>")
        }
        xml.append("</coverage>")
        try xml.joined(separator: "\n").write(to: sonarXMLPath, atomically: true, encoding: .utf8)
    }

    var failures: [String] = []

    if overallCoverage < options.overallThreshold {
        failures.append(String(format: "Overall scoped coverage %.2f%% is below %.2f%%.", overallCoverage, options.overallThreshold))
    }

    if let changedCoverageValue, changedCoverageValue < options.changedThreshold {
        failures.append(String(format: "Changed-code coverage %.2f%% is below %.2f%%.", changedCoverageValue, options.changedThreshold))
    }

    if !failures.isEmpty {
        for failure in failures {
            fputs("error: \(failure)\n", stderr)
        }
        exit(1)
    }
}

do {
    try main()
} catch {
    fputs("error: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)\n", stderr)
    exit(1)
}
