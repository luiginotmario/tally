import Foundation

/// Where an agent is, from the point of view of the person at the desk.
public enum Status: String, Codable, Sendable, CaseIterable {
  /// Open, with nothing in flight.
  case idle
  case working
  /// Finished a turn: your move.
  case done
  /// Stuck on a permission prompt or a question.
  case waiting
  /// The session is gone; its key is free again.
  case closed

  /// The two states the deck exists to point at.
  public var wantsYou: Bool { self == .done || self == .waiting }
}

/// How to bring a session's window back to the front.
public enum Focus: Codable, Sendable, Equatable {
  /// A terminal tab, found by its tty (`/dev/ttys004`).
  case terminal(app: String, tty: String)
  /// An editor window, found by the folder it has open.
  case folder(app: String, path: String)
  /// Only the app is known.
  case app(String)
}

/// One message from an agent: the only thing that crosses from the `tally` command to the app.
public struct Signal: Codable, Sendable, Equatable {
  public var session: String
  public var agent: String
  public var status: Status
  public var cwd: String
  public var focus: Focus?

  public init(session: String, agent: String, status: Status, cwd: String, focus: Focus? = nil) {
    self.session = session
    self.agent = agent
    self.status = status
    self.cwd = cwd
    self.focus = focus
  }

  /// The project's folder name, which is what people recognise a session by.
  public var title: String {
    let name = (cwd as NSString).lastPathComponent
    return name.isEmpty || name == "/" ? agent : name
  }
}
