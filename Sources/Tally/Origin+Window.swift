import AppKit
import Darwin
import TallyKit

extension Origin {
  /// Reads where the agent that ran this command lives, from what the process inherited.
  static func ofCaller(agent: String, session: String) -> Origin {
    let environment = ProcessInfo.processInfo.environment
    let app = environment["__CFBundleIdentifier"]
    var origin = Origin(app: app, pane: environment["CMUX_SURFACE_ID"], tty: controllingTerminal())

    // Desktop agent apps can open one exact session from a link.
    if let host = environment["CLAUDE_CODE_HOST_SESSION_ID"], host.wholeMatch(of: /local_[A-Za-z0-9-]{1,64}/) != nil {
      origin.link = "claude://code/continue?session=\(host)"
    } else if app == "com.openai.codex", session.wholeMatch(of: /[A-Za-z0-9_-]{1,128}/) != nil {
      origin.link = "codex://threads/\(session)"
    }

    // Editors bring the right window forward when asked to open its folder.
    origin.opensByFolder = agent == "cursor"
      || ["vscode", "zed"].contains(environment["TERM_PROGRAM"] ?? "")
      || environment["TERMINAL_EMULATOR"]?.hasPrefix("JetBrains") == true
    return origin
  }

  /// The tty this process belongs to, even though a hook's stdin is a pipe.
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
}

extension Board.Session {
  /// Brings the session to the front: the exact session where its app can be told which one,
  /// otherwise the app, where you can click the rest of the way.
  func bringToFront() {
    guard let origin else { return }
    if let link = origin.link, let url = URL(string: link), NSWorkspace.shared.open(url) { return }
    guard let app = origin.app, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { return }

    if let script = Self.focusScript(app: app, pane: origin.pane, tty: origin.tty),
       NSAppleScript(source: script)?.executeAndReturnError(nil) != nil {
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    if origin.opensByFolder, !cwd.isEmpty {
      NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: appURL, configuration: configuration)
    } else {
      NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
  }

  /// AppleScript for the terminals that can pick out one pane: cmux by its pane id, Terminal and
  /// iTerm by tty. Ids end up inside the script, so only well-formed ones are accepted.
  private static func focusScript(app: String, pane: String?, tty: String?) -> String? {
    let tty = tty?.wholeMatch(of: /\/dev\/ttys[0-9]+/).map { String($0.output) }
    switch app {
    case "com.cmuxterm.app":
      guard let pane, pane.wholeMatch(of: /[A-Za-z0-9-]{1,64}/) != nil else { return nil }
      return """
        tell application id "com.cmuxterm.app"
          focus terminal id "\(pane)"
          activate
        end tell
        """
    case "com.apple.Terminal":
      guard let tty else { return nil }
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
      guard let tty else { return nil }
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
