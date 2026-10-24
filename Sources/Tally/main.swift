import AppKit

// One binary, two jobs: with a subcommand it's the `tally` command agents call; without one
// it's the menu bar app.
if let status = Command.run(Array(CommandLine.arguments.dropFirst())) {
  exit(status)
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
