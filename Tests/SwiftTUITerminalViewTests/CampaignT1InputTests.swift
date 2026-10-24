import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

@Suite("Campaign T1 input contracts", .serialized, .timeLimit(.minutes(1)))
struct CampaignT1InputTests {
  @Test(arguments: Array(31...50))
  func keys(id: Int) async {
    let emulator = TerminalEmulator(size: .init(width: 12, height: 4))
    func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }
    let controlC = TerminalEmulatorKey(code: .character("c"), modifiers: .control)
    switch id {
    case 31:
      let pairs: [(Character, UInt8)] = [
        ("@", 0), ("2", 0), ("[", 27), ("3", 27),
        ("\\", 28), ("]", 29), ("^", 30), ("_", 31), ("?", 127),
      ]
      for (character, expected) in pairs {
        #expect(
          await emulator.encode(key: .init(code: .character(character), modifiers: .control)) == [
            expected
          ])
      }
    case 32:
      for (lower, upper) in zip("azm", "AZM") {
        let first = await emulator.encode(key: .init(code: .character(lower), modifiers: .control))
        let second = await emulator.encode(key: .init(code: .character(upper), modifiers: .control))
        #expect(first == upper.asControlBytes)
        #expect(second == first)
      }
    case 33:
      #expect(
        await emulator.encode(key: .init(code: .character("e\u{301}"), modifiers: .option)) == [27]
          + bytes("e\u{301}"))
    case 34:
      #expect(
        await emulator.encode(key: .init(code: .character("d"), modifiers: [.control, .option]))
          == [27, 4])
    case 35:
      #expect(await emulator.encode(key: .init(code: .backspace, modifiers: .control)) == [8])
      #expect(await emulator.encode(key: .init(code: .backspace)) == [127])
    case 36:
      #expect(
        await emulator.encode(key: .init(code: .tab, modifiers: [.option, .shift]))
          == bytes("\u{1B}\u{1B}[Z"))
    case 37:
      #expect(
        await emulator.encode(key: .init(code: .home, modifiers: [.control, .option, .shift]))
          == bytes("\u{1B}[1;8H"))
      #expect(
        await emulator.encode(key: .init(code: .end, modifiers: [.control, .option, .shift]))
          == bytes("\u{1B}[1;8F"))
    case 38:
      let keys: [TerminalEmulatorKey.Code] = [.insert, .delete, .pageUp, .pageDown]
      for (key, number) in zip(keys, [2, 3, 5, 6]) {
        #expect(
          await emulator.encode(key: .init(code: key, modifiers: [.control, .shift]))
            == bytes("\u{1B}[\(number);6~"))
      }
    case 39:
      let expected = [
        "\u{1B}OP", "\u{1B}OQ", "\u{1B}OR", "\u{1B}OS", "\u{1B}[15~", "\u{1B}[17~",
        "\u{1B}[18~", "\u{1B}[19~", "\u{1B}[20~", "\u{1B}[21~", "\u{1B}[23~", "\u{1B}[24~",
      ]
      for (index, value) in expected.enumerated() {
        #expect(await emulator.encode(key: .init(code: .function(index + 1))) == bytes(value))
      }
    case 40:
      _ = await emulator.feed(bytes("\u{1B}[?1h"))
      #expect(await emulator.encode(key: .init(code: .arrowLeft)) == bytes("\u{1B}OD"))
      _ = await emulator.feed([27, 99])
      #expect(await emulator.encode(key: .init(code: .arrowLeft)) == bytes("\u{1B}[D"))
    case 41:
      let events = await emulator.feed(bytes("\u{1B}[>6u\u{1B}[?u"))
      #expect(events.contains(.clientReply(bytes("\u{1B}[?0u"))))
      #expect(await emulator.encode(key: controlC) == [3])
    case 42:
      _ = await emulator.feed(bytes("\u{1B}[>25u"))
      #expect(
        await emulator.encode(key: .init(code: .character("e\u{301}")))
          == bytes("\u{1B}[101;;101:769u"))
    case 43:
      _ = await emulator.feed(bytes("\u{1B}[>8u"))
      #expect(await emulator.encode(key: .init(code: .character("é"))) == bytes("\u{1B}[233u"))
    case 44:
      _ = await emulator.feed(bytes("\u{1B}[>1u"))
      #expect(
        await emulator.encode(key: .init(code: .character("é"), modifiers: .option))
          == bytes("\u{1B}[233;3u"))
    case 45:
      _ = await emulator.feed(bytes("\u{1B}[>1u"))
      #expect(await emulator.encode(key: .init(code: .character("界"))) == bytes("界"))
    case 46:
      _ = await emulator.feed(bytes("\u{1B}[>1u\u{1B}[>8u"))
      #expect(await emulator.encode(key: .init(code: .character("x"))) == bytes("\u{1B}[120u"))
      _ = await emulator.feed(bytes("\u{1B}[<u"))
      #expect(await emulator.encode(key: .init(code: .character("x"))) == bytes("x"))
      #expect(await emulator.encode(key: controlC) == bytes("\u{1B}[99;5u"))
      _ = await emulator.feed(bytes("\u{1B}[<u"))
      #expect(await emulator.encode(key: controlC) == [3])
    case 47:
      _ = await emulator.feed(bytes("\u{1B}[>1u\u{1B}[?1049h\u{1B}[>8u"))
      #expect(await emulator.encode(key: .init(code: .character("x"))) == bytes("\u{1B}[120u"))
      _ = await emulator.feed(bytes("\u{1B}[?1049l"))
      #expect(await emulator.encode(key: .init(code: .character("x"))) == bytes("x"))
      #expect(await emulator.encode(key: controlC) == bytes("\u{1B}[99;5u"))
    case 48:
      _ = await emulator.feed(bytes("\u{1B}[>1u\u{1B}[>8u\u{1B}c\u{1B}[<u"))
      #expect(await emulator.encode(key: controlC) == [3])
    case 49:
      _ = await emulator.feed(bytes("\u{1B}[>1u"))
      #expect(await emulator.encode(key: .init(code: .function(13))) == bytes("\u{1B}[57376u"))
      #expect(await emulator.encode(key: .init(code: .function(35))) == bytes("\u{1B}[57398u"))
    default:
      _ = await emulator.feed(bytes("\u{1B}[>1u"))
      for number in [0, 36, 99] {
        #expect(await emulator.encode(key: .init(code: .function(number))).isEmpty)
      }
    }
  }

  @Test(arguments: Array(51...60))
  func pasteAndMouse(id: Int) async {
    let emulator = TerminalEmulator(size: .init(width: 12, height: 4))
    let paste = "界\ne\u{301}"
    let plain = Array(paste.utf8)
    let bracketed = Array("\u{1B}[200~\(paste)\u{1B}[201~".utf8)
    switch id {
    case 51: #expect(await emulator.encode(paste: paste) == plain)
    case 52:
      _ = await emulator.feed(Array("\u{1B}[?2004h".utf8))
      #expect(await emulator.encode(paste: paste) == bracketed)
    case 53:
      for byte in Array("\u{1B}[?2004h".utf8) { _ = await emulator.feed([byte]) }
      #expect(await emulator.encode(paste: paste) == bracketed)
    case 54:
      _ = await emulator.feed(Array("\u{1B}[?2004h\u{1B}c".utf8))
      #expect(await emulator.encode(paste: paste) == plain)
    case 55:
      let second = TerminalEmulator(size: .init(width: 12, height: 4))
      _ = await emulator.feed(Array("\u{1B}[?2004h".utf8))
      #expect(await emulator.encode(paste: paste) == bracketed)
      #expect(await second.encode(paste: paste) == plain)
    case 56:
      _ = await emulator.feed(Array("\u{1B}[?1000h\u{1B}[?1006h".utf8))
      #expect(await emulator.send(mouse: .init(kind: .cancelled, cell: .zero)).isEmpty)
      #expect(await emulator.encode(key: .init(code: .character("x"))) == [120])
    case 57:
      let event = MouseEvent(
        kind: .dragged(.secondary), location: .init(x: 2.8, y: 3.2), modifiers: [.ctrl, .alt])
      let mouse = TerminalEmulatorMouse(event: event)
      #expect(mouse.kind == .dragged(.secondary) && mouse.cell == .init(x: 2, y: 3))
      #expect(mouse.modifiers == [.ctrl, .alt])
    case 58:
      let whole = TerminalEmulator(size: .init(width: 12, height: 4))
      let expected = await whole.feed(Array("\u{1B}[?1006h".utf8))
      #expect(expected.contains(.mouseModeChanged(.sgr)))
      var events: [TerminalEmulatorEvent] = []
      for byte in Array("\u{1B}[?1006h".utf8) { events += await emulator.feed([byte]) }
      t1Known("STUI-1179: mouse-mode publication depends on chunk boundaries") {
        #expect(
          events.filter { if case .mouseModeChanged = $0 { true } else { false } }
            == expected.filter { if case .mouseModeChanged = $0 { true } else { false } })
      }
    case 59:
      _ = await emulator.feed(Array("\u{1B}[?1006h".utf8))
      let events = await emulator.feed(Array("\u{1B}[?1006l\u{1B}[?1006h".utf8))
      t1Known("STUI-1179: final mouse-mode notification contradicts the enabled protocol") {
        #expect(
          events.last { if case .mouseModeChanged = $0 { true } else { false } }
            == .mouseModeChanged(.sgr))
      }
      #expect(
        await emulator.send(mouse: .init(kind: .down(.primary), cell: .zero))
          == Array("\u{1B}[<0;1;1M".utf8))
    default:
      let events = await emulator.feed(Array("\u{1B}[?1006h\u{1B}[?1006l\u{1B}[?1006h".utf8))
      t1Known("STUI-1179: final mouse-mode notification contradicts the enabled protocol") {
        #expect(
          events.last { if case .mouseModeChanged = $0 { true } else { false } }
            == .mouseModeChanged(.sgr))
      }
      #expect(
        await emulator.send(mouse: .init(kind: .down(.primary), cell: .zero))
          == Array("\u{1B}[<0;1;1M".utf8))
    }
  }
}

extension Character {
  fileprivate var asControlBytes: [UInt8] {
    switch self {
    case "A": [1]
    case "Z": [26]
    case "M": [13]
    default: []
    }
  }
}
