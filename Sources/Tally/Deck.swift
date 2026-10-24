import IOKit.hid
import OSLog
import TallyKit

/// The Stream Deck on the desk, spoken to directly over USB HID.
///
/// Event-driven end to end: IOKit wakes the app when a deck arrives, leaves, or a key changes.
/// Only one app can drive a deck at a time, so Elgato's own app has to be quit.
final class Deck {
  private(set) var model: DeckModel?
  var onConnect: (DeckModel) -> Void = { _ in }
  var onDisconnect: () -> Void = {}
  var onKey: (_ key: Int, _ isDown: Bool) -> Void = { _, _ in }

  private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  private var device: IOHIDDevice?
  private var reportBuffer: UnsafeMutableBufferPointer<UInt8>?
  private var held: [Bool] = []
  private let log = Logger(subsystem: "tally", category: "deck")

  init() {
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: DeckModel.vendorID] as CFDictionary)
    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
      MainActor.assumeIsolated { Deck.from(context).attach(device) }
    }, context)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
      MainActor.assumeIsolated { Deck.from(context).detach(device) }
    }, context)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    if opened != kIOReturnSuccess { log.error("Couldn't open HID manager: \(opened)") }
  }

  /// Puts an encoded image (from `DeckModel.encode`) on one key.
  func show(_ image: [UInt8], onKey key: Int) {
    guard let model else { return }
    for report in model.imageReports(image, key: key) { send(report, type: kIOHIDReportTypeOutput) }
  }

  func setBrightness(_ percent: Int) {
    if let model { send(model.brightnessReport(percent: percent), type: kIOHIDReportTypeFeature) }
  }

  func reset() {
    if let model { send(model.resetReport, type: kIOHIDReportTypeFeature) }
  }

  // MARK: - Device lifetime

  private static func from(_ context: UnsafeMutableRawPointer?) -> Deck {
    Unmanaged<Deck>.fromOpaque(context!).takeUnretainedValue()
  }

  private func attach(_ device: IOHIDDevice) {
    guard self.device == nil,
          let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
          let model = DeckModel.matching(productID: productID)
    else { return }

    let size = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 1024
    let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: size)
    IOHIDDeviceRegisterInputReportCallback(device, buffer.baseAddress!, size, { context, _, _, _, _, report, length in
      let bytes = Array(UnsafeBufferPointer(start: report, count: length))
      MainActor.assumeIsolated { Deck.from(context).received(bytes) }
    }, Unmanaged.passUnretained(self).toOpaque())

    self.device = device
    self.model = model
    reportBuffer = buffer
    held = Array(repeating: false, count: model.keyCount)
    log.info("\(model.name, privacy: .public) connected")
    onConnect(model)
  }

  private func detach(_ device: IOHIDDevice) {
    guard device == self.device else { return }
    self.device = nil
    model = nil
    reportBuffer?.deallocate()
    reportBuffer = nil
    onDisconnect()
  }

  private func received(_ report: [UInt8]) {
    guard let pressed = model?.pressedKeys(in: report) else { return }
    for (key, isDown) in pressed.enumerated() where isDown != held[key] {
      held[key] = isDown
      onKey(key, isDown)
    }
  }

  private func send(_ report: [UInt8], type: IOHIDReportType) {
    guard let device, let id = report.first else { return }
    // The report ID stays as the first byte, the way the device expects it.
    let result = IOHIDDeviceSetReport(device, type, CFIndex(id), report, report.count)
    if result != kIOReturnSuccess { log.error("Report failed: \(result)") }
  }
}
