import Foundation
import SwiftTUIRuntime

struct TerminalGraphicsStore {
  private struct Asset {
    let png: [UInt8]
    let size: PixelSize
  }
  private struct Placement {
    let identity: UInt64
    let image: UInt64
    let placement: Int
    let alternate: Bool
    let row: Int
    let column: Int
    let size: CellSize
  }
  private struct Assembly {
    let control: [String: String]
    var payload: [UInt8]
    let started: ContinuousClock.Instant
  }
  private var images: [UInt64: Asset] = [:]
  private var placements: [Placement] = []
  private var assembly: Assembly?
  private var nextIdentity: UInt64 = 1
  private var nextSixelID: UInt64 = 1 << 32
  static let maximumDimension = 1024
  static let maximumPixels = 1_048_576
  static let maximumRetainedBytes = 16 * 1024 * 1024

  mutating func clear(alternate: Bool? = nil) {
    if let alternate {
      placements.removeAll { $0.alternate == alternate }
    } else {
      placements.removeAll()
      images.removeAll()
      assembly = nil
    }
    collectUnusedSixels()
  }

  mutating func evict(before row: Int, alternate: Bool) {
    placements.removeAll { $0.alternate == alternate && $0.row + $0.size.height <= row }
    collectUnusedSixels()
  }

  func snapshot(top: Int, alternate: Bool) -> [TerminalGraphic] {
    placements.compactMap { placement in
      guard placement.alternate == alternate, let asset = images[placement.image] else {
        return nil
      }
      return TerminalGraphic(
        id: placement.identity, png: asset.png, pixelSize: asset.size,
        bounds: CellRect(
          origin: CellPoint(x: placement.column, y: placement.row - top), size: placement.size)
      )
    }
  }

  mutating func addSixel(
    rgba: [UInt8], width: Int, height: Int, row: Int, column: Int, alternate: Bool
  ) {
    guard Self.validDimensions(width, height), rgba.count == width * height * 4 else { return }
    let png = TerminalPNG.encode(rgba: rgba, width: width, height: height)
    let id = nextSixelID
    nextSixelID &+= 1
    guard canStore(png, replacing: id), placements.count < 64 else { return }
    images[id] = Asset(png: png, size: PixelSize(width: width, height: height))
    place(id, placement: 0, row: row, column: column, alternate: alternate, columns: 0, rows: 0)
  }

  /// Direct RGB/RGBA transfers, explicit placement and deletion. Other transfer media never reach file APIs.
  mutating func kitty(_ payload: [UInt8], row: Int, column: Int, alternate: Bool) -> [UInt8]? {
    guard payload.first == 71, let separator = payload.firstIndex(of: 59) else { return nil }
    let header = String(decoding: payload[1..<separator], as: UTF8.self)
    var control: [String: String] = [:]
    for item in header.split(separator: ",") {
      let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard pair.count == 2, control[String(pair[0])] == nil else { return nil }
      control[String(pair[0])] = String(pair[1])
    }
    var encoded = Array(payload[(separator + 1)...])
    var assemblyStarted = ContinuousClock.now
    if let previous = assembly {
      assembly = nil
      assemblyStarted = previous.started
      guard previous.started.duration(to: .now) <= .seconds(5),
        previous.payload.count + encoded.count <= TerminalControlFramer.maximumBytes,
        control.keys.allSatisfy({ $0 == "m" || $0 == "q" })
      else { return reply(previous.control, "EINVAL: invalid or expired chunks") }
      let more = control["m"]
      encoded = previous.payload + encoded
      control = previous.control
      control["m"] = more
    }
    if control["m"] == "1" {
      assembly = Assembly(control: control, payload: encoded, started: assemblyStarted)
      return nil
    }
    guard control["m"] == nil || control["m"] == "0" else {
      return reply(control, "EINVAL: chunk flag")
    }
    let action = control["a"] ?? "t"
    guard let id = UInt64(control["i"] ?? "0"), id <= UInt64(UInt32.max),
      let placement = Int(control["p"] ?? "0"), placement >= 0,
      let columns = Int(control["c"] ?? "0"), (0...1024).contains(columns),
      let rows = Int(control["r"] ?? "0"), (0...1024).contains(rows)
    else { return reply(control, "EINVAL: identifier or geometry") }
    let allowed = Set(["a", "i", "p", "q", "f", "s", "v", "c", "r", "t", "m", "C", "d"])
    guard control.keys.allSatisfy({ allowed.contains($0) }),
      control["t"] == nil || control["t"] == "d",
      control["C"] == nil || control["C"] == "1"
    else { return reply(control, "ENOTSUP: only direct stationary placements") }
    if action == "p" || action == "T" {
      guard control["C"] == "1" else { return reply(control, "ENOTSUP: C=1 required") }
      guard
        placements.count < 64
          || placements.contains(where: {
            $0.image == id && $0.placement == placement && $0.alternate == alternate
          })
      else {
        return reply(control, "ENOSPC: placement budget")
      }
    }
    if action == "d" {
      let mode = control["d"] ?? "a"
      switch mode {
      case "a", "A":
        placements.removeAll { $0.alternate == alternate }
        if mode == "A" {
          images.removeAll()
          placements.removeAll()
        }
      case "i", "I":
        placements.removeAll { $0.image == id && (placement == 0 || $0.placement == placement) }
        if mode == "I" {
          images[id] = nil
          placements.removeAll { $0.image == id }
        }
      default: return reply(control, "ENOTSUP: deletion selector")
      }
      collectUnusedSixels()
      return nil
    }
    if action == "p" {
      guard id != 0, images[id] != nil else { return reply(control, "ENOENT: image") }
    } else {
      guard action == "t" || action == "T" || action == "q",
        let width = Int(control["s"] ?? "0"), let height = Int(control["v"] ?? "0"),
        Self.validDimensions(width, height),
        let format = Int(control["f"] ?? "32"), format == 24 || format == 32,
        let data = Data(base64Encoded: Data(encoded)), data.count == width * height * (format / 8)
      else { return reply(control, "EINVAL: expected bounded raw RGB or RGBA") }
      if action == "q" { return reply(control, "OK") }
      guard id != 0 else { return reply(control, "EINVAL: explicit image id required") }
      var rgba = Array(data)
      if format == 24 {
        rgba = []
        rgba.reserveCapacity(width * height * 4)
        for offset in stride(from: 0, to: data.count, by: 3) {
          rgba.append(contentsOf: data[offset..<(offset + 3)])
          rgba.append(255)
        }
      }
      let png = TerminalPNG.encode(rgba: rgba, width: width, height: height)
      guard canStore(png, replacing: id) else { return reply(control, "ENOSPC: image budget") }
      images[id] = Asset(png: png, size: PixelSize(width: width, height: height))
    }
    if action == "p" || action == "T" {
      place(
        id, placement: placement, row: row, column: column, alternate: alternate, columns: columns,
        rows: rows)
    }
    return reply(control, "OK")
  }

  private mutating func place(
    _ image: UInt64, placement: Int, row: Int, column: Int, alternate: Bool, columns: Int, rows: Int
  ) {
    guard let asset = images[image] else { return }
    let existing = placements.first {
      $0.image == image && $0.placement == placement && $0.alternate == alternate
    }
    placements.removeAll {
      $0.image == image && $0.placement == placement && $0.alternate == alternate
    }
    placements.append(
      Placement(
        identity: existing?.identity ?? nextIdentity, image: image, placement: placement,
        alternate: alternate,
        row: row, column: column,
        size: CellSize(
          width: columns > 0 ? columns : max(1, (asset.size.width + 7) / 8),
          height: rows > 0 ? rows : max(1, (asset.size.height + 15) / 16))
      ))
    nextIdentity &+= 1
  }

  private func canStore(_ png: [UInt8], replacing id: UInt64) -> Bool {
    (images[id] != nil || images.count < 32)
      && images.reduce(0) { $0 + ($1.key == id ? 0 : $1.value.png.count) } + png.count
        <= Self.maximumRetainedBytes
  }

  private mutating func collectUnusedSixels() {
    let used = Set(placements.map(\.image))
    images = images.filter { $0.key < 1 << 32 || used.contains($0.key) }
  }

  private func reply(_ control: [String: String], _ message: String) -> [UInt8]? {
    if control["q"] == "2" || control["q"] == "1" && message == "OK" { return nil }
    // Never interpolate unvalidated child control text in a reply.
    let id = UInt32(control["i"] ?? "") ?? 0
    let placement = UInt32(control["p"] ?? "")
    return Array("\u{1B}_Gi=\(id)\(placement.map { ",p=\($0)" } ?? "");\(message)\u{1B}\\".utf8)
  }

  static func validDimensions(_ width: Int, _ height: Int) -> Bool {
    (1...maximumDimension).contains(width) && (1...maximumDimension).contains(height)
      && width * height <= maximumPixels
  }
}
