import Foundation
import Testing
@testable import TallyKit

struct BoardTests {
  let start = Date(timeIntervalSince1970: 0)

  func signal(_ session: String, _ status: Status) -> Signal {
    Signal(session: session, agent: "claude", status: status, cwd: "/Users/me/Projects/\(session)")
  }

  @Test func `sessions take the first free key and keep it`() {
    var board = Board(keyCount: 3)
    board.apply(signal("a", .working), at: start)
    board.apply(signal("b", .working), at: start)
    board.apply(signal("a", .done), at: start)
    #expect(board.keys == ["a", "b", nil])
    #expect(board.session(onKey: 0)?.title == "a")
  }

  @Test func `a closed session frees its key for the next in line`() {
    var board = Board(keyCount: 1)
    board.apply(signal("a", .working), at: start)
    board.apply(signal("b", .working), at: start)
    #expect(board.keys == ["a"])
    let touched = board.apply(signal("a", .closed), at: start)
    #expect(board.keys == ["b"])
    #expect(touched == [0])
  }

  @Test func `on a full deck, a session that wants you pushes off the quietest one`() {
    var board = Board(keyCount: 2)
    board.apply(signal("old", .working), at: start)
    board.apply(signal("new", .working), at: start.addingTimeInterval(10))
    board.apply(signal("late", .waiting), at: start.addingTimeInterval(20))
    #expect(board.keys == ["late", "new"])
  }

  @Test func `a quiet session never pushes anyone off`() {
    var board = Board(keyCount: 1)
    board.apply(signal("a", .done), at: start)
    board.apply(signal("b", .working), at: start)
    #expect(board.keys == ["a"])
  }

  @Test func `pressing a key quiets it, finished or waiting`() {
    var board = Board(keyCount: 2)
    board.apply(signal("a", .done), at: start)
    board.apply(signal("b", .waiting), at: start)
    board.acknowledge(key: 1, at: start)
    #expect(board.session(onKey: 1)?.status == .idle)
    #expect(board.session(onKey: 0)?.status == .done)
  }

  @Test func `switching to an app quiets the one session there that wants you`() {
    var board = Board(keyCount: 3)
    var mine = signal("a", .done)
    mine.origin = Origin(app: "com.mitchellh.ghostty")
    board.apply(mine, at: start)
    board.apply(signal("b", .done), at: start)
    #expect(board.acknowledge(app: "com.mitchellh.ghostty", at: start) == [0])
    #expect(board.session(onKey: 0)?.status == .idle)
    #expect(board.session(onKey: 1)?.status == .done)
  }

  @Test func `with several waiting in one app, switching to it can't tell which you're on`() {
    var board = Board(keyCount: 2)
    for id in ["a", "b"] {
      var waiting = signal(id, .waiting)
      waiting.origin = Origin(app: "com.anthropic.claudefordesktop")
      board.apply(waiting, at: start)
    }
    #expect(board.acknowledge(app: "com.anthropic.claudefordesktop", at: start).isEmpty)
    #expect(board.sessions.values.allSatisfy { $0.status == .waiting })
  }

  @Test func `pressing a finished key quiets it`() {
    var board = Board(keyCount: 1)
    board.apply(signal("a", .done), at: start)
    board.acknowledge(key: 0, at: start)
    #expect(board.session(onKey: 0)?.status == .idle)
  }

  @Test func `repeating the same status doesn't restart the clock`() {
    var board = Board(keyCount: 1)
    board.apply(signal("a", .working), at: start)
    let touched = board.apply(signal("a", .working), at: start.addingTimeInterval(30))
    #expect(touched.isEmpty)
    #expect(board.session(onKey: 0)?.since == start)
  }

  @Test func `unplugging and replugging a deck keeps every session`() {
    var board = Board(keyCount: 2)
    board.apply(signal("a", .working), at: start)
    board.apply(signal("b", .done), at: start)
    board.resize(to: 0)
    board.resize(to: 6)
    #expect(Set(board.keys.compactMap { $0 }) == ["a", "b"])
    #expect(board.keys.count == 6)
  }
}
