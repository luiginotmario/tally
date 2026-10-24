import Foundation

/// One kind of Stream Deck, and how to speak to it over USB HID.
///
/// There are two wire protocols: the Mini family takes BMP images in 1024-byte reports with a
/// 16-byte header, everything newer takes JPEG with an 8-byte header.
public struct DeckModel: Sendable, Equatable {
  public static let vendorID = 0x0FD9

  enum Wire: Sendable { case bmp, jpeg }

  /// How the key's screen is mounted relative to the picture we draw.
  enum Mounting: Sendable { case upright, upsideDown, quarterTurn }

  public let name: String
  public let productIDs: Set<Int>
  public let columns: Int
  public let rows: Int
  /// Width and height of one key's image, in pixels.
  public let side: Int
  let wire: Wire
  let mounting: Mounting

  public var keyCount: Int { columns * rows }

  public static let all: [DeckModel] = [
    DeckModel(name: "Stream Deck Mini", productIDs: [0x63, 0x90, 0xB3, 0xB8], columns: 3, rows: 2, side: 80, wire: .bmp, mounting: .quarterTurn),
    DeckModel(name: "Stream Deck", productIDs: [0x6D, 0x80, 0xA5, 0xB9, 0xE4], columns: 5, rows: 3, side: 72, wire: .jpeg, mounting: .upsideDown),
    DeckModel(name: "Stream Deck XL", productIDs: [0x6C, 0x8F, 0xBA], columns: 8, rows: 4, side: 96, wire: .jpeg, mounting: .upsideDown),
    DeckModel(name: "Stream Deck Neo", productIDs: [0x9A], columns: 4, rows: 2, side: 96, wire: .jpeg, mounting: .upsideDown),
    DeckModel(name: "Stream Deck +", productIDs: [0x84], columns: 4, rows: 2, side: 120, wire: .jpeg, mounting: .upright),
    DeckModel(name: "Stream Deck + XL", productIDs: [0xC6], columns: 9, rows: 4, side: 112, wire: .jpeg, mounting: .quarterTurn),
  ]

  public static func matching(productID: Int) -> DeckModel? {
    all.first { $0.productIDs.contains(productID) }
  }

  // MARK: - Reports

  static let reportLength = 1024
  var headerLength: Int { wire == .bmp ? 16 : 8 }
  var featureLength: Int { wire == .bmp ? 17 : 32 }

  /// The output reports that put an encoded image on one key (0 is top-left, row by row).
  public func imageReports(_ image: [UInt8], key: Int) -> [[UInt8]] {
    let chunk = Self.reportLength - headerLength
    let pages = max(1, (image.count + chunk - 1) / chunk)
    return (0..<pages).map { page in
      let body = image[min(image.count, page * chunk)..<min(image.count, (page + 1) * chunk)]
      let isLast: UInt8 = page == pages - 1 ? 1 : 0
      var report: [UInt8] = switch wire {
      case .bmp: [0x02, 0x01, UInt8(page), 0, isLast, UInt8(key + 1)]
      case .jpeg: [0x02, 0x07, UInt8(key), isLast,
                   UInt8(body.count & 0xFF), UInt8(body.count >> 8),
                   UInt8(page & 0xFF), UInt8(page >> 8)]
      }
      report += Array(repeating: 0, count: headerLength - report.count)
      report += body
      report += Array(repeating: 0, count: Self.reportLength - report.count)
      return report
    }
  }

  public func brightnessReport(percent: Int) -> [UInt8] {
    let level = UInt8(clamping: min(100, max(0, percent)))
    return padded(wire == .bmp ? [0x05, 0x55, 0xAA, 0xD1, 0x01, level] : [0x03, 0x08, level])
  }

  /// Clears every key back to the device's blank state.
  public var resetReport: [UInt8] { padded(wire == .bmp ? [0x0B, 0x63] : [0x03, 0x02]) }

  /// Which keys are held down, from an input report (report ID included), or nil if it
  /// reports something else, like a dial or the touch strip.
  public func pressedKeys(in report: [UInt8]) -> [Bool]? {
    let start = wire == .bmp ? 1 : 4
    guard report.first == 0x01, report.count >= start + keyCount,
          wire == .bmp || report[1] == 0x00 else { return nil }
    return report[start..<start + keyCount].map { $0 != 0 }
  }

  private func padded(_ bytes: [UInt8]) -> [UInt8] {
    bytes + Array(repeating: 0, count: featureLength - bytes.count)
  }

  // MARK: - Images

  /// Turns an upright RGBA picture (rows from the top, `side` square) into what the key expects.
  public func encode(_ rgba: [UInt8]) -> [UInt8] {
    let mounted = mount(rgba)
    return wire == .bmp ? bmp(mounted) : Pixels.encode(mounted, side: side, as: .jpeg)
  }

  /// Rotates the picture so it reads right once the key's screen shows it.
  func mount(_ rgba: [UInt8]) -> [UInt8] {
    guard mounting != .upright else { return rgba }
    let last = side - 1
    var out = [UInt8](repeating: 0, count: rgba.count)
    for y in 0..<side {
      for x in 0..<side {
        let (sx, sy) = switch mounting {
        case .upright: (x, y)
        case .upsideDown: (last - x, last - y)
        case .quarterTurn: (last - y, x)      // a quarter turn counter-clockwise
        }
        let to = (y * side + x) * 4, from = (sy * side + sx) * 4
        out[to..<to + 4] = rgba[from..<from + 4]
      }
    }
    return out
  }

  /// 24-bit BGR with the 54-byte header, rows written top first as the Mini wants them.
  private func bmp(_ rgba: [UInt8]) -> [UInt8] {
    let pixelBytes = side * side * 3
    func le32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
    let fileHeader: [[UInt8]] = [[0x42, 0x4D], le32(54 + pixelBytes), le32(0), le32(54)]
    let infoHeader: [[UInt8]] = [le32(40), le32(side), le32(side), [1, 0, 24, 0], le32(0), le32(pixelBytes),
                                 le32(2835), le32(2835), le32(0), le32(0)]
    var out = (fileHeader + infoHeader).flatMap { $0 }
    out.reserveCapacity(54 + pixelBytes)
    for pixel in stride(from: 0, to: rgba.count, by: 4) {
      out += [rgba[pixel + 2], rgba[pixel + 1], rgba[pixel]]
    }
    return out
  }
}
