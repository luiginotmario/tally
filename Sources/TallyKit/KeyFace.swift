import AppKit
import CoreText

/// What one key shows. Equatable, so a key that hasn't changed is never sent again.
///
/// The idea is a tally light: a quiet key is dark like a powered-down panel, and a key
/// that wants you becomes the lamp itself, warm white when an agent is done, red when
/// it's blocked on you.
public struct KeyFace: Equatable, Sendable {
  /// `nil` is an unused key.
  public var status: Status?
  public var title: String
  public var agent: String
  /// How far the lamp is on, 0...1. Drives the light-up ramp and the overdue flash.
  public var light: Double

  public static let blank = KeyFace(status: nil, title: "", agent: "", light: 0)

  public init(status: Status?, title: String, agent: String, light: Double) {
    self.status = status
    self.title = title
    self.agent = agent
    self.light = light
  }

  public init(_ session: Board.Session?, light: Double = 1) {
    guard let session, session.status != .closed else { self = .blank; return }
    self.init(status: session.status, title: session.title, agent: session.agent,
              light: session.status.wantsYou ? light : 0)
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

    context.setFillColor(palette.background)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    guard status != nil else { return }

    // Top row: the agent's mark (or its name, for agents without one) and, on a dark key, the lamp.
    let topLine = side - inset - 5 * unit
    let markSize = 15 * unit
    if let mark = AgentMark.image(for: agent.lowercased()) {
      draw(mark, in: CGRect(x: inset, y: side - inset - markSize, width: markSize, height: markSize),
           color: palette.agent, context: context)
    } else {
      let label = text(agent.lowercased(), size: 9 * unit, weight: .medium, color: palette.agent)
      draw(label, at: CGPoint(x: inset, y: topLine), width: side - 2 * inset - 10 * unit, in: context)
    }
    if let lamp = palette.lamp {
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

  /// Draws a mark as a silhouette in one colour.
  private func draw(_ mark: NSImage, in rect: CGRect, color: CGColor, context: CGContext) {
    context.saveGState()
    context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    mark.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    context.setBlendMode(.sourceIn)
    context.setFillColor(color)
    context.fill(rect)
    context.endTransparencyLayer()
    context.restoreGState()
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
