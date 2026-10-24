import Testing
@testable import TallyKit

struct DeckModelTests {
  let mk2 = DeckModel.matching(productID: 0x80)!
  let mini = DeckModel.matching(productID: 0x63)!

  @Test func `known product ids resolve`() {
    #expect(mk2.keyCount == 15 && mk2.side == 72)
    #expect(mini.keyCount == 6 && mini.side == 80)
    #expect(DeckModel.matching(productID: 0x86) == nil)   // the pedal has no screens
  }

  @Test func `jpeg decks split images into 1024-byte reports with an 8-byte header`() {
    let image = [UInt8](repeating: 0xAB, count: 1016 + 10)
    let reports = mk2.imageReports(image, key: 4)
    #expect(reports.count == 2)
    #expect(reports.allSatisfy { $0.count == 1024 })
    #expect(Array(reports[0].prefix(8)) == [0x02, 0x07, 4, 0, 0xF8, 0x03, 0, 0])
    #expect(Array(reports[1].prefix(8)) == [0x02, 0x07, 4, 1, 10, 0, 1, 0])
    #expect(reports[1][8..<18].allSatisfy { $0 == 0xAB } && reports[1][18] == 0)
  }

  @Test func `the mini counts keys from one and pages in its header`() {
    let reports = mini.imageReports([UInt8](repeating: 1, count: 54 + 80 * 80 * 3), key: 0)
    #expect(reports.count == 20)
    #expect(Array(reports[0].prefix(6)) == [0x02, 0x01, 0, 0, 0, 1])
    #expect(Array(reports[19].prefix(6)) == [0x02, 0x01, 19, 0, 1, 1])
  }

  @Test func `feature reports`() {
    #expect(mk2.brightnessReport(percent: 70) == [0x03, 0x08, 70] + Array(repeating: 0, count: 29))
    #expect(mini.brightnessReport(percent: 150).prefix(6) == [0x05, 0x55, 0xAA, 0xD1, 0x01, 100])
    #expect(mini.resetReport.count == 17)
  }

  @Test func `key presses come after the report header`() {
    var report = [UInt8](repeating: 0, count: 512)
    report[0] = 0x01
    report[4 + 2] = 1
    #expect(mk2.pressedKeys(in: report)?.firstIndex(of: true) == 2)
    report[1] = 0x03                                       // a dial turning, not a key
    #expect(mk2.pressedKeys(in: report) == nil)
    #expect(mini.pressedKeys(in: [0x01, 0, 0, 0, 0, 0, 1])?.last == true)
  }

  /// A 2×2-ish check on a real size: mark the top-left pixel and see where it lands.
  @Test func `mounting turns the picture the way each deck needs`() {
    func marked(_ model: DeckModel) -> Int {
      var rgba = [UInt8](repeating: 0, count: model.side * model.side * 4)
      rgba[0] = 255
      let index = model.mount(rgba).firstIndex(of: 255)! / 4
      return index
    }
    let last = mk2.side - 1
    #expect(marked(mk2) == last * mk2.side + last)              // upside down: bottom-right
    #expect(marked(mini) == (mini.side - 1) * mini.side)        // quarter turn counter-clockwise: bottom-left
  }

  @Test func `the mini gets a 24-bit bmp`() {
    let bmp = mini.encode([UInt8](repeating: 0, count: 80 * 80 * 4))
    #expect(bmp.count == 54 + 80 * 80 * 3)
    #expect(bmp.prefix(2) == [0x42, 0x4D] && bmp[28] == 24)
  }

  @Test func `jpeg decks get a jpeg`() {
    let jpeg = mk2.encode(KeyFace(status: .done, title: "x", agent: "claude", light: 1).pixels(side: 72))
    #expect(jpeg.prefix(2) == [0xFF, 0xD8])
  }
}
