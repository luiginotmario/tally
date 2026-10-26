import Foundation
import TallyKit

/// `tally` as a command: how agents reach the running app.
///
///     tally hook <agent> [json]       what agents' hooks run (JSON on stdin, or as the last argument)
///     tally done|working|waiting|idle|closed [--agent name]
///                                     for agents without hooks: put it in their instructions
///     tally connect                   registers the hook with every installed agent
///     tally preview <folder>          draws every key state to PNGs
enum Command {
  /// Runs the command in `arguments`, or returns nil when there isn't one and the app should start.
  static func run(_ arguments: [String]) -> Int32? {
    guard let verb = arguments.first else { return nil }
    let rest = Array(arguments.dropFirst())
    switch verb {
    case "hook":
      hook(agent: rest.first ?? "agent", inline: rest.dropFirst().last)
    case "connect":
      connect()
    case "preview":
      preview(into: URL(fileURLWithPath: rest.first ?? "."))
    case _ where Status(rawValue: verb) != nil:
      report(Status(rawValue: verb)!, agent: value(of: "--agent", in: rest))
    default:
      return nil
    }
    return 0
  }

  /// Never fails loudly: an agent's hook must not get in the agent's way.
  private static func hook(agent: String, inline: String?) {
    let payload = inline.map { Data($0.utf8) } ?? FileHandle.standardInput.readDataToEndOfFile()
    if let reply = Hook.reply(to: payload) { print(reply) }
    guard var signal = Hook.signal(from: payload, agent: agent) else { return }
    let origin = Origin.ofCaller(agent: signal.agent, session: signal.session)
    // Apps built on Cursor's engine (Grok Bot) send Cursor's payload; the app says who it really is.
    if signal.agent == "cursor", let app = origin.app.flatMap(AgentMark.agent(forApp:)) { signal.agent = app }
    signal.origin = origin
    Inbox.send(signal)
  }

  private static func report(_ status: Status, agent: String?) {
    let environment = ProcessInfo.processInfo.environment
    let agent = agent ?? environment["TALLY_AGENT"] ?? "agent"
    let cwd = FileManager.default.currentDirectoryPath
    // Without a session id from the agent, its terminal pane (or the folder) is the session.
    let origin = Origin.ofCaller(agent: agent, session: "")
    let session = environment["TALLY_SESSION"] ?? origin.pane ?? origin.tty ?? cwd
    Inbox.send(Signal(session: "\(agent):\(session)", agent: agent, status: status, cwd: cwd, origin: origin))
  }

  private static func connect() {
    let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
    for (agent, outcome) in Connector(executable: executable).connectAll() {
      switch outcome {
      case .connected: print("✓ \(agent)")
      case .failed(let reason): print("✗ \(agent): \(reason)")
      case .absent: break
      }
    }
  }

  private static func preview(into folder: URL) {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let side = 144
    let faces: [(String, KeyFace)] = [
      ("blank", .blank),
      ("idle", KeyFace(status: .idle, title: "paddock", agent: "claude", light: 0)),
      ("working", KeyFace(status: .working, title: "radar-detection", agent: "codex", light: 0)),
      ("done", KeyFace(status: .done, title: "tuvian-os", agent: "claude", light: 1)),
      ("done-flash", KeyFace(status: .done, title: "tuvian-os", agent: "claude", light: 0)),
      ("waiting", KeyFace(status: .waiting, title: "expert-capture", agent: "cursor", light: 1)),
      ("waiting-flash", KeyFace(status: .waiting, title: "expert-capture", agent: "cursor", light: 0)),
      ("gemini", KeyFace(status: .working, title: "loupe", agent: "gemini", light: 0)),
      ("grok", KeyFace(status: .done, title: "carry", agent: "grok", light: 1)),
      ("cursor", KeyFace(status: .idle, title: "shed", agent: "cursor", light: 0)),
    ]
    for (name, face) in faces {
      let png = Pixels.encode(face.pixels(side: side), side: side, as: .png)
      try? Data(png).write(to: folder.appending(path: "\(name).png"))
    }
    print(folder.path)
  }

  private static func value(of flag: String, in arguments: [String]) -> String? {
    arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
  }
}

