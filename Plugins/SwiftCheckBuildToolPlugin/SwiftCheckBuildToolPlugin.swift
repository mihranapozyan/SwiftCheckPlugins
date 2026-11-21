//
//  SwiftCheckBuildToolPlugin.swift
//  SwiftCheck
//
//  Created by Mihran on 21.11.26.
//

import Foundation
import PackagePlugin

/// Runs SwiftCheck on a target's Swift files during every build. Violations appear as compiler-style warnings
/// and errors; an error-severity violation fails the build.
@main
struct SwiftCheckBuildToolPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let module = target.sourceModule else { return [] }
        let files = module.sourceFiles(withSuffix: "swift").map(\.url)
        return try Self.commands(tool: context.tool(named: "swiftcheck").url,
                                 start: context.package.directoryURL, files: files)
    }

    static func commands(tool: URL, start: URL, files: [URL]) -> [Command] {
        guard !files.isEmpty else { return [] }
        let root = ProjectRoot.find(from: start)
        return [
            .buildCommand(
                displayName: "SwiftCheck",
                executable: tool,
                arguments: ["--xcode", "--root", root.path, "--files"] + files.map(\.path),
                inputFiles: files + ProjectRoot.configurationFiles(in: root),
                // No outputs: the command runs on every build, which takes milliseconds.
                outputFiles: []
            ),
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftCheckBuildToolPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let files = target.inputFiles.filter { $0.type == .source && $0.url.pathExtension == "swift" }.map(\.url)
        return try Self.commands(tool: context.tool(named: "swiftcheck").url,
                                 start: context.xcodeProject.directoryURL, files: files)
    }
}
#endif

/// The folder with `.swiftcheck.json` at or above the package / project, so one configuration can cover a whole
/// repository. Without one, the package / project folder itself (all rules, default severities).
enum ProjectRoot {
    static let configurationFileName = ".swiftcheck.json"

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
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(configurationFileName).path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return start }
            current = parent
        }
    }

    static func configurationFiles(in root: URL) -> [URL] {
        [configurationFileName, ".swiftcheck-baseline.json"]
            .map { root.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
