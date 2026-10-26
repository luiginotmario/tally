import AppKit
import ServiceManagement
import TallyKit

/// The menu bar presence: a small lamp that fills when an agent wants you, and a short menu.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let desk = Desk()
  private var inbox: Inbox?
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

  func applicationDidFinishLaunching(_ notification: Notification) {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    if others.contains(where: { $0 != .current }) { NSApp.terminate(nil); return }

    inbox = Inbox { [desk] in desk.receive($0) }
    desk.onChange = { [unowned self] in refreshIcon() }

    let menu = NSMenu()
    menu.delegate = self
    item.menu = menu
    refreshIcon()

    // The deck should just work after a restart, so the first launch of the real app opts into login.
    if Bundle.main.bundleIdentifier != nil, !UserDefaults.standard.bool(forKey: "launched") {
      UserDefaults.standard.set(true, forKey: "launched")
      try? SMAppService.mainApp.register()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    desk.blank()
  }

  /// Four little keys, like the app icon; the top-right one fills while an agent wants you.
  private func refreshIcon() {
    let wanting = desk.waitingOnYou
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
      for (index, origin) in [(0, 9), (9, 9), (0, 0), (9, 0)].map({ CGPoint(x: $0 + 1, y: $1 + 1) }).enumerated() {
        let key = NSBezierPath(roundedRect: NSRect(origin: origin, size: NSSize(width: 6, height: 6)).insetBy(dx: 0.5, dy: 0.5),
                               xRadius: 1.5, yRadius: 1.5)
        NSColor.black.set()
        if index == 1 && wanting > 0 { key.fill() } else { key.lineWidth = 1; key.stroke() }
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = wanting > 0 ? "\(wanting) agents waiting" : "Tally"
    item.button?.image = image
  }

  // MARK: - Menu

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let deck = desk.deck.model.map { "\($0.name) connected" } ?? "Plug in a Stream Deck"
    menu.addItem(NSMenuItem(title: deck, action: nil, keyEquivalent: ""))
    menu.addItem(.separator())
    menu.addItem(action("Connect Agents…", #selector(connectAgents)))
    let login = action("Open at Login", #selector(toggleLogin))
    login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    menu.addItem(login)
    menu.addItem(.separator())
    menu.addItem(action("Quit Tally", #selector(NSApplication.terminate(_:)), key: "q"))
  }

  private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
    let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
    item.target = selector == #selector(NSApplication.terminate(_:)) ? NSApp : self
    return item
  }

  @objc private func connectAgents() {
    guard let executable = Bundle.main.executableURL?.path else { return }
    let results = Connector(executable: executable).connectAll()
    let alert = NSAlert()
    alert.messageText = results.isEmpty ? "No agents found" : "Agents connected"
    alert.informativeText = results.isEmpty
      ? "Install an agent, then try again."
      : results.map { agent, outcome in
          switch outcome {
          case .connected: "✓ \(agent)"
          case .failed(let reason): "✗ \(agent): \(reason)"
          case .absent: ""
          }
        }.joined(separator: "\n")
    NSApp.activate()
    alert.runModal()
  }

  @objc private func toggleLogin() {
    let service = SMAppService.mainApp
    try? service.status == .enabled ? service.unregister() : service.register()
  }
}
