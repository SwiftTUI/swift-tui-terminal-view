/// Frames control strings before the backend sees them, imposing a hard allocation bound.
/// Bytes outside DCS/APC/OSC are delivered unchanged, including incremental UTF-8.
struct TerminalControlFramer {
  enum Chunk {
    case terminal([UInt8])
    case dcs([UInt8])
    case apc([UInt8])
    case osc([UInt8])
    case erase([UInt8])
    case reset
  }
  private enum Mode { case ground, escape, csi, dcs, apc, osc }
  private var mode = Mode.ground
  private var buffer: [UInt8] = []
  private var escaped = false
  private var discard = false
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
    for byte in bytes {
      switch mode {
      case .ground:
        if byte == 27 {
          flush()
          mode = .escape
          buffer = [27]
        } else {
          plain.append(byte)
        }
      case .escape:
        buffer.append(byte)
        switch byte {
        case 91: mode = .csi
        case 80: mode = .dcs
        case 95: mode = .apc
        case 93: mode = .osc
        case 99:
          chunks.append(.reset)
          clear()
        case 27:
          chunks.append(.terminal([27]))
          buffer = [27]
        default:
          chunks.append(.terminal(buffer))
          clear()
        }
        started = .now
      case .csi:
        buffer.append(byte)
        if (0x40...0x7E).contains(byte) {
          chunks.append(byte == 74 || byte == 75 ? .erase(buffer) : .terminal(buffer))
          clear()
        } else if buffer.count > 128 || byte == 24 || byte == 26 {
          clear()
        }
      case .dcs, .apc, .osc:
        if byte == 24 || byte == 26 {
          clear()
          continue
        }
        let complete = escaped && byte == 92 || mode == .osc && byte == 7
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
        }
      }
    }
    flush()
    return chunks
  }

  private mutating func clear() {
    mode = .ground
    buffer.removeAll(keepingCapacity: false)
    escaped = false
    discard = false
  }
}
