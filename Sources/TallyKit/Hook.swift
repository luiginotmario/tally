import Foundation

/// Reads the JSON an agent hands its hooks and turns it into a signal.
///
/// Most agents now share one hook schema with small spelling differences (snake_case or
/// camelCase, `cwd` or a list of workspace roots, `Stop` or `AfterAgent`), so one reader
/// covers all of them instead of one parser per agent.
public enum Hook {
  /// - Parameters:
  ///   - payload: the JSON from stdin, or from the last argument for agents that pass it that way.
  ///   - agent: which agent's config the hook was registered in.
  public static func signal(from payload: Data, agent: String) -> Signal? {
    guard let fields = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
          let session = string(in: fields, "session_id", "sessionId", "conversation_id", "conversationId", "thread-id"),
          let event = string(in: fields, "hook_event_name", "hookEventName", "type"),
          let status = status(event: event, detail: string(in: fields, "notification_type", "notificationType", "status"))
    else { return nil }

    let cwd = string(in: fields, "cwd", "workspaceRoot")
      ?? strings(in: fields, "workspace_roots", "workspacePaths").first
      ?? ""
    return Signal(session: session, agent: source(of: fields, registeredFor: agent), status: status, cwd: cwd)
  }

  /// What the agent insists on reading back on stdout, if anything. Everything else gets silence.
  public static func reply(to payload: Data) -> String? {
    guard let fields = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
          let event = string(in: fields, "hook_event_name", "hookEventName") else { return nil }
    return normalized(event) == "beforesubmitprompt" ? #"{"continue":true}"# : nil
  }

  static func status(event: String, detail: String?) -> Status? {
    switch normalized(event) {
    case "sessionstart":
      return .idle
    case "userpromptsubmit", "beforesubmitprompt", "beforeagent", "posttooluse", "aftertool":
      return .working
    case "stop":
      // An editor reports a turn you cancelled yourself; you're already looking at it.
      return detail.map(normalized) == "aborted" ? .idle : .done
    case "stopfailure", "afteragent", "agentturncomplete":
      return .done
    case "permissionrequest":
      return .waiting
    case "notification":
      let asksForYou: Set = ["permissionprompt", "elicitationdialog", "agentneedsinput", "toolpermission"]
      return detail.map(normalized).map(asksForYou.contains) == true ? .waiting : nil
    case "sessionend":
      return .closed
    default:
      return nil
    }
  }

  /// Some editors also run hooks registered for other agents, so the payload decides who's speaking.
  private static func source(of fields: [String: Any], registeredFor agent: String) -> String {
    if fields["cursor_version"] != nil { return "cursor" }
    if fields["hookEventName"] != nil, agent == "claude" { return "grok" }
    return agent
  }

  private static func normalized(_ name: String) -> String {
    name.lowercased().filter { $0 != "_" && $0 != "-" }
  }

  private static func string(in fields: [String: Any], _ keys: String...) -> String? {
    keys.lazy.compactMap { fields[$0] as? String }.first { !$0.isEmpty }
  }

  private static func strings(in fields: [String: Any], _ keys: String...) -> [String] {
    keys.lazy.compactMap { fields[$0] as? [String] }.first ?? []
  }
}
