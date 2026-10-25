/// Frames control strings before the backend sees them, imposing a hard allocation bound.
/// Bytes outside control sequences and strings are delivered unchanged, including
/// incremental UTF-8.
///
/// Every sequence the framer delivers is one the backend's parser dispatches, and the
/// backend is in its ground state between chunks, so that the backend cannot see a
/// sequence that the framer did not frame. Inside a sequence the framer therefore follows
/// the backend: a C0 control is delivered at once (the backend executes it in place), DEL
/// is ignored, ESC abandons the unfinished sequence and starts a new one, and CAN/SUB
/// abandon it. An 8-bit C1 control does the same in its 7-bit form: an introducer opens
/// its sequence, ST ends one, and any other is executed. In a control string, an ESC that
/// does not begin ST, or a C1 control (OSC text excepted, which may be UTF-8), discards
/// the unfinished string in the same way. SOS and PM strings are discarded.
struct TerminalControlFramer {
  enum Chunk {
    case terminal([UInt8])
    case dcs([UInt8])
    case apc([UInt8])
    case osc([UInt8])
    case erase([UInt8])
    case reset
  }
  private enum Mode { case ground, escape, csi, dcs, apc, osc, sos }
  private var mode = Mode.ground
  private var buffer: [UInt8] = []
  private var escaped = false
  private var discard = false
  private var oscHasText = false
  private var started = ContinuousClock.now
  static let maximumBytes = 6 * 1024 * 1024

  mutating func feed(_ bytes: [UInt8]) -> [Chunk] {
    var chunks: [Chunk] = []
    var plain: [UInt8] = []
    func flush() {
      if !plain.isEmpty {
        chunks.append(.terminal(plain))
        plain.removeAll(keepingCapacity: true)
      }
    }
    var index = bytes.startIndex
    while index < bytes.endIndex {
      let byte = bytes[index]
      index += 1
      switch mode {
      case .ground:
        if byte == 27 {
          flush()
          begin(.escape)
        } else {
          plain.append(byte)
        }
      case .escape:
        if Self.isExecutedInSequence(byte) {
          chunks.append(.terminal([byte]))
          continue
        }
        switch byte {
        case 127:
          continue
        case 24, 26:
          clear()
        case 27:
          begin(.escape)
        case 0x20...0x2F:
          buffer.append(byte)
        case 0x80...0x9F:
          readC1(byte, into: &chunks)
        case 91 where buffer.count == 1: begin(.csi)
        case 80 where buffer.count == 1: begin(.dcs)
        case 95 where buffer.count == 1: begin(.apc)
        case 93 where buffer.count == 1: begin(.osc)
        case 88 where buffer.count == 1, 94 where buffer.count == 1: begin(.sos)
        case 99 where buffer.count == 1:
          chunks.append(.reset)
          clear()
        default:
          buffer.append(byte)
          chunks.append(.terminal(buffer))
          clear()
        }
      case .csi:
        if Self.isExecutedInSequence(byte) {
          chunks.append(.terminal([byte]))
        } else if byte == 27 {
          begin(.escape)
        } else if byte == 127 {
          continue
        } else if (0x80...0x9F).contains(byte) {
          readC1(byte, into: &chunks)
        } else if (0x40...0x7E).contains(byte) {
          buffer.append(byte)
          chunks.append(byte == 74 || byte == 75 ? .erase(buffer) : .terminal(buffer))
          clear()
        } else if buffer.count >= 128 || byte == 24 || byte == 26 {
          clear()
        } else {
          buffer.append(byte)
        }
      case .dcs, .apc, .osc, .sos:
        if byte == 24 || byte == 26 {
          clear()
          continue
        }
        let complete =
          escaped && byte == 92 || mode == .osc && byte == 7 || mode != .osc && byte == 0x9C
        if !complete && (escaped || Self.isC1(byte) && (mode != .osc || !oscHasText)) {
          // The backend leaves the string here: an ESC that does not begin ST, or a C1
          // control outside OSC text. Discard the string and read the ESC or the C1 control
          // as the start of what follows.
          if escaped {
            begin(.escape)
          } else {
            clear()
            readC1(byte, into: &chunks)
            continue
          }
          index -= 1
          continue
        }
        if complete {
          if !discard {
            if escaped { buffer.removeLast() }
            let payload = Array(buffer.dropFirst(2))
            switch mode {
            case .dcs: chunks.append(.dcs(payload))
            case .apc: chunks.append(.apc(payload))
            case .osc: chunks.append(.osc(payload))
            default: break
            }
          }
          clear()
        } else {
          if buffer.count >= Self.maximumBytes || started.duration(to: .now) > .seconds(5) {
            discard = true
            buffer.removeAll(keepingCapacity: false)
          }
          if !discard { buffer.append(byte) }
          escaped = byte == 27
          if byte >= 0x20 && !Self.isC1(byte) { oscHasText = true }
        }
      }
    }
    flush()
    return chunks
  }

  /// Reads an 8-bit C1 control as the backend's parser does inside a sequence: as ESC
  /// followed by its 7-bit form. Introducers open their sequence, ST ends the current
  /// one, and the backend executes any other C1 control from its escape state.
  private mutating func readC1(_ byte: UInt8, into chunks: inout [Chunk]) {
    switch byte {
    case 0x9B: begin(.csi)
    case 0x90: begin(.dcs)
    case 0x9F: begin(.apc)
    case 0x9D: begin(.osc)
    case 0x98, 0x9E: begin(.sos)
    case 0x9C: clear()
    default:
      chunks.append(.terminal([27, byte]))
      clear()
    }
  }

  /// The C0 controls the backend executes inside an escape or CSI sequence without
  /// leaving it. CAN, SUB and ESC end the sequence instead.
  private static func isExecutedInSequence(_ byte: UInt8) -> Bool {
    byte <= 0x17 || (0x1C...0x1F).contains(byte)
  }

  private static func isC1(_ byte: UInt8) -> Bool {
    (0x80...0x9F).contains(byte)
  }

  /// Starts a sequence; its buffer holds the 7-bit introducer.
  private mutating func begin(_ next: Mode) {
    clear()
    mode = next
    switch next {
    case .escape, .ground: buffer = [27]
    case .csi: buffer = [27, 91]
    case .dcs: buffer = [27, 80]
    case .apc: buffer = [27, 95]
    case .osc: buffer = [27, 93]
    case .sos: buffer = [27, 88]
    }
    started = .now
  }

  private mutating func clear() {
    mode = .ground
    buffer.removeAll(keepingCapacity: false)
    escaped = false
    discard = false
    oscHasText = false
  }
}
