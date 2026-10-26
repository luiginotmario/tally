import CoreGraphics
import Foundation
import ImageIO

/// A picture spread across the whole deck like a wallpaper. Each key is a window onto its own
/// part, a key pitch apart, so the picture carries on across the gaps between keys.
public final class Scene {
  private let image: CGImage
  private let columns: Int
  private let rows: Int
  /// How much to scale the picture's light so it lands at `Scene.level`.
  private let exposure: Double

  /// The average brightness every picture is brought to: calm enough to stay behind the keys.
  private static let level = 0.27
  /// How far a dark picture may be brightened before its lights blow out.
  private static let maxBoost = 3.0
  /// How much colour is taken out, so the picture doesn't compete with the keys.
  private static let mute = 0.35

  public init?(contentsOf url: URL, columns: Int, rows: Int) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    self.image = image
    self.columns = columns
    self.rows = rows
    exposure = min(Self.maxBoost, Self.level / max(0.01, Self.brightness(of: image)))
  }

  /// The picture's average brightness, 0...1, from a tiny copy of it.
  private static func brightness(of image: CGImage) -> Double {
    var pixels = [UInt8](repeating: 0, count: 32 * 18 * 4)
    pixels.withUnsafeMutableBytes { bytes in
      CGContext(data: bytes.baseAddress, width: 32, height: 18, bitsPerComponent: 8, bytesPerRow: 32 * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?
        .draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 18))
    }
    let sum = stride(from: 0, to: pixels.count, by: 4).reduce(0) { $0 + Int(pixels[$1]) + Int(pixels[$1 + 1]) + Int(pixels[$1 + 2]) }
    return Double(sum) / Double(32 * 18 * 3 * 255)
  }

  /// Draws key `key`'s part of the picture over a key `side` pixels square.
  func draw(key: Int, in context: CGContext, side: CGFloat) {
    let pitch = side * KeyFace.pitch
    let canvas = CGSize(width: pitch * CGFloat(columns - 1) + side, height: pitch * CGFloat(rows - 1) + side)
    // Fill the deck and centre the picture, cropping whatever overflows.
    let scale = max(canvas.width / CGFloat(image.width), canvas.height / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    let column = CGFloat(key % columns), row = CGFloat(key / columns)
    let origin = CGPoint(x: -column * pitch - (size.width - canvas.width) / 2,
                         y: -(canvas.height - side - row * pitch) - (size.height - canvas.height) / 2)   // rows run down, CG runs up
    let frame = CGRect(origin: origin, size: size)
    context.interpolationQuality = .high
    context.draw(image, in: frame)

    let key = CGRect(x: 0, y: 0, width: side, height: side)
    context.saveGState()
    // Brighten a dark picture by adding it onto itself; darkness stays dark, the lights come up.
    var extra = exposure - 1
    context.setBlendMode(.plusLighter)
    while extra > 0 {
      context.setAlpha(min(1, extra))
      context.draw(image, in: frame)
      extra -= 1
    }
    context.setAlpha(1)
    context.setBlendMode(.saturation)           // take some colour out
    context.setFillColor(CGColor(gray: 0.5, alpha: Self.mute))
    context.fill(key)
    context.restoreGState()
    if exposure < 1 {
      context.setFillColor(CGColor(gray: 0, alpha: 1 - exposure))
      context.fill(key)
    }
  }
}
