import AppKit
import OSLog
import TallyKit

/// Ties the board of sessions to the deck: paints keys, turns presses into jumps, and quiets a
/// key when you go to its app yourself.
///
/// Idle cost is nothing: it wakes for a signal, a key press or an app switch, and the animation
/// clock exists only while some key is working or wants you. Each frame is drawn once and then
/// reused, so animating is just resending bytes.
final class Desk {
  private(set) var board = Board()
  let deck = Deck()
  /// Called whenever what wants you may have changed, for the menu bar.
  var onChange: () -> Void = {}

  private var painted: [KeyFace] = []
  /// Encoded images by face, so animating is just resending bytes.
  private var frames: [KeyFace: [UInt8]] = [:]
  private var pressedAt: [Int: Date] = [:]
  private var clock: Timer?
  private var tick = 0

  /// Holding a key this long forgets its session instead of jumping to it.
  private static let longPress: TimeInterval = 0.6
  private static let brightness = 70
  private let log = Logger(subsystem: "tally", category: "desk")

  init() {
    deck.onConnect = { [unowned self] model in
      deck.reset()
      deck.setBrightness(Self.brightness)
      painted = Array(repeating: .blank, count: model.keyCount)
      frames = [:]
      board.resize(to: model.keyCount)
      paint(board.keys.indices)
    }
    deck.onDisconnect = { [unowned self] in
      painted = []
      board.resize(to: 0)
    }
    deck.onKey = { [unowned self] key, isDown in press(key, isDown: isDown) }

    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [unowned self] notification in
      let app = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
      MainActor.assumeIsolated {
        guard let app else { return }
        paint(board.acknowledge(app: app, at: .now))
        settled()
      }
    }
  }

  /// Sessions that want you right now.
  var waitingOnYou: Int {
    board.sessions.values.count { $0.status.wantsYou }
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
    guard let model = deck.model else { return }
    for key in keys where painted.indices.contains(key) {
      let face = KeyFace(board.session(onKey: key), light: flashLit ? 1 : 0, phase: tick)
      guard face != painted[key] else { continue }
      if frames.count > 512 { frames = [:] }
      let image = frames[face] ?? model.encode(face.pixels(side: model.side))
      frames[face] = image
      painted[key] = face
      deck.show(image, onKey: key)
    }
  }

  /// The flash's beat: five frames on, five off.
  private var flashLit: Bool { tick / 5 % 2 == 0 }

  /// Runs the animation clock only while a key is working or wants you, and tells the menu bar.
  private func settled() {
    let animating = board.keys.indices.contains { key in
      guard let status = board.session(onKey: key)?.status else { return false }
      return status == .working || status.wantsYou
    }
    if animating, clock == nil {
      clock = Timer.scheduledTimer(withTimeInterval: 1.0 / 8, repeats: true) { [unowned self] _ in
        MainActor.assumeIsolated {
          tick += 1
          paint(board.keys.indices)
        }
      }
    } else if !animating {
      clock?.invalidate()
      clock = nil
      tick = 0
    }
    onChange()
  }
}
