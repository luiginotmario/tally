import Foundation
import Testing
@testable import TallyKit

struct HookTests {
  func signal(_ json: String, agent: String = "claude") -> Signal? {
    Hook.signal(from: Data(json.utf8), agent: agent)
  }

  @Test(arguments: [
    ("SessionStart", Status.idle),
    ("UserPromptSubmit", .working),
    ("PostToolUse", .working),
    ("PermissionRequest", .waiting),
    ("Stop", .done),
    ("StopFailure", .done),
    ("SessionEnd", .closed),
  ])
  func `claude code events`(event: String, status: Status) {
    let result = signal(#"{"session_id":"s1","cwd":"/p/tally","hook_event_name":"\#(event)"}"#)
    #expect(result == Signal(session: "s1", agent: "claude", status: status, cwd: "/p/tally"))
  }

  @Test func `only notifications that ask for you count`() {
    #expect(signal(#"{"session_id":"s","hook_event_name":"Notification","notification_type":"permission_prompt"}"#)?.status == .waiting)
    #expect(signal(#"{"session_id":"s","hook_event_name":"Notification","notification_type":"idle_prompt"}"#) == nil)
    #expect(signal(#"{"session_id":"s","hook_event_name":"Notification","notification_type":"ToolPermission"}"#, agent: "gemini")?.status == .waiting)
  }

  @Test func `codex notify passes kebab-case json`() {
    let result = signal(#"{"type":"agent-turn-complete","thread-id":"t9","cwd":"/p/x","turn-id":"1"}"#, agent: "codex")
    #expect(result == Signal(session: "t9", agent: "codex", status: .done, cwd: "/p/x"))
  }

  @Test func `cursor uses conversation ids and workspace roots`() {
    let result = signal(#"{"conversation_id":"c1","hook_event_name":"stop","status":"completed","workspace_roots":["/p/site"],"cursor_version":"2.0"}"#, agent: "cursor")
    #expect(result == Signal(session: "c1", agent: "cursor", status: .done, cwd: "/p/site"))
    let aborted = signal(#"{"conversation_id":"c1","hook_event_name":"stop","status":"aborted"}"#, agent: "cursor")
    #expect(aborted?.status == .idle)
  }

  @Test func `an editor running claude's hooks is still named for itself`() {
    #expect(signal(#"{"conversation_id":"c","hook_event_name":"Stop","cursor_version":"2.0"}"#)?.agent == "cursor")
    #expect(signal(#"{"sessionId":"g","hookEventName":"Stop","cwd":"/p"}"#)?.agent == "grok")
  }

  @Test func `only prompt submission in cursor gets a reply`() {
    #expect(Hook.reply(to: Data(#"{"hook_event_name":"beforeSubmitPrompt"}"#.utf8)) == #"{"continue":true}"#)
    #expect(Hook.reply(to: Data(#"{"hook_event_name":"Stop"}"#.utf8)) == nil)
  }

  @Test func `garbage is ignored`() {
    #expect(signal("") == nil)
    #expect(signal(#"{"hook_event_name":"Stop"}"#) == nil)
    #expect(signal(#"{"session_id":"s","hook_event_name":"PreCompact"}"#) == nil)
  }

  @Test func `the title is the project folder`() {
    #expect(Signal(session: "s", agent: "codex", status: .idle, cwd: "/Users/me/Projects/paddock").title == "paddock")
    #expect(Signal(session: "s", agent: "codex", status: .idle, cwd: "").title == "codex")
  }
}
