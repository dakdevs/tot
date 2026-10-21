import Foundation

public struct CLIError: Error, CustomStringConvertible {
  public let description: String
}

public enum CLIRunner {
  /// GUI apps inherit a minimal PATH, so look where Bun, Homebrew, and user installs put CLIs.
  public static let searchPaths = [
    "\(NSHomeDirectory())/.bun/bin", "\(NSHomeDirectory())/.local/bin",
    "\(NSHomeDirectory())/.opencode/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
  ]

  public static func resolve(_ executable: String) -> String? {
    searchPaths.map { "\($0)/\(executable)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  /// Runs the CLI off the main actor and returns stdout; throws on launch failure, timeout, or a
  /// non-zero exit.
  @concurrent
  public static func run(_ invocation: CLIInvocation, timeout: TimeInterval = 90) async throws -> Data {
    guard let path = resolve(invocation.executable) else {
      throw CLIError(description: "\(invocation.executable) not found in \(searchPaths.joined(separator: ":"))")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = invocation.arguments
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = (searchPaths + [environment["PATH"] ?? ""]).joined(separator: ":")
    process.environment = environment
    process.currentDirectoryURL = FileManager.default.temporaryDirectory
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    let input = Pipe()
    process.standardInput = input
    try process.run()
    let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
    defer { watchdog.cancel() }
    if let text = invocation.standardInput { input.fileHandleForWriting.write(Data(text.utf8)) }
    try input.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw CLIError(
        description: "\(invocation.executable) \(invocation.arguments.prefix(2).joined(separator: " ")) "
          + "exited with status \(process.terminationStatus)")
    }
    return data
  }
}
