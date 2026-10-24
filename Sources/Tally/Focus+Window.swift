import AppKit
import Darwin
import TallyKit

extension Focus {
  /// Works out how to get back to whoever ran this command, from what the process inherited:
  /// the app that launched it, the terminal it's attached to, and the folder it's working in.
  static func ofCaller(agent: String, cwd: String) -> Focus? {
    let environment = ProcessInfo.processInfo.environment
    guard let app = environment["__CFBundleIdentifier"] else { return nil }
    // Editors (and their integrated terminals) bring the right window forward when asked to open its folder.
    if environment["TERM_PROGRAM"] == "vscode" || agent == "cursor", !cwd.isEmpty {
      return .folder(app: app, path: cwd)
    }
    if let tty = controllingTerminal() { return .terminal(app: app, tty: tty) }
    return .app(app)
  }

  /// The tty this process belongs to, even when stdin is a pipe, as hooks' stdin always is.
  private static func controllingTerminal() -> String? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&query, u_int(query.count), &info, &size, nil, 0) == 0,
          info.kp_eproc.e_tdev != -1,
          let name = devname(info.kp_eproc.e_tdev, S_IFCHR)
    else { return nil }
    return "/dev/" + String(cString: name)
  }

  /// Brings the session's window to the front: the exact tab where the app can say which one, else the app.
  func bringToFront() {
    switch self {
    case .terminal(let app, let tty):
      if let script = Self.selectTab(app: app, tty: tty), NSAppleScript(source: script)?.executeAndReturnError(nil) != nil {
        return
      }
      Self.open(app: app)
    case .folder(let app, let path):
      Self.open(app: app, folder: URL(fileURLWithPath: path))
    case .app(let app):
      Self.open(app: app)
    }
  }

  private static func open(app: String, folder: URL? = nil) {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    if let folder {
      NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: configuration)
    } else {
      NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
  }

  /// AppleScript for the terminals that can select a tab by its tty.
  private static func selectTab(app: String, tty: String) -> String? {
    // The tty ends up inside a script, so accept nothing but a real device path.
    guard tty.wholeMatch(of: /\/dev\/ttys[0-9]+/) != nil else { return nil }
    switch app {
    case "com.apple.Terminal":
      return """
        tell application id "com.apple.Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(tty)" then
                set selected of t to true
                set index of w to 1
                activate
                return
              end if
            end repeat
          end repeat
        end tell
        error "not found"
        """
    case "com.googlecode.iterm2":
      return """
        tell application id "com.googlecode.iterm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if tty of s is "\(tty)" then
                  select w
                  select t
                  select s
                  activate
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        error "not found"
        """
    default:
      return nil
    }
  }
}
