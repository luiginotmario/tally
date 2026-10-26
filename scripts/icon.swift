// Draws Tally's app icon: a dark deck of four keys, one of them lit.
// Usage: swift scripts/icon.swift out.png
import AppKit

let size = 1024.0
let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor { CGColor(gray: white, alpha: alpha) }
let warm = CGColor(srgbRed: 0.95, green: 0.93, blue: 0.89, alpha: 1)

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
  CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ path: CGPath, top: CGColor, bottom: CGColor, in rect: CGRect) {
  context.saveGState()
  context.addPath(path)
  context.clip()
  let gradient = CGGradient(colorsSpace: nil, colors: [top, bottom] as CFArray, locations: [0, 1])!
  context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
  context.restoreGState()
}

// The body: macOS's standard 824-point tile, with a soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = rounded(body, 185)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: gray(0, 0.35))
context.addPath(bodyPath)
context.setFillColor(gray(0.1))
context.fillPath()
context.restoreGState()
fill(bodyPath, top: gray(0.15), bottom: gray(0.06), in: body)

// Four keys; the top-right one is the lamp.
let key = 236.0, gap = 56.0
let origin = (size - (2 * key + gap)) / 2
for row in 0..<2 {
  for column in 0..<2 {
    let rect = CGRect(x: origin + Double(column) * (key + gap), y: origin + Double(row) * (key + gap), width: key, height: key)
    let path = rounded(rect, 52)
    if row == 1 && column == 1 {
      context.saveGState()
      context.setShadow(offset: .zero, blur: 90, color: CGColor(srgbRed: 1, green: 0.9, blue: 0.75, alpha: 0.55))
      context.addPath(path)
      context.setFillColor(warm)
      context.fillPath()
      context.restoreGState()
      fill(path, top: CGColor(srgbRed: 0.99, green: 0.97, blue: 0.93, alpha: 1), bottom: CGColor(srgbRed: 0.91, green: 0.88, blue: 0.83, alpha: 1), in: rect)
    } else {
      fill(path, top: gray(0.2), bottom: gray(0.13), in: rect)
      context.saveGState()
      context.addPath(rounded(rect.insetBy(dx: 1, dy: 1), 51))
      context.setStrokeColor(gray(1, 0.06))
      context.setLineWidth(2)
      context.strokePath()
      context.restoreGState()
    }
  }
}

let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
