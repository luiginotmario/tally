import Foundation
import Testing
@testable import TallyKit

struct ConnectorTests {
  let command = "'/Applications/Tally.app/Contents/MacOS/Tally' hook claude"

  @Test func `keeps the user's hooks and replaces older tally ones`() throws {
    var root: [String: Any] = [
      "model": "opus",
      "hooks": [
        "Stop": [["hooks": [["type": "command", "command": "say done"]]],
                 ["hooks": [["type": "command", "command": "'/old/Tally' hook claude"]]]],
        "Retired": [["hooks": [["type": "command", "command": "'/old/Tally' hook claude"]]]],
      ],
    ]
    Connector.install(command, shape: .shared(events: ["Stop", Connector.Target.Event(name: "Notification", matcher: "permission_prompt")], timeout: 5, async: true), into: &root)

    let hooks = try #require(root["hooks"] as? [String: Any])
    #expect(root["model"] as? String == "opus")
    #expect(hooks["Retired"] == nil)
    let stop = try #require(hooks["Stop"] as? [[String: Any]])
    #expect(stop.count == 2)
    #expect(((stop[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String) == "say done")
    let ours = try #require((stop[1]["hooks"] as? [[String: Any]])?.first)
    #expect(ours["command"] as? String == command && ours["async"] as? Bool == true && ours["timeout"] as? Int == 5)
    let notification = try #require((hooks["Notification"] as? [[String: Any]])?.first)
    #expect(notification["matcher"] as? String == "permission_prompt")
  }

  @Test func `installing twice changes nothing`() throws {
    var once: [String: Any] = [:]
    Connector.install(command, shape: .flat(events: ["stop"]), into: &once)
    var twice = once
    Connector.install(command, shape: .flat(events: ["stop"]), into: &twice)
    #expect(NSDictionary(dictionary: once) == NSDictionary(dictionary: twice))
    #expect(once["version"] as? Int == 1)
  }

  @Test func `codex notify goes above the first table`() throws {
    let toml = "model = \"gpt\"\n\n[profiles.fast]\nnotify = 1\n"
    let updated = try #require(Connector.settingNotify(in: toml, executable: "/Apps/Tally"))
    #expect(updated.hasPrefix(#"notify = ["/Apps/Tally", "hook", "codex"]"#))
    #expect(Connector.settingNotify(in: updated, executable: "/New/Tally") == updated.replacingOccurrences(of: "/Apps/", with: "/New/"))
  }

  @Test func `codex notify leaves someone else's command alone`() {
    #expect(Connector.settingNotify(in: "notify = [\"terminal-notifier\"]\n", executable: "/Apps/Tally") == nil)
  }

  @Test func `paths with quotes survive the shell`() {
    let connector = Connector(executable: "/Users/o'neil/Tally", home: URL(fileURLWithPath: "/tmp"))
    #expect(connector.command(for: "claude") == #"'/Users/o'\''neil/Tally' hook claude"#)
  }
}
