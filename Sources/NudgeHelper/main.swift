import Foundation
import NudgeCore

private func printUsage() {
    print("""
    NudgeHelper v\(NudgeHelperDaemon.daemonVersion) — Privileged Battery Limit Daemon
    Mach Service: \(kNudgeHelperMachServiceName)

    Usage:
      nudge-helper [options]

    Options:
      -f, --foreground          Run in foreground test mode without Mach service bootstrap
      -i, --interval <seconds>  Enforcement polling interval in seconds (default: \(NudgeHelperDaemon.defaultIntervalSeconds), min: 2)
      -v, --version             Print daemon version and exit
      -h, --help                Show this help message and exit
    """)
}

var foreground = false
var intervalSeconds = NudgeHelperDaemon.defaultIntervalSeconds

let args = Array(CommandLine.arguments.dropFirst())
var index = 0

while index < args.count {
    let arg = args[index]
    switch arg {
    case "--foreground", "-f":
        foreground = true
    case "--interval", "-i":
        let nextIndex = index + 1
        guard nextIndex < args.count, let parsed = Int(args[nextIndex]), parsed >= 2 else {
            fputs("Error: --interval requires an integer >= 2\n", stderr)
            exit(EXIT_FAILURE)
        }
        intervalSeconds = parsed
        index = nextIndex
    case "--version", "-v":
        print("nudge-helper \(NudgeHelperDaemon.daemonVersion)")
        exit(EXIT_SUCCESS)
    case "--help", "-h":
        printUsage()
        exit(EXIT_SUCCESS)
    default:
        fputs("Unknown option: \(arg)\n", stderr)
        printUsage()
        exit(EXIT_FAILURE)
    }
    index += 1
}

NudgeHelperDaemon.shared.start(foreground: foreground, intervalSeconds: intervalSeconds)

// Run the main RunLoop so NSWorkspace Fast User Switching & sleep/wake notifications are delivered
// while keeping idle CPU utilization well below 0.5%.
RunLoop.main.run()
