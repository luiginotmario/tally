import Foundation

/// Every session the app knows about, and which physical key shows which one.
///
/// Keys are sticky: a session keeps its key until it closes or is pushed off a full deck
/// by a session that wants you, so a key's meaning never shifts under your hand.
public struct Board: Sendable {
  public struct Session: Sendable, Equatable {
    public let id: String
    public var agent: String
    public var title: String
    public var status: Status
    /// When `status` last changed.
    public var since: Date
    public var origin: Origin?
    /// Where the agent is working.
    public var cwd: String
  }

  public private(set) var sessions: [String: Session] = [:]
  /// One entry per physical key, holding the id of the session it shows.
  public private(set) var keys: [String?]

  public init(keyCount: Int = 0) {
    keys = Array(repeating: nil, count: keyCount)
  }

  public func session(onKey key: Int) -> Session? {
    keys.indices.contains(key) ? keys[key].flatMap { sessions[$0] } : nil
  }

  /// Applies a signal and returns the keys whose face changed.
  @discardableResult
  public mutating func apply(_ signal: Signal, at now: Date) -> Set<Int> {
    guard signal.status != .closed else { return remove(signal.session) }

    var session = sessions[signal.session]
      ?? Session(id: signal.session, agent: signal.agent, title: signal.title,
                 status: signal.status, since: now, origin: signal.origin, cwd: signal.cwd)
    if session.status != signal.status {
      session.status = signal.status
      session.since = now
    }
    session.origin = signal.origin ?? session.origin
    let changed = sessions[signal.session] != session
    sessions[signal.session] = session

    var touched = place(signal.session)
    if changed, let key = keys.firstIndex(of: signal.session) { touched.insert(key) }
    return touched
  }

  /// You pressed the key, so you're on it: the key goes quiet.
  @discardableResult
  public mutating func acknowledge(key: Int, at now: Date) -> Session? {
    guard let session = session(onKey: key) else { return nil }
    quiet(session.id, at: now)
    return sessions[session.id]
  }

  /// You switched to an app yourself. If exactly one session there wants you, you're looking at
  /// it; with several, there's no telling which, so they stay lit until each hears from you.
  @discardableResult
  public mutating func acknowledge(app: String, at now: Date) -> Set<Int> {
    let wanting = sessions.values.filter { $0.status.wantsYou && $0.origin?.app == app }
    guard wanting.count == 1, let session = wanting.first else { return [] }
    quiet(session.id, at: now)
    return keys.firstIndex(of: session.id).map { [$0] } ?? []
  }

  private mutating func quiet(_ id: String, at now: Date) {
    guard sessions[id]?.status.wantsYou == true else { return }
    sessions[id]?.status = .idle
    sessions[id]?.since = now
  }

  /// Forgets a session for good (a long press), for agents that died without saying so.
  @discardableResult
  public mutating func dismiss(key: Int) -> Set<Int> {
    guard let id = keys.indices.contains(key) ? keys[key] : nil else { return [] }
    return remove(id)
  }

  /// Follows the deck: called when one is plugged in, swapped or pulled out.
  public mutating func resize(to count: Int) {
    keys = Array(keys.prefix(count)) + Array(repeating: nil, count: max(0, count - keys.count))
    for id in queue() { _ = place(id) }
  }

  // MARK: - Key assignment

  private mutating func remove(_ id: String) -> Set<Int> {
    sessions[id] = nil
    guard let key = keys.firstIndex(of: id) else { return [] }
    keys[key] = nil
    var touched: Set<Int> = [key]
    if let next = queue().first { touched.formUnion(place(next)) }
    return touched
  }

  /// Gives a session a key if it has none: a free one, or one taken from a session that doesn't want you.
  private mutating func place(_ id: String) -> Set<Int> {
    guard !keys.contains(id), let session = sessions[id] else { return [] }
    if let free = keys.firstIndex(of: nil) {
      keys[free] = id
      return [free]
    }
    guard session.status.wantsYou,
          let quietest = keys.indices
            .compactMap({ key in self.session(onKey: key).map { (key: key, session: $0) } })
            .filter({ !$0.session.status.wantsYou })
            .min(by: { $0.session.since < $1.session.since })?.key
    else { return [] }
    keys[quietest] = id
    return [quietest]
  }

  /// Sessions without a key, the ones that want you first, then oldest first.
  private func queue() -> [String] {
    sessions.values
      .filter { !keys.contains($0.id) }
      .sorted { ($0.status.wantsYou ? 0 : 1, $0.since) < ($1.status.wantsYou ? 0 : 1, $1.since) }
      .map(\.id)
  }
}
