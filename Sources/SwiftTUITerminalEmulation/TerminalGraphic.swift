public import SwiftTUIRuntime

/// A pane-owned, decoded image encoded as PNG for the ordinary SwiftTUI image renderer.
public struct TerminalGraphic: Sendable, Equatable, Identifiable {
  public let id: UInt64
  public let png: [UInt8]
  public let pixelSize: PixelSize
  public let bounds: CellRect

  public init(id: UInt64, png: [UInt8], pixelSize: PixelSize, bounds: CellRect) {
    self.id = id
    self.png = png
    self.pixelSize = pixelSize
    self.bounds = bounds
  }
}

/// Encodes bounded RGBA with stored DEFLATE blocks; no platform image API is required.
enum TerminalPNG {
  static func encode(rgba: [UInt8], width: Int, height: Int) -> [UInt8] {
    var scanlines: [UInt8] = []
    scanlines.reserveCapacity(rgba.count + height)
    for row in 0..<height {
      scanlines.append(0)
      scanlines.append(contentsOf: rgba[(row * width * 4)..<((row + 1) * width * 4)])
    }
    var compressed: [UInt8] = [0x78, 0x01]
    var offset = 0
    while offset < scanlines.count {
      let count = min(65_535, scanlines.count - offset)
      let final = offset + count == scanlines.count
      compressed += [
        final ? 1 : 0, UInt8(count & 255), UInt8(count >> 8), UInt8((count ^ 65_535) & 255),
        UInt8((count ^ 65_535) >> 8),
      ]
      compressed.append(contentsOf: scanlines[offset..<(offset + count)])
      offset += count
    }
    var a: UInt32 = 1
    var b: UInt32 = 0
    for byte in scanlines {
      a = (a + UInt32(byte)) % 65_521
      b = (b + a) % 65_521
    }
    compressed += bigEndian((b << 16) | a)
    var result: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    result += chunk("IHDR", bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [8, 6, 0, 0, 0])
    result += chunk("IDAT", compressed)
    result += chunk("IEND", [])
    return result
  }

  private static let crcTable: [UInt32] = (0..<256).map { value in
    var crc = UInt32(value)
    for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : 0xEDB8_8320 ^ (crc >> 1) }
    return crc
  }

  private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
    let bytes = Array(type.utf8) + data
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes { crc = crcTable[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8) }
    return bigEndian(UInt32(data.count)) + bytes + bigEndian(crc ^ 0xFFFF_FFFF)
  }

  private static func bigEndian(_ value: UInt32) -> [UInt8] {
    [
      UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255),
      UInt8(value & 255),
    ]
  }
}
