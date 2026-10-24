import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Moves raw key pictures in and out of image files.
public enum Pixels {
  /// Wraps RGBA rows (from the top, `side` square) in a `CGImage`.
  public static func image(_ rgba: [UInt8], side: Int) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
    return CGImage(
      width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }

  public static func encode(_ rgba: [UInt8], side: Int, as type: UTType, quality: Double = 0.92) -> [UInt8] {
    let data = NSMutableData()
    guard let image = image(rgba, side: side),
          let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
    else { return [] }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    CGImageDestinationFinalize(destination)
    return [UInt8](data as Data)
  }
}
