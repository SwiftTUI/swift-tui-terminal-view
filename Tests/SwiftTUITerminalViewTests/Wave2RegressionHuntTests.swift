import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

// Wave-2 regression hunt, part CA (STUI-1165): neighbours of the 0.19.3
// cell-conversion, pixel-report, mouse-mode and SGR-Pixels repairs (STUI-1148,
// 1149, 1151, 1153, 1179, 1215). Cases w2ca001-w2ca008; the hypotheses precede
// these tests in the hunt's evidence directory.
@Suite("Wave-2 hunt CA: TerminalView repair neighbours", .serialized)
struct Wave2RegressionHuntTests {
  // MARK: Selection highlight over preserved reverse video (STUI-1149)

  @Test("w2ca001 selection over default-colour reverse video keeps the blue highlight")
  func w2ca001SelectionOverDefaultReverseIsBlueHighlight() async {
    let plain = await highlightedStyle(after: "")
    #expect(presentedBackground(plain) == .blue)
    #expect(presentedForeground(plain) == .white)
    for prefix in ["\u{1B}[7m", "\u{1B}[31;7m", "\u{1B}[42;7m"] {
      let style = await highlightedStyle(after: prefix)
      w2HuntKnown(
        """
        NEW-1: a selected default-colour reverse-video cell is presented blue on white, \
        not with the blue highlight; highlightedGrid replaces both colours but keeps the \
        .reverse emphasis STUI-1149 now preserves; contract: TerminalEmbedding.md:159; \
        adjacent STUI-1149
        """
      ) {
        #expect(presentedBackground(style) == .blue, "\(prefix.debugDescription)")
        #expect(presentedForeground(style) == .white, "\(prefix.debugDescription)")
      }
    }
  }

  @Test("w2ca002 selection over swapped-colour reverse and faint or blink cells is white on blue")
  func w2ca002SelectionOverSwappedAndFaintCellsIsBlueHighlight() async {
    let swapped = await highlightedStyle(after: "\u{1B}[31;42;7m")
    #expect(presentedBackground(swapped) == .blue)
    #expect(presentedForeground(swapped) == .white)
    let faint = await highlightedStyle(after: "\u{1B}[2;5m")
    #expect(presentedBackground(faint) == .blue)
    #expect(presentedForeground(faint) == .white)
    #expect(faint?.emphasis.contains(.faint) == true)
    #expect(faint?.emphasis.contains(.blink) == true)
  }

  // MARK: DECSET grammar versus the backend's parser (STUI-1179)

  @Test("w2ca003 a DECSET the backend drops for its parameter count publishes no encoding change")
  func w2ca003OverlongDecsetPublishesNoEncodingChange() async {
    let press = TerminalEmulatorMouse(kind: .down(.primary), cell: CellPoint(x: 4, y: 2))

    // Control: 24 parameters are dispatched; 1006 switches to SGR.
    let accepted = await drainedHuntEmulator()
    _ = await accepted.feed(Array("\u{1B}[?1000h".utf8))
    let acceptedModes = huntMouseModes(
      await accepted.feed(Array(("\u{1B}[?" + String(repeating: "25;", count: 23) + "1006h").utf8)))
    #expect(acceptedModes == [.sgr])
    #expect(await accepted.send(mouse: press) == Array("\u{1B}[<0;5;3M".utf8))

    // 25 parameters: SwiftTerm drops the whole sequence, so the encoding stays X10.
    let dropped = await drainedHuntEmulator()
    _ = await dropped.feed(Array("\u{1B}[?1000h".utf8))
    let droppedModes = huntMouseModes(
      await dropped.feed(Array(("\u{1B}[?" + String(repeating: "25;", count: 24) + "1006h").utf8)))
    let packet = await dropped.send(mouse: press)
    #expect(packet == Array("\u{1B}[M %#".utf8))
    w2HuntKnown(
      """
      NEW-2: a DECSET with more than 24 parameters publishes .mouseModeChanged(.sgr) \
      although SwiftTerm drops the sequence and keeps X10 encoding; mouseEncodingEvents \
      parses its own DECSET grammar instead of the sequence the backend dispatched; \
      contract: 36b424d (STUI-1179), docs/ARCHITECTURE.md:9; adjacent STUI-1179, STUI-1214
      """
    ) {
      #expect(droppedModes.isEmpty, "published \(droppedModes) while the press encodes X10")
    }
  }

  @Test("w2ca004 a DECSET 1006 with a colon separator or DEL publishes the encoding it selects")
  func w2ca004DecsetWithColonOrDelPublishesTheBackendEncoding() async {
    let press = TerminalEmulatorMouse(kind: .down(.primary), cell: CellPoint(x: 4, y: 2))
    let sequences: [(String, [UInt8])] = [
      ("colon", Array("\u{1B}[?1006:0h".utf8)),
      ("DEL", [0x1B, 0x5B, 0x3F, 0x31, 0x30, 0x7F, 0x30, 0x36, 0x68]),
    ]
    for (name, sequence) in sequences {
      let emulator = await drainedHuntEmulator()
      _ = await emulator.feed(Array("\u{1B}[?1000h".utf8))
      let modes = huntMouseModes(await emulator.feed(sequence))
      let packet = await emulator.send(mouse: press)
      // The backend's grammar decides the encoding: SGR packets follow.
      #expect(packet == Array("\u{1B}[<0;5;3M".utf8), "\(name)")
      w2HuntKnown(
        """
        NEW-2: a DECSET 1006 with a ':' separator or DEL switches SwiftTerm to SGR encoding \
        without .mouseModeChanged; mouseEncodingEvents accepts only digits and ';' while the \
        backend parser treats ':' as a separator and ignores DEL; contract: 36b424d \
        (STUI-1179); adjacent STUI-1179, STUI-1214
        """
      ) {
        #expect(modes == [.sgr], "\(name): published \(modes) while the press encodes SGR")
      }
    }
  }

  // MARK: Pixel reports (STUI-1153) and SGR-Pixels (STUI-1215)

  @Test("w2ca005 every pixel-size report describes the virtual cell before and after a resize")
  func w2ca005AllPixelReportsDescribeTheVirtualCellAcrossResize() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
    #expect(await replies(emulator, "\u{1B}[14t") == ["\u{1B}[4;48;80t"])
    #expect(await replies(emulator, "\u{1B}[14;2t") == ["\u{1B}[4;48;80t"])
    #expect(await replies(emulator, "\u{1B}[15t") == ["\u{1B}[5;48;80t"])
    #expect(await replies(emulator, "\u{1B}[16t") == ["\u{1B}[6;16;8t"])
    await emulator.resize(CellSize(width: 12, height: 5))
    #expect(await replies(emulator, "\u{1B}[14t") == ["\u{1B}[4;80;96t"])
    #expect(await replies(emulator, "\u{1B}[14;2t") == ["\u{1B}[4;80;96t"])
    #expect(await replies(emulator, "\u{1B}[15t") == ["\u{1B}[5;80;96t"])
    #expect(await replies(emulator, "\u{1B}[16t") == ["\u{1B}[6;16;8t"])
  }

  @Test("w2ca006 combined tracking and SGR-Pixels controls publish in order and report pixels")
  func w2ca006CombinedTrackingAndPixelModesPublishAndReport() async {
    let emulator = await drainedHuntEmulator()
    #expect(
      huntMouseModes(await emulator.feed(Array("\u{1B}[?1003;1016h".utf8))) == [.anyEvent, .sgr])
    let move = await emulator.send(mouse: .init(kind: .moved, cell: CellPoint(x: 3, y: 1)))
    #expect(move == Array("\u{1B}[<35;24;16M".utf8))
    #expect(
      huntMouseModes(await emulator.feed(Array("\u{1B}[?1016;1003l".utf8))) == [
        .disabled, .disabled,
      ])
    #expect(await emulator.captureSnapshot().mouseTracking == false)
  }

  // MARK: OSC 8 destinations (STUI-1151)

  @Test("w2ca007 OSC 8 keeps the whole URI after the params and needs the params field")
  func w2ca007HyperlinkParamsAndMissingParamsField() async {
    let url = "https://e.com/x;y"
    #expect(
      await huntLinks("\u{1B}]8;id=a;\(url)\u{1B}\\AB\u{1B}]8;;\u{1B}\\C", count: 3)
        == [url, url, nil])
    #expect(await huntLinks("\u{1B}]8;https://e.com\u{1B}\\AB", count: 2) == [nil, nil])
  }

  // MARK: Chunk independence across buffer switches and resets (STUI-1179)

  @Test("w2ca008 buffer switch, reset and DECRST publish the same order at every split")
  func w2ca008BufferSwitchAndResetKeepEventOrderAtEverySplit() async {
    let input = Array("\u{1B}[?1049;1006h\u{1B}c\u{1B}[?1006l".utf8)
    let whole = orderedModeEvents(await drainedHuntEmulator().feed(input))
    #expect(whole.first == .bufferActivated(.alternate))
    #expect(whole.contains(.mouseModeChanged(.sgr)))
    #expect(whole.last == .mouseModeChanged(.disabled))
    for split in 1..<input.count {
      let emulator = await drainedHuntEmulator()
      var events = await emulator.feed(Array(input[..<split]))
      events += await emulator.feed(Array(input[split...]))
      #expect(orderedModeEvents(events) == whole, "split at byte \(split)")
    }
  }
}

// MARK: Helpers

/// Preserves an unmarked reproduction while guarding only confirmed assertions.
private func w2HuntKnown(_ comment: Comment, _ body: () -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_W2HUNT_UNMARKED"] == "1" {
    body()
  } else {
    withKnownIssue(comment) { body() }
  }
}

/// The highlighted style of cell (0,0) after `prefix + "AB"`, with (0,0)-(1,0) selected.
private func highlightedStyle(after prefix: String) async -> ResolvedTextStyle? {
  let emulator = TerminalEmulator(size: CellSize(width: 10, height: 1))
  _ = await emulator.feed(Array((prefix + "AB").utf8))
  var selection = TerminalTextSelection(
    snapshot: await emulator.captureSnapshot(), anchor: CellPoint(x: 0, y: 0))
  selection.extend(to: CellPoint(x: 1, y: 0))
  return selection.highlightedGrid.cells[0][0].style
}

/// The colour a terminal (SGR 7) and the SwiftUI host draw behind the glyph.
private func presentedBackground(_ style: ResolvedTextStyle?) -> Color? {
  style?.emphasis.contains(.reverse) == true ? style?.foregroundColor : style?.backgroundColor
}

private func presentedForeground(_ style: ResolvedTextStyle?) -> Color? {
  style?.emphasis.contains(.reverse) == true ? style?.backgroundColor : style?.foregroundColor
}

/// SwiftTerm announces its initial mouse mode during construction; drain it.
private func drainedHuntEmulator() async -> TerminalEmulator {
  let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
  _ = await emulator.feed([])
  return emulator
}

private func huntMouseModes(_ events: [TerminalEmulatorEvent]) -> [TerminalMouseMode] {
  events.compactMap { event -> TerminalMouseMode? in
    guard case .mouseModeChanged(let mode) = event else { return nil }
    return mode
  }
}

private func orderedModeEvents(_ events: [TerminalEmulatorEvent]) -> [TerminalEmulatorEvent] {
  events.filter { event in
    switch event {
    case .bufferActivated, .mouseModeChanged: true
    default: false
    }
  }
}

private func replies(_ emulator: TerminalEmulator, _ query: String) async -> [String] {
  (await emulator.feed(Array(query.utf8))).compactMap { event -> String? in
    guard case .clientReply(let bytes) = event else { return nil }
    return String(decoding: bytes, as: UTF8.self)
  }
}

private func huntLinks(_ text: String, count: Int) async -> [String?] {
  let emulator = TerminalEmulator(size: CellSize(width: 6, height: 1))
  _ = await emulator.feed(Array(text.utf8))
  return (await emulator.snapshot()).cells[0].prefix(count).map(\.hyperlink)
}
