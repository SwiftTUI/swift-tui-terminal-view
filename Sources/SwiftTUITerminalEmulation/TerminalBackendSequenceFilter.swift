/// Removes the child controls that SwiftTerm reports only by printing to the host process's
/// standard output, which ignores `silentLog` and is usually the outer terminal.
///
/// SwiftTerm prints for locator reporting (DECELR, `CSI Ps ; Pu ' z`) and for every SGR
/// parameter it does not handle, and otherwise ignores both. Removing them before the
/// backend parses a complete sequence therefore changes nothing but the output.
enum TerminalBackendSequenceFilter {
  /// The sequence to feed the backend, or `nil` to drop it.
  static func filtered(_ sequence: [UInt8]) -> [UInt8]? {
    guard sequence.count >= 3, sequence[0] == 27, sequence[1] == 91, let final = sequence.last
    else { return sequence }
    let body = sequence[2..<(sequence.count - 1)]
    switch final {
    case 0x7A where body.contains(0x27) && body.allSatisfy({ (0x20...0x3F).contains($0) }):
      // With `'` among its intermediates a `z` control is DECELR or nothing at all.
      return nil
    case 0x6D:
      return selectGraphicRendition(sequence, body: body)
    default:
      return sequence
    }
  }

  /// SGR parameters the backend applies (`Terminal.cmdCharAttributes`); 38, 48 and 58
  /// introduce colours whose sub-parameters are not attributes.
  private static func isApplied(_ parameter: Int) -> Bool {
    switch parameter {
    case 0...5, 7...9, 21...25, 27...49, 58, 59, 90...97, 100...107: true
    default: false
    }
  }

  /// Removes the top-level parameters the backend does not apply. The kept units keep
  /// their own separators and are joined by `;`, which the backend reads identically.
  private static func selectGraphicRendition(
    _ sequence: [UInt8], body: ArraySlice<UInt8>
  ) -> [UInt8]? {
    // A leading `:` aborts the sequence; intermediates and private markers are not SGR.
    guard body.first != 0x3A, body.allSatisfy({ (0x30...0x3B).contains($0) }) else {
      return sequence
    }
    var count = 0
    var allApplied = true
    var reader = ParameterReader(body: body)
    while let parameter = reader.next() {
      count += 1
      allApplied = allApplied && isApplied(parameter.value)
    }
    // The backend drops a sequence with more than 24 parameters.
    guard count <= 24, !allApplied else { return sequence }
    var removed = false
    walkUnits(body, count: count) { _, applied in removed = removed || !applied }
    guard removed else { return sequence }
    var rewritten: [UInt8] = [27, 91]
    var kept = false
    walkUnits(body, count: count) { bytes, applied in
      guard applied else { return }
      if kept { rewritten.append(0x3B) }
      rewritten += body[bytes]
      kept = true
    }
    guard kept else { return nil }
    rewritten.append(0x6D)
    return rewritten
  }

  /// Visits the units the backend reads, in order, with their bytes and whether it applies
  /// them: a 38/48/58 colour with its sub-parameters (`;` or `:` form), `4:n`, or a single
  /// parameter. Mirrors `Terminal.cmdCharAttributes` and its `parseExtendedColor`.
  private static func walkUnits(
    _ body: ArraySlice<UInt8>, count: Int, _ visit: (Range<Int>, Bool) -> Void
  ) {
    var reader = ParameterReader(body: body)
    var index = 0
    while let first = reader.next() {
      var last = first
      var applied = true
      index += 1
      switch first.value {
      case 38, 48, 58:
        // The colour kind follows; its sub-parameters are a `:` chain, or a fixed count.
        guard index < count, let kind = reader.next() else { break }
        last = kind
        index += 1
        var remaining = 0
        if first.separator == 0x3A {
          remaining = .max
        } else if kind.value == 2, index + 2 < count {
          remaining = 3
        } else if kind.value == 5, index < count {
          remaining = 1
        }
        while remaining > 0, first.separator != 0x3A || last.separator == 0x3A,
          let next = reader.next()
        {
          last = next
          index += 1
          remaining -= 1
        }
      case 4 where first.separator == 0x3A:
        if let style = reader.next() { last = style }
        index += 1
      default:
        applied = isApplied(first.value)
      }
      visit(first.bytes.lowerBound..<last.bytes.upperBound, applied)
    }
  }

  /// Reads `;`/`:`-separated decimal parameters, saturating as the backend does.
  private struct ParameterReader {
    struct Parameter {
      var value: Int
      var bytes: Range<Int>
      var separator: UInt8?
    }

    let body: ArraySlice<UInt8>
    var position: Int

    init(body: ArraySlice<UInt8>) {
      self.body = body
      self.position = body.startIndex
    }

    mutating func next() -> Parameter? {
      guard position <= body.endIndex else { return nil }
      let start = position
      var value = 0
      var index = start
      while index < body.endIndex, body[index] != 0x3A, body[index] != 0x3B {
        value = min(65_535, value * 10 + Int(body[index]) - 48)
        index += 1
      }
      position = index + 1
      return Parameter(
        value: value, bytes: start..<index, separator: index < body.endIndex ? body[index] : nil)
    }
  }
}
