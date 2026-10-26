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

/// Everything known about where a session lives, so a key press can find its way back.
///
/// It's captured from the agent's environment when the hook runs, and the app tries the most
/// precise route the session's app supports: a deep link to the session itself, the exact
/// terminal pane, the editor window for the folder, or else just the app.
public struct Origin: Codable, Sendable, Equatable {
  /// Bundle id of the app the agent runs in (a terminal, an editor, a desktop agent app).
  public var app: String?
  /// A URL that opens this exact session in a desktop agent app.
  public var link: String?
  /// The terminal's own id for the pane (cmux).
  public var pane: String?
  /// The tty the agent is attached to (Terminal, iTerm).
  public var tty: String?
  /// The app opens the right window when asked to open the folder (editors).
  public var opensByFolder: Bool

  public init(app: String? = nil, link: String? = nil, pane: String? = nil, tty: String? = nil,
              opensByFolder: Bool = false) {
    self.app = app
    self.link = link
    self.pane = pane
    self.tty = tty
    self.opensByFolder = opensByFolder
  }
}

/// One message from an agent: the only thing that crosses from the `tally` command to the app.
public struct Signal: Codable, Sendable, Equatable {
  public var session: String
  public var agent: String
  public var status: Status
  public var cwd: String
  public var origin: Origin?

  public init(session: String, agent: String, status: Status, cwd: String, origin: Origin? = nil) {
    self.session = session
    self.agent = agent
    self.status = status
    self.cwd = cwd
    self.origin = origin
  }

  /// The project's folder name, which is what people recognise a session by.
  public var title: String {
    let name = (cwd as NSString).lastPathComponent
    return name.isEmpty || name == "/" ? agent : name
  }
}
