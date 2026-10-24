import Foundation

/// Registers `tally hook <agent>` with every agent installed on this Mac.
///
/// Each agent keeps its hooks in its own file, and most share one JSON shape. Everything already
/// in those files is kept, older Tally entries are replaced, and each file is copied aside once
/// before it's first touched.
public struct Connector {
  public enum Outcome: Sendable, Equatable {
    case connected
    /// The agent isn't installed for this user.
    case absent
    case failed(String)
  }

  /// One agent's hook file.
  struct Target: Sendable {
    enum Shape: Sendable {
      /// `{"hooks": {"Event": [{"matcher": …, "hooks": [{"type": "command", …}]}]}}`
      /// `timeout` is in the agent's own unit; `async` keeps the agent from waiting on us.
      case shared(events: [Event], timeout: Int, async: Bool)
      /// `{"version": 1, "hooks": {"event": [{"command": …}]}}`
      case flat(events: [String])
    }
    struct Event: Sendable, ExpressibleByStringLiteral {
      let name: String
      var matcher: String? = nil

      init(name: String, matcher: String? = nil) {
        self.name = name
        self.matcher = matcher
      }

      init(stringLiteral name: String) { self.init(name: name) }
    }
    let agent: String
    let label: String
    /// Present only when the agent is installed.
    let folder: String
    let file: String
    let shape: Shape
  }

  static let targets: [Target] = [
    Target(agent: "claude", label: "Claude Code", folder: ".claude", file: ".claude/settings.json", shape: .shared(
      events: ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest",
               Target.Event(name: "Notification", matcher: "permission_prompt|elicitation_dialog"), "Stop", "StopFailure", "SessionEnd"],
      timeout: 5, async: true)),
    Target(agent: "codex", label: "Codex", folder: ".codex", file: ".codex/hooks.json", shape: .shared(
      events: ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest",
               "Stop", "SessionEnd"],
      timeout: 5, async: true)),
    Target(agent: "grok", label: "Grok", folder: ".grok", file: ".grok/hooks/tally.json", shape: .shared(
      events: ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification",
               "Stop", "StopFailure", "SessionEnd"],
      timeout: 5, async: false)),
    Target(agent: "gemini", label: "Gemini", folder: ".gemini", file: ".gemini/settings.json", shape: .shared(
      events: ["SessionStart", "BeforeAgent", "AfterTool", "Notification",
               "AfterAgent", "SessionEnd"],
      timeout: 5000, async: false)),   // milliseconds here
    Target(agent: "cursor", label: "Cursor", folder: ".cursor", file: ".cursor/hooks.json", shape: .flat(
      events: ["sessionStart", "beforeSubmitPrompt", "stop", "sessionEnd"])),
  ]

  let home: URL
  let executable: String

  public init(executable: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
    self.executable = executable
    self.home = home
  }

  /// Connects every installed agent and says what happened to each, by name.
  public func connectAll() -> [(agent: String, outcome: Outcome)] {
    var results = Self.targets.map { ($0.label, connect($0)) }
    results.append(("Codex notify", connectCodexNotify()))
    return results.filter { $0.1 != .absent }
  }

  func command(for agent: String) -> String {
    "'\(executable.replacingOccurrences(of: "'", with: #"'\''"#))' hook \(agent)"
  }

  /// Every command Tally writes runs the `hook` subcommand of a binary called Tally.
  static func isOurs(_ command: Any?) -> Bool {
    (command as? String)?.contains("Tally' hook ") == true
  }

  // MARK: - JSON hook files

  func connect(_ target: Target) -> Outcome {
    guard FileManager.default.fileExists(atPath: home.appending(path: target.folder).path) else { return .absent }
    let file = home.appending(path: target.file)
    do {
      var root = try Self.readJSON(file)
      Self.install(command(for: target.agent), shape: target.shape, into: &root)
      try Self.writeJSON(root, to: file)
      return .connected
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  static func install(_ command: String, shape: Target.Shape, into root: inout [String: Any]) {
    var hooks = root["hooks"] as? [String: Any] ?? [:]
    // Drop whatever an older Tally left behind, including events it no longer uses.
    for (event, groups) in hooks {
      guard let groups = groups as? [[String: Any]] else { continue }
      let kept = groups.filter { group in
        !isOurs(group["command"]) && !((group["hooks"] as? [[String: Any]])?.contains { isOurs($0["command"]) } ?? false)
      }
      hooks[event] = kept.isEmpty ? nil : kept
    }
    switch shape {
    case .shared(let events, let timeout, let async):
      var entry: [String: Any] = ["type": "command", "command": command, "timeout": timeout]
      if async { entry["async"] = true }
      for event in events {
        var group: [String: Any] = ["hooks": [entry]]
        group["matcher"] = event.matcher
        hooks[event.name] = (hooks[event.name] as? [[String: Any]] ?? []) + [group]
      }
    case .flat(let events):
      root["version"] = root["version"] ?? 1
      for event in events {
        hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [["command": command]]
      }
    }
    root["hooks"] = hooks
  }

  static func readJSON(_ file: URL) throws -> [String: Any] {
    guard let data = try? Data(contentsOf: file), !data.isEmpty else { return [:] }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: file.path])
    }
    return root
  }

  static func writeJSON(_ root: [String: Any], to file: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try write(data, to: file)
  }

  private static func write(_ data: Data, to file: URL) throws {
    let manager = FileManager.default
    try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let backup = file.appendingPathExtension("before-tally")
    if manager.fileExists(atPath: file.path), !manager.fileExists(atPath: backup.path) {
      try manager.copyItem(at: file, to: backup)
    }
    try data.write(to: file, options: .atomic)
  }

  // MARK: - Codex `notify`

  /// Codex's `notify` command works without the per-hook trust step its hooks need,
  /// so "done" lights up even before you've trusted the hooks.
  func connectCodexNotify() -> Outcome {
    let file = home.appending(path: ".codex/config.toml")
    guard FileManager.default.fileExists(atPath: home.appending(path: ".codex").path) else { return .absent }
    let toml = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    guard let updated = Self.settingNotify(in: toml, executable: executable) else {
      return .failed("config.toml already has its own notify command; left it alone")
    }
    do {
      try Self.write(Data(updated.utf8), to: file)
      return .connected
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  /// Returns the file with Tally's `notify` line, or nil if the user already has a different one.
  static func settingNotify(in toml: String, executable: String) -> String? {
    let escaped = executable.replacingOccurrences(of: #"\"#, with: #"\\"#).replacingOccurrences(of: #"""#, with: #"\""#)
    let line = #"notify = ["\#(escaped)", "hook", "codex"]"#
    var lines = toml.components(separatedBy: "\n")
    // Top-level keys live above the first [table].
    let topLevel = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
    if let existing = lines[..<topLevel].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify") }) {
      guard lines[existing].contains(#"Tally", "hook""#) else { return nil }
      lines[existing] = line
    } else {
      lines.insert(line, at: 0)
    }
    return lines.joined(separator: "\n")
  }
}
