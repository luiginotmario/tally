import AppKit
import CoreText

/// What one key shows. Equatable, so a key that hasn't changed is never sent again.
///
/// The idea is a tally light: a quiet key is dark like a powered-down panel, and a key
/// that wants you becomes the lamp itself, warm white when an agent is done, red when
/// it's blocked on you.
public struct KeyFace: Hashable, Sendable {
  /// `nil` is an unused key.
  public var status: Status?
  public var title: String
  public var agent: String
  /// How far the lamp is on, 0...1. Drives the flash.
  public var light: Double
  /// Which frame of the working ping, 0..<`KeyFace.frames`.
  public var phase: Int

  /// The wave of light that spreads across the deck when an agent starts wanting you.
  public var ripple: Ripple?

  /// Frames in one loop of the working ping.
  public static let frames = 12

  public struct Ripple: Hashable, Sendable {
    /// Where the wave started, counted in keys from this one: right and down are positive.
    public var columns: Int
    public var rows: Int
    /// 0..<`Ripple.frames`.
    public var frame: Int
    /// Done or waiting: the wave is that lamp's colour.
    public var status: Status

    public static let frames = 10

    public init(columns: Int, rows: Int, frame: Int, status: Status) {
      self.columns = columns
      self.rows = rows
      self.frame = frame
      self.status = status
    }
  }

  public static let blank = KeyFace(status: nil, title: "", agent: "", light: 0)

  public init(status: Status?, title: String, agent: String, light: Double, phase: Int = 0) {
    self.status = status
    self.title = title
    self.agent = agent
    self.light = light
    self.phase = status == .working ? phase % Self.frames : 0
  }

  public init(_ session: Board.Session?, light: Double = 1, phase: Int = 0) {
    guard let session, session.status != .closed else { self = .blank; return }
    self.init(status: session.status, title: session.title, agent: session.agent,
              light: session.status.wantsYou ? light : 0, phase: phase)
  }

  /// Draws the face upright, `side` pixels square, as RGBA rows from the top.
  public func pixels(side: Int) -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: side * side * 4)
    buffer.withUnsafeMutableBytes { bytes in
      guard let context = CGContext(
        data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8,
        bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return }
      draw(in: context, side: CGFloat(side))
    }
    return buffer
  }

  // MARK: - Drawing

  private struct Palette {
    let background: CGColor
    let title: CGColor
    let agent: CGColor
    /// The small lamp in the corner; absent once the whole key is the lamp.
    let lamp: (color: CGColor, filled: Bool)?
  }

  private typealias RGB = (r: Double, g: Double, b: Double)
  private static let warm: RGB = (0.95, 0.93, 0.89)
  private static let red: RGB = (0.85, 0.19, 0.15)

  private var palette: Palette {
    func gray(_ white: Double) -> CGColor { CGColor(gray: white, alpha: 1) }
    func color(_ rgb: RGB, _ level: Double = 1) -> CGColor {
      CGColor(srgbRed: rgb.r * level, green: rgb.g * level, blue: rgb.b * level, alpha: 1)
    }
    switch status {
    case nil, .closed:
      return Palette(background: gray(0), title: gray(0), agent: gray(0), lamp: nil)
    case .idle:
      return Palette(background: gray(0), title: gray(0.42), agent: gray(0.28), lamp: (gray(0.32), false))
    case .working:
      return Palette(background: gray(0), title: gray(0.86), agent: gray(0.48), lamp: (gray(0.86), true))
    case .done, .waiting:
      // Lit, the key is the lamp and the text is ink on it; dark (the off beat of a flash),
      // the text glows in the lamp's colour instead.
      let lamp = status == .done ? Self.warm : Self.red
      guard light >= 0.5 else {
        return Palette(background: gray(0), title: color(lamp), agent: color(lamp, 0.6), lamp: nil)
      }
      let ink = status == .done ? gray(0.07) : gray(1)
      let agent = status == .done ? gray(0.4) : color((1, 0.84, 0.81))
      return Palette(background: color(lamp, light), title: ink, agent: agent, lamp: nil)
    }
  }

  private func draw(in context: CGContext, side: CGFloat) {
    let palette = palette
    let unit = side / 72                       // everything is laid out on a 72-point key
    let inset = 7 * unit

    // Black around a rounded card, so each key reads as a tile inside its bezel.
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    defer { if let ripple { drawRipple(ripple, in: context, side: side) } }
    guard let status else { return }
    context.saveGState()
    context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 2 * unit, dy: 2 * unit),
                           cornerWidth: 11 * unit, cornerHeight: 11 * unit, transform: nil))
    context.clip()
    context.setFillColor(palette.background)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    if !status.wantsYou || light < 0.5 {
      drawGradient(in: context, side: side, strength: status == .idle ? 0.55 : 1)
    }
    context.restoreGState()

    // Top row: the agent's mark (or its name, for agents without one) and, on a dark key, the lamp.
    let topLine = side - inset - 5 * unit
    let markSize = 18 * unit
    let markRect = CGRect(x: inset - 1 * unit, y: side - inset - markSize + 1 * unit, width: markSize, height: markSize)
    switch AgentMark.art(for: agent.lowercased()) {
    case .color(let image):
      draw(image, in: markRect, tint: nil, context: context)
    case .ink(let image):
      draw(image, in: markRect.insetBy(dx: 2 * unit, dy: 2 * unit), tint: palette.agent, context: context)
    case nil:
      let label = text(agent.lowercased(), size: 9 * unit, weight: .medium, color: palette.agent)
      draw(label, at: CGPoint(x: inset, y: topLine), width: side - 2 * inset - 10 * unit, in: context)
    }
    if status == .working {
      drawPing(in: context, side: side, unit: unit, inset: inset, color: palette.title)
    } else if let lamp = palette.lamp {
      let dot = CGRect(x: side - inset - 6 * unit, y: side - inset - 6 * unit - 3.5 * unit, width: 6 * unit, height: 6 * unit)
      if lamp.filled {
        context.setFillColor(lamp.color)
        context.fillEllipse(in: dot)
      } else {
        context.setStrokeColor(lamp.color)
        context.setLineWidth(1.25 * unit)
        context.strokeEllipse(in: dot.insetBy(dx: 0.625 * unit, dy: 0.625 * unit))
      }
    }

    // Bottom: the project name, on up to two lines.
    let name = text(title, size: 14 * unit, weight: .semibold, color: palette.title)
    for (index, titleLine) in wrap(name, width: side - 2 * inset).reversed().enumerated() {
      draw(titleLine, at: CGPoint(x: inset, y: inset + 1 * unit + CGFloat(index) * 15 * unit),
           width: side - 2 * inset, in: context)
    }
  }

  /// Draws an image, or with a tint, its silhouette in that one colour.
  private func draw(_ image: NSImage, in rect: CGRect, tint: CGColor?, context: CGContext) {
    context.saveGState()
    context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    if let tint {
      context.setBlendMode(.sourceIn)
      context.setFillColor(tint)
      context.fill(rect)
    }
    context.endTransparencyLayer()
    context.restoreGState()
  }

  /// This key's slice of the wave. Each key draws the ring around the same point on the deck,
  /// a key pitch apart, so the wave reads as one ring crossing the gaps between keys.
  private func drawRipple(_ ripple: Ripple, in context: CGContext, side: CGFloat) {
    let pitch = side * 1.35                    // a key plus the gap to the next one
    let center = CGPoint(x: side / 2 + CGFloat(ripple.columns) * pitch, y: side / 2 - CGFloat(ripple.rows) * pitch)
    let t = Double(ripple.frame) / Double(Ripple.frames - 1)
    let radius = (0.4 + 3 * (1 - pow(1 - t, 2))) * pitch        // quick to leave, slow to settle
    let width = 0.55 * pitch
    let lamp = ripple.status == .waiting ? Self.red : Self.warm
    let alpha = 0.7 * (1 - t)
    let colors: [CGColor] = [0, alpha, 0].map { (level: Double) in CGColor(srgbRed: lamp.r, green: lamp.g, blue: lamp.b, alpha: level) }
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: [0, 0.5, 1])!
    context.saveGState()
    context.setBlendMode(.screen)
    context.drawRadialGradient(gradient, startCenter: center, startRadius: max(0, radius - width),
                               endCenter: center, endRadius: radius + width, options: [])
    context.restoreGState()
  }

  /// A dark key wears its agent's colour: a deep gradient of it, lit from the top. Idle keys
  /// get a dimmer one, so the working ones stand out.
  private func drawGradient(in context: CGContext, side: CGFloat, strength: Double) {
    let accent = AgentMark.accent(for: agent.lowercased()) ?? (0.62, 0.58, 0.54)
    func shade(_ level: Double) -> CGColor {
      CGColor(srgbRed: accent.r * level * strength, green: accent.g * level * strength, blue: accent.b * level * strength, alpha: 1)
    }
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [shade(0.34), shade(0.09)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: .zero, options: [])
  }

  /// The working ping: a steady dot with a ring that keeps spreading out of it and fading,
  /// fast at first and settling (an ease-out), the way a ripple does.
  private func drawPing(in context: CGContext, side: CGFloat, unit: CGFloat, inset: CGFloat, color: CGColor) {
    let t = Double(phase) / Double(Self.frames)
    let center = CGPoint(x: side - inset - 3 * unit, y: side - inset - 6.5 * unit)
    let dot = 2.6 * unit
    context.setFillColor(color)
    context.fillEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: 2 * dot, height: 2 * dot))
    let ring = 3 * unit + 6 * unit * (1 - pow(1 - t, 3))
    context.setStrokeColor(color.copy(alpha: 0.6 * (1 - t)) ?? color)
    context.setLineWidth(1.2 * unit)
    context.strokeEllipse(in: CGRect(x: center.x - ring, y: center.y - ring, width: 2 * ring, height: 2 * ring))
  }

  private func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: CGColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight),
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
      .kern: -0.01 * size,
    ])
  }

  /// Breaks a title over two lines; `draw` ends the second with an ellipsis if it still doesn't fit.
  private func wrap(_ text: NSAttributedString, width: CGFloat) -> [NSAttributedString] {
    let firstLength = CTTypesetterSuggestLineBreak(CTTypesetterCreateWithAttributedString(text), 0, width)
    guard firstLength < text.length else { return [text] }
    return [text.attributedSubstring(from: NSRange(location: 0, length: firstLength)),
            text.attributedSubstring(from: NSRange(location: firstLength, length: text.length - firstLength))]
  }

  private func draw(_ text: NSAttributedString, at origin: CGPoint, width: CGFloat, in context: CGContext) {
    guard text.length > 0 else { return }
    let line = CTLineCreateWithAttributedString(text)
    let ellipsis = CTLineCreateWithAttributedString(
      NSAttributedString(string: "…", attributes: text.attributes(at: 0, effectiveRange: nil)))
    context.textPosition = origin
    CTLineDraw(CTLineCreateTruncatedLine(line, Double(width), .end, ellipsis) ?? line, context)
  }
}
