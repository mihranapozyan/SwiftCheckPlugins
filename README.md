# SwiftCheckPlugins

SwiftPM and Xcode plugins for [SwiftCheck](https://github.com/mihranapozyan/SwiftCheck), a fast static
analyzer for Swift code. This package contains only the plugins and a reference to the prebuilt
`swiftcheck` binary of the matching SwiftCheck release, so adding it costs no build time and brings no
swift-syntax dependency into your project.

Requirements: Apple Silicon Mac, Xcode 16 or later.

## Build tool plugin

Checks a target's Swift files on every build. Violations appear as warnings and errors on the right
lines; an error-severity violation fails the build.

**Xcode project:** File ▸ Add Package Dependencies…, enter
`https://github.com/mihranapozyan/SwiftCheckPlugins.git` and add the package without linking a product.
In the target: Build Phases ▸ Run Build Tool Plug-ins ▸ + ▸ **SwiftCheckBuildToolPlugin**. Trust the
plugin when Xcode asks on the first build.

**Swift package:**

```swift
dependencies: [
    .package(url: "https://github.com/mihranapozyan/SwiftCheckPlugins.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "MyLibrary",
        plugins: [.plugin(name: "SwiftCheckBuildToolPlugin", package: "SwiftCheckPlugins")]
    ),
]
```

For `xcodebuild` in CI, pass `-skipPackagePluginValidation` (or trust the plugin once locally).

## Command plugin

```bash
swift package swiftcheck                         # all targets
swift package swiftcheck --target MyLibrary      # selected targets
swift package swiftcheck --json                  # JSON report
swift package swiftcheck --diff main             # files changed since main
```

In Xcode: right-click the project in the navigator ▸ SwiftCheck.

## Configuration

Both plugins look for `.swiftcheck.json` in the package / project folder and its parents, so one file at
the repository root covers every package in it. Without a configuration, every rule runs with its default
severity. Rules, configuration, suppression comments and the baseline are described in the SwiftCheck
README.

## Versions

Each version of this package uses the SwiftCheck release with the same number. `Package.swift` is
generated from `Package.swift.template` by SwiftCheck's `scripts/release.sh`.
