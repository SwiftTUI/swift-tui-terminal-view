/// SwiftTerm's decoder is private and has no resource limits. Validate its complete
/// work and allocation dimensions before feeding it a bounded, normalized DCS.
enum TerminalSixelPreflight {
  static func isSixel(_ payload: [UInt8]) -> Bool {
    guard let final = payload.first(where: { (0x40...0x7E).contains($0) }) else { return false }
    return final == 113
      && payload.prefix(while: { $0 != 113 }).allSatisfy { (48...57).contains($0) || $0 == 59 }
  }

  static func normalized(_ payload: [UInt8]) -> [UInt8]? {
    guard payload.count <= 1024 * 1024, let q = payload.firstIndex(of: 113),
      payload[..<q].allSatisfy({ (48...57).contains($0) || $0 == 59 })
    else { return nil }
    let bytes = Array(payload[(q + 1)...])
    var index = 0
    var x = 0
    var y = 0
    var work = 0
    func integer(_ index: inout Int) -> Int? {
      let start = index
      var value = 0
      while index < bytes.count, (48...57).contains(bytes[index]) {
        guard index - start < 6 else { return nil }
        value = value * 10 + Int(bytes[index] - 48)
        index += 1
      }
      return index > start ? value : nil
    }
    while index < bytes.count {
      let byte = bytes[index]
      index += 1
      switch byte {
      case 33:
        guard let count = integer(&index), (1...1024).contains(count),
          index < bytes.count, (63...126).contains(bytes[index])
        else { return nil }
        index += 1
        x += count
        work += count
      case 35, 34:
        var values: [Int] = []
        guard let first = integer(&index) else { return nil }
        values.append(first)
        while index < bytes.count, bytes[index] == 59 {
          index += 1
          guard values.count < 5, let value = integer(&index) else { return nil }
          values.append(value)
        }
        if byte == 35 {
          guard first <= 255, values.count == 1 || values.count == 5 else { return nil }
          if values.count == 5 {
            guard values[1] == 1 || values[1] == 2,
              values[2] <= (values[1] == 1 ? 360 : 100), values[3] <= 100, values[4] <= 100
            else { return nil }
          }
        } else {
          guard values.count == 4, values[0] <= 1024, values[1] <= 1024,
            values[2] <= 1024, values[3] <= 1024
          else { return nil }
        }
      case 36: x = 0
      case 45:
        y += 6
        x = 0
      case 63...126:
        x += 1
        work += 1
      case 10, 13: break
      default: return nil
      }
      guard x <= 1024, y + 6 <= 1024, work <= 2_097_152 else { return nil }
    }
    // The backend begins decoding at the first palette selection. A default
    // selection makes palette-free streams work; the final '$' closes its scan.
    return Array("\u{1B}Pq#15".utf8) + bytes + Array("$\u{1B}\\".utf8)
  }
}
