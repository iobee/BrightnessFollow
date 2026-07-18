import AppKit
import Foundation

let arguments = Set(CommandLine.arguments.dropFirst())
if arguments.contains("--windows") {
    exit(Diagnostics.printApplicationWindows())
}
if arguments.contains("--probe") || arguments.contains("--verify-ddc") {
    exit(Diagnostics.run(verifyWrite: arguments.contains("--verify-ddc")))
}

if let bundleIdentifier = Bundle.main.bundleIdentifier {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    let earlierInstanceIsRunning = NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleIdentifier)
        .contains { $0.processIdentifier > 0 && $0.processIdentifier < currentPID }
    if earlierInstanceIsRunning { exit(0) }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
