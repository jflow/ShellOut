/**
 *  ShellOut
 *  Copyright (c) John Sundell 2017
 *  Licensed under the MIT license. See LICENSE file.
 */

import Foundation
import Dispatch
import ShellQuote

// MARK: - API

/**
 *  Run a shell command using Bash
 *
 *  - parameter command: The command to run
 *  - parameter arguments: The arguments to pass to the command
 *  - parameter path: The path to execute the commands at (defaults to current folder)
 *  - parameter process: Which process to use to perform the command (default: A new one)
 *  - parameter outputHandle: Any `FileHandle` that any output (STDOUT) should be redirected to
 *              (at the moment this is only supported on macOS)
 *  - parameter errorHandle: Any `FileHandle` that any error output (STDERR) should be redirected to
 *              (at the moment this is only supported on macOS)
 *  - parameter environment: The environment for the command.
 *
 *  - returns: The output of running the command
 *  - throws: `ShellOutError` in case the command couldn't be performed, or it returned an error
 *
 *  Use this function to "shell out" in a Swift script or command line tool
 *  For example: `shellOut(to: "mkdir", arguments: ["NewFolder"], at: "~/CurrentFolder")`
 */
@discardableResult public func shellOut(
    to command: SafeString,
    arguments: [Argument] = [],
    at path: String = ".",
    process: Process = .init(),
    outputHandle: FileHandle? = nil,
    errorHandle: FileHandle? = nil,
    environment: [String : String]? = nil,
    quoteArguments: Bool = true
) throws -> String {
    let command = "cd \(path.escapingSpaces) && \(command) \(arguments.map(\.string).joined(separator: " "))"

    return try process.launchBash(
        with: command,
        outputHandle: outputHandle,
        errorHandle: errorHandle,
        environment: environment
    )
}

/**
 *  Run a pre-defined shell command using Bash
 *
 *  - parameter command: The command to run
 *  - parameter path: The path to execute the commands at (defaults to current folder)
 *  - parameter process: Which process to use to perform the command (default: A new one)
 *  - parameter outputHandle: Any `FileHandle` that any output (STDOUT) should be redirected to
 *  - parameter errorHandle: Any `FileHandle` that any error output (STDERR) should be redirected to
 *  - parameter environment: The environment for the command.
 *
 *  - returns: The output of running the command
 *  - throws: `ShellOutError` in case the command couldn't be performed, or it returned an error
 *
 *  Use this function to "shell out" in a Swift script or command line tool
 *  For example: `shellOut(to: .gitCommit(message: "Commit"), at: "~/CurrentFolder")`
 *
 *  See `ShellOutCommand` for more info.
 */
@discardableResult public func shellOut(
    to command: ShellOutCommand,
    at path: String = ".",
    process: Process = .init(),
    outputHandle: FileHandle? = nil,
    errorHandle: FileHandle? = nil,
    environment: [String : String]? = nil
) throws -> String {
    try shellOut(
        to: command.command,
        arguments: command.arguments,
        at: path,
        process: process,
        outputHandle: outputHandle,
        errorHandle: errorHandle,
        environment: environment,
        quoteArguments: false
    )
}

/// Structure used to pre-define commands for use with ShellOut
public struct ShellOutCommand {
    /// The string that makes up the command that should be run on the command line
    public var command: SafeString

    public var arguments: [Argument]

    /// Initialize a value using a string that makes up the underlying command
    public init(command: String, arguments: [Argument] = []) throws {
        self.init(command: try SafeString(command), arguments: arguments)
    }

    public init(safeCommand: String, arguments: [Argument] = []) {
        self.init(command: SafeString(unchecked: safeCommand), arguments: arguments)
    }

    public init(command: SafeString, arguments: [Argument]) {
        self.command = command
        self.arguments = arguments
    }

    var string: String {
        ([Argument(command)] + arguments)
            .map(\.string)
            .joined(separator: " ")
    }

    func appending(arguments newArguments: [Argument]) -> Self {
        .init(command: command, arguments: arguments + newArguments)
    }

    func appending(argument: Argument) -> Self {
        appending(arguments: [argument])
    }

    mutating func append(arguments newArguments: [Argument]) {
        self.arguments = self.arguments + newArguments
    }

    mutating func append(argument: Argument) {
        append(arguments: [argument])
    }
}

/// Git commands
public extension ShellOutCommand {
    /// Initialize a git repository
    static func gitInit() -> ShellOutCommand {
        .init(safeCommand: "git", arguments: ["init".verbatim])
    }

    /// Clone a git repository at a given URL
    static func gitClone(url: URL, to path: String? = nil, allowingPrompt: Bool = true, quiet: Bool = true) -> ShellOutCommand {
        var command = git(allowingPrompt: allowingPrompt)
            .appending(arguments: ["clone", url.absoluteString].quoted)

        path.map { command.append(argument: $0.quoted) }

        if quiet {
            command.append(argument: "--quiet".verbatim)
        }

        return command
    }

    /// Create a git commit with a given message (also adds all untracked file to the index)
    static func gitCommit(message: String, allowingPrompt: Bool = true, quiet: Bool = true) -> ShellOutCommand {
        var command = git(allowingPrompt: allowingPrompt)
            .appending(arguments: ["add . && git commit -a -m".verbatim])
        command.append(argument: message.quoted)

        if quiet {
            command.append(argument: "--quiet".verbatim)
        }

        return command
    }

    /// Perform a git push
    static func gitPush(remote: String? = nil, branch: String? = nil, allowingPrompt: Bool = true, quiet: Bool = true) -> ShellOutCommand {
        var command = git(allowingPrompt: allowingPrompt)
            .appending(arguments: ["push".verbatim])
        remote.map { command.append(argument: $0.verbatim) }
        branch.map { command.append(argument: $0.verbatim) }

        if quiet {
            command.append(argument: "--quiet".verbatim)
        }

        return command
    }

    /// Perform a git pull
    static func gitPull(remote: String? = nil, branch: String? = nil, allowingPrompt: Bool = true, quiet: Bool = true) -> ShellOutCommand {
        var command = git(allowingPrompt: allowingPrompt)
            .appending(arguments: ["pull".verbatim])
        remote.map { command.append(argument: $0.quoted) }
        branch.map { command.append(argument: $0.quoted) }

        if quiet {
            command.append(argument: "--quiet".verbatim)
        }

        return command
    }

    /// Run a git submodule update
    static func gitSubmoduleUpdate(initializeIfNeeded: Bool = true, recursive: Bool = true, allowingPrompt: Bool = true, quiet: Bool = true) -> ShellOutCommand {
        var command = git(allowingPrompt: allowingPrompt)
            .appending(arguments: ["submodule update".verbatim])

        if initializeIfNeeded {
            command.append(argument: "--init".verbatim)
        }

        if recursive {
            command.append(argument: "--recursive".verbatim)
        }

        if quiet {
            command.append(argument: "--quiet".verbatim)
        }

        return command
    }

    /// Checkout a given git branch
    static func gitCheckout(branch: String, quiet: Bool = true) -> ShellOutCommand {
        var command = ShellOutCommand(safeCommand: "git",
                                      arguments: ["checkout".verbatim, branch.quoted])

        if quiet {
            command.append(argument: "--quiet".verbatim)
        }

        return command
    }

    private static func git(allowingPrompt: Bool) -> Self {
        allowingPrompt
        ? .init(safeCommand: "git")
        : .init(safeCommand: "env", arguments: ["GIT_TERMINAL_PROMPT=0", "git"].verbatim)

    }
}

/// File system commands
public extension ShellOutCommand {
    /// Create a folder with a given name
    static func createFolder(named name: String) -> ShellOutCommand {
        .init(safeCommand: "mkdir", arguments: [name.quoted])
    }

    /// Create a file with a given name and contents (will overwrite any existing file with the same name)
    static func createFile(named name: String, contents: String) -> ShellOutCommand {
        .init(safeCommand: "echo", arguments: [contents.quoted])
        .appending(argument: ">".verbatim)
        .appending(argument: name.quoted)
    }

    /// Move a file from one path to another
    static func moveFile(from originPath: String, to targetPath: String) -> ShellOutCommand {
        .init(safeCommand: "mv", arguments: [originPath, targetPath].quoted)
    }
    
    /// Copy a file from one path to another
    static func copyFile(from originPath: String, to targetPath: String) -> ShellOutCommand {
        .init(safeCommand: "cp", arguments: [originPath, targetPath].quoted)
    }
    
    /// Remove a file
    static func removeFile(from path: String, arguments: [String] = ["-f"]) -> ShellOutCommand {
        .init(safeCommand: "rm", arguments: arguments.quoted + [path.quoted])
    }

    /// Open a file using its designated application
    static func openFile(at path: String) -> ShellOutCommand {
        .init(safeCommand: "open", arguments: [path.quoted])
    }

    /// Read a file as a string
    static func readFile(at path: String) -> ShellOutCommand {
        .init(safeCommand: "cat", arguments: [path.quoted])
    }

    /// Create a symlink at a given path, to a given target
    static func createSymlink(to targetPath: String, at linkPath: String) -> ShellOutCommand {
        .init(safeCommand: "ln", arguments: ["-s", targetPath, linkPath].quoted)
    }

    /// Expand a symlink at a given path, returning its target path
    static func expandSymlink(at path: String) -> ShellOutCommand {
        .init(safeCommand: "readlink", arguments: [path.quoted])
    }
}

/// Marathon commands
public extension ShellOutCommand {
    /// Run a Marathon Swift script
    static func runMarathonScript(at path: String, arguments: [String] = []) -> ShellOutCommand {
        .init(safeCommand: "marathon", arguments: ["run", path].quoted + arguments.quoted)
    }

    /// Update all Swift packages managed by Marathon
    static func updateMarathonPackages() -> ShellOutCommand {
        .init(safeCommand: "marathon", arguments: ["update".verbatim])
    }
}

/// Swift Package Manager commands
public extension ShellOutCommand {
    /// Enum defining available package types when using the Swift Package Manager
    enum SwiftPackageType: String {
        case library
        case executable
    }

    /// Enum defining available build configurations when using the Swift Package Manager
    enum SwiftBuildConfiguration: String {
        case debug
        case release
    }

    /// Create a Swift package with a given type (see SwiftPackageType for options)
    static func createSwiftPackage(withType type: SwiftPackageType = .library) -> ShellOutCommand {
        .init(safeCommand: "swift",
              arguments: ["package init --type \(type)".verbatim])
    }

    /// Update all Swift package dependencies
    static func updateSwiftPackages() -> ShellOutCommand {
        .init(safeCommand: "swift", arguments: ["package", "update"].verbatim)
    }

    /// Generate an Xcode project for a Swift package
    static func generateSwiftPackageXcodeProject() -> ShellOutCommand {
        .init(safeCommand: "swift", arguments: ["package", "generate-xcodeproj"].verbatim)
    }

    /// Build a Swift package using a given configuration (see SwiftBuildConfiguration for options)
    static func buildSwiftPackage(withConfiguration configuration: SwiftBuildConfiguration = .debug) -> ShellOutCommand {
        .init(safeCommand: "swift",
              arguments: ["build -c \(configuration)".verbatim])
    }

    /// Test a Swift package using a given configuration (see SwiftBuildConfiguration for options)
    static func testSwiftPackage(withConfiguration configuration: SwiftBuildConfiguration = .debug) -> ShellOutCommand {
        .init(safeCommand: "swift",
              arguments: ["test -c \(configuration)".verbatim])
    }
}

/// Fastlane commands
public extension ShellOutCommand {
    /// Run Fastlane using a given lane
    static func runFastlane(usingLane lane: String) -> ShellOutCommand {
        .init(safeCommand: "fastlane", arguments: [lane.quoted])
    }
}

/// CocoaPods commands
public extension ShellOutCommand {
    /// Update all CocoaPods dependencies
    static func updateCocoaPods() -> ShellOutCommand {
        .init(safeCommand: "pod", arguments: ["update".verbatim])
    }

    /// Install all CocoaPods dependencies
    static func installCocoaPods() -> ShellOutCommand {
        .init(safeCommand: "pod", arguments: ["install".verbatim])
    }
}

/// Error type thrown by the `shellOut()` function, in case the given command failed
public struct ShellOutError: Swift.Error {
    /// The termination status of the command that was run
    public let terminationStatus: Int32
    /// The error message as a UTF8 string, as returned through `STDERR`
    public var message: String { return errorData.shellOutput() }
    /// The raw error buffer data, as returned through `STDERR`
    public let errorData: Data
    /// The raw output buffer data, as retuned through `STDOUT`
    public let outputData: Data
    /// The output of the command as a UTF8 string, as returned through `STDOUT`
    public var output: String { return outputData.shellOutput() }
}

extension ShellOutError: CustomStringConvertible {
    public var description: String {
        return """
               ShellOut encountered an error
               Status code: \(terminationStatus)
               Message: "\(message)"
               Output: "\(output)"
               """
    }
}

extension ShellOutError: LocalizedError {
    public var errorDescription: String? {
        return description
    }
}

extension ShellOutCommand {
    // TODO: consolidate with ShellOutError
    struct Error: Swift.Error {
        var message: String
    }
}

// MARK: - Private

private extension Process {
    @discardableResult func launchBash(with command: String, outputHandle: FileHandle? = nil, errorHandle: FileHandle? = nil, environment: [String : String]? = nil) throws -> String {
        launchPath = "/bin/bash"
        arguments = ["-c", command]

        if let environment = environment {
            self.environment = environment
        }

        // Because FileHandle's readabilityHandler might be called from a
        // different queue from the calling queue, avoid a data race by
        // protecting reads and writes to outputData and errorData on
        // a single dispatch queue.
        let outputQueue = DispatchQueue(label: "bash-output-queue")

        var outputData = Data()
        var errorData = Data()

        let outputPipe = Pipe()
        standardOutput = outputPipe

        let errorPipe = Pipe()
        standardError = errorPipe

        #if !os(Linux)
        outputPipe.fileHandleForReading.readabilityHandler = { handler in
            let data = handler.availableData
            outputQueue.async {
                outputData.append(data)
                outputHandle?.write(data)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handler in
            let data = handler.availableData
            outputQueue.async {
                errorData.append(data)
                errorHandle?.write(data)
            }
        }
        #endif

        launch()

        #if os(Linux)
        outputQueue.sync {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        }
        #endif

        waitUntilExit()

        if let handle = outputHandle, !handle.isStandard {
            handle.closeFile()
        }

        if let handle = errorHandle, !handle.isStandard {
            handle.closeFile()
        }

        #if !os(Linux)
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        #endif

        // Block until all writes have occurred to outputData and errorData,
        // and then read the data back out.
        return try outputQueue.sync {
            if terminationStatus != 0 {
                throw ShellOutError(
                    terminationStatus: terminationStatus,
                    errorData: errorData,
                    outputData: outputData
                )
            }

            return outputData.shellOutput()
        }
    }
}

private extension FileHandle {
    var isStandard: Bool {
        return self === FileHandle.standardOutput ||
            self === FileHandle.standardError ||
            self === FileHandle.standardInput
    }
}

private extension Data {
    func shellOutput() -> String {
        guard let output = String(data: self, encoding: .utf8) else {
            return ""
        }

        guard !output.hasSuffix("\n") else {
            let endIndex = output.index(before: output.endIndex)
            return String(output[..<endIndex])
        }

        return output

    }
}

private extension String {
    var escapingSpaces: String {
        return replacingOccurrences(of: " ", with: "\\ ")
    }

    func appending(argument: String) -> String {
        return "\(self) \"\(argument)\""
    }

    func appending(arguments: [String]) -> String {
        return appending(argument: arguments.joined(separator: "\" \""))
    }

    mutating func append(argument: String) {
        self = appending(argument: argument)
    }

    mutating func append(arguments: [String]) {
        self = appending(arguments: arguments)
    }
}
