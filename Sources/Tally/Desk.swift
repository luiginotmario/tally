import Foundation
import OSLog
import TallyKit

/// Ties the board of sessions to the deck: paints keys, turns presses into jumps, keeps the clocks.
///
/// Idle cost is nothing: it only wakes for a signal, a key press, or the moment a key is due to
/// start flashing, and the flash timer exists only while something is overdue.
final class Desk {
  private(set) var board = Board()
  let deck = Deck()
  /// Called whenever what wants you may have changed, for the menu bar.
  var onChange: () -> Void = {}

  private var painted: [KeyFace] = []
  private var ramps: [Int: Task<Void, Never>] = [:]
  private var pressedAt: [Int: Date] = [:]
  private var nudge: Timer?
  private var flash: Timer?
  private var flashLit = true

  /// Holding a key this long forgets its session instead of jumping to it.
  private static let longPress: TimeInterval = 0.6
  private static let brightness = 70
  private let log = Logger(subsystem: "tally", category: "desk")

  init() {
    deck.onConnect = { [unowned self] model in
      deck.reset()
      deck.setBrightness(Self.brightness)
      painted = Array(repeating: .blank, count: model.keyCount)
      board.resize(to: model.keyCount)
      paint(board.keys.indices)
    }
    deck.onDisconnect = { [unowned self] in
      ramps.values.forEach { $0.cancel() }
      painted = []
      board.resize(to: 0)
    }
    deck.onKey = { [unowned self] key, isDown in press(key, isDown: isDown) }
  }

  /// Sessions that want you and haven't been looked at yet.
  var waitingOnYou: Int {
    board.sessions.values.count { $0.status.wantsYou && !$0.seen }
  }

  func receive(_ signal: Signal) {
    log.info("\(signal.agent, privacy: .public) \(signal.title, privacy: .public): \(signal.status.rawValue, privacy: .public)")
    paint(board.apply(signal, at: .now))
    settled()
  }

  /// Leaves the deck dark when the app quits.
  func blank() {
    deck.reset()
  }

  // MARK: - Presses

  private func press(_ key: Int, isDown: Bool) {
    guard !isDown else { pressedAt[key] = .now; return }
    guard let start = pressedAt.removeValue(forKey: key) else { return }
    if Date.now.timeIntervalSince(start) >= Self.longPress {
      paint(board.dismiss(key: key))
    } else if let session = board.acknowledge(key: key, at: .now) {
      session.bringToFront()
      paint([key])
    }
    settled()
  }

  // MARK: - Painting

  private func paint(_ keys: some Sequence<Int>) {
    let now = Date.now
    for key in keys where painted.indices.contains(key) {
      let session = board.session(onKey: key)
      let overdue = session.map { board.isOverdue($0, at: now) } ?? false
      let face = KeyFace(session, light: overdue && !flashLit ? 0 : 1)
      guard face != painted[key] else { continue }

      ramps[key]?.cancel()
      let lightingUp = face.status?.wantsYou == true && painted[key].status != face.status
      if lightingUp { ramp(key, to: face) } else { show(face, onKey: key) }
    }
  }

  /// Brings a key's lamp up over a few frames: a steep start and a long tail, like a bulb warming.
  private func ramp(_ key: Int, to face: KeyFace) {
    let frames = 6
    ramps[key] = Task {
      for frame in 1...frames {
        guard !Task.isCancelled else { return }
        var step = face
        step.light = 1 - pow(1 - Double(frame) / Double(frames), 5)
        show(step, onKey: key)
        try? await Task.sleep(for: .milliseconds(50))
      }
    }
  }

  private func show(_ face: KeyFace, onKey key: Int) {
    guard let model = deck.model else { return }
    painted[key] = face
    deck.show(model.encode(face.pixels(side: model.side)), onKey: key)
  }

  // MARK: - Clocks

  /// Re-arms the timers after anything changed, and tells the menu bar.
  private func settled() {
    let now = Date.now
    nudge?.invalidate()
    nudge = board.nextNudge(after: now).map { due in
      Timer.scheduledTimer(withTimeInterval: due.timeIntervalSince(now) + 0.05, repeats: false) { [unowned self] _ in
        MainActor.assumeIsolated {
          paint(board.keys.indices)
          settled()
        }
      }
    }

    let anyOverdue = board.keys.indices.contains { key in
      board.session(onKey: key).map { board.isOverdue($0, at: now) } ?? false
    }
    if anyOverdue, flash == nil {
      flash = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [unowned self] _ in
        MainActor.assumeIsolated {
          flashLit.toggle()
          paint(board.keys.indices)
        }
      }
    } else if !anyOverdue {
      flash?.invalidate()
      flash = nil
      flashLit = true
    }
    onChange()
  }
}
