//
//  SwiftCheckCommandPlugin.swift
//  SwiftCheck
//
//  Created by Mihran on 21.11.26.
//

import Foundation
import PackagePlugin

/// `swift package swiftcheck [--target <name>…] [swiftcheck options]`, or the SwiftCheck item in Xcode's
/// project context menu. Checks the Swift files of the chosen targets (all by default) and reports violations
/// as diagnostics. Options such as `--json` or `--include-baselined` are passed to the tool; `--all` and
/// `--diff <base>` replace the target selection.
@main
struct SwiftCheckCommandPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        let names = extractor.extractOption(named: "target")
        let targets = names.isEmpty ? context.package.targets : try context.package.targets(named: names)
        let files = targets.compactMap(\.sourceModule).flatMap { $0.sourceFiles(withSuffix: "swift").map(\.url) }
        try Runner.run(tool: context.tool(named: "swiftcheck").url, start: context.package.directoryURL,
                       files: files, options: extractor.remainingArguments)
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftCheckCommandPlugin: XcodeCommandPlugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        var extractor = ArgumentExtractor(arguments)
        let names = Set(extractor.extractOption(named: "target"))
        let targets = context.xcodeProject.targets.filter { names.isEmpty || names.contains($0.displayName) }
        let files = targets.flatMap { target in
            target.inputFiles.filter { $0.type == .source && $0.url.pathExtension == "swift" }.map(\.url)
        }
        try Runner.run(tool: context.tool(named: "swiftcheck").url, start: context.xcodeProject.directoryURL,
                       files: files, options: extractor.remainingArguments)
    }
}
#endif

enum Runner {
    static func run(tool: URL, start: URL, files: [URL], options: [String]) throws {
        let root = ProjectRoot.find(from: start)
        let json = options.contains("--json")
        var arguments = ["--root", root.path] + options
        if !json, !options.contains("--xcode") { arguments.insert("--xcode", at: 0) }
        if !options.contains(where: { ["--all", "--diff", "--files", "--list-rules", "--help", "--version"].contains($0) }) {
            guard !files.isEmpty else {
                Diagnostics.remark("SwiftCheck: no Swift files in the selected targets")
                return
            }
            arguments += ["--files"] + Set(files.map(\.path)).sorted()
        }

        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.currentDirectoryURL = root
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(decoding: outData, as: UTF8.self)
        let isPlainOutput = json || options.contains { ["--list-rules", "--help", "--version"].contains($0) }
        if isPlainOutput {
            print(out, terminator: "")
        } else {
            for line in out.split(separator: "\n") { report(String(line), root: root) }
        }
        let summary = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { print(summary) }

        switch process.terminationStatus {
        case 0: break
        case 1: Diagnostics.error("SwiftCheck found errors")
        default: Diagnostics.error("swiftcheck exited with status \(process.terminationStatus)")
        }
    }

    /// `path:line:col: warning|error: [rule] message` → a diagnostic Xcode links to the line. The message
    /// repeats the location, because the terminal shows only the message.
    static func report(_ line: String, root: URL) {
        let parts = line.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count == 5, let number = Int(parts[1]), let column = Int(parts[2]) else {
            print(line)
            return
        }
        let path = String(parts[0])
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let shown = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        let severity = parts[3].trimmingCharacters(in: .whitespaces)
        let message = "\(shown):\(number):\(column): " + parts[4].trimmingCharacters(in: .whitespaces)
        switch severity {
        case "error": Diagnostics.error(message, file: path, line: number)
        default: Diagnostics.warning(message, file: path, line: number)
        }
    }
}

/// The folder with `.swiftcheck.json` at or above the package / project; see the build tool plugin.
enum ProjectRoot {
    /// Symlinks resolved like `realpath(3)` (`/tmp` → `/private/tmp`), matching the paths swiftcheck reports.
    static func canonical(_ url: URL) -> URL {
        guard let resolved = realpath(url.standardizedFileURL.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    static func find(from start: URL) -> URL {
        let start = canonical(start)
        var current = start
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".swiftcheck.json").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return start }
            current = parent
        }
    }
}
