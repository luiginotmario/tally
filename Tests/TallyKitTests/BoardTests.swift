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

  @Test func `keys start nagging after five minutes, unless you pressed them`() {
    var board = Board(keyCount: 2)
    board.apply(signal("a", .done), at: start)
    board.apply(signal("b", .waiting), at: start)
    let later = start.addingTimeInterval(Board.patience)
    #expect(board.nextNudge(after: start) == later)
    #expect(board.isOverdue(board.session(onKey: 0)!, at: later))

    board.acknowledge(key: 1, at: later)
    #expect(!board.isOverdue(board.session(onKey: 1)!, at: later))
    #expect(board.session(onKey: 1)?.status == .waiting)
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
