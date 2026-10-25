import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

// Wave-2 regression hunt, part CA (STUI-1165): neighbours of the 0.19.3
// cell-conversion, pixel-report, mouse-mode and SGR-Pixels repairs (STUI-1148,
// 1149, 1151, 1153, 1179, 1215). Cases w2ca001-w2ca008; the hypotheses precede
// these tests in the hunt's evidence directory. The w3ca1 cases are the
// neighbours of the wave-3 repairs of NEW-1 (STUI-1253) and NEW-2 (STUI-1254).
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
      #expect(presentedBackground(style) == .blue, "\(prefix.debugDescription)")
      #expect(presentedForeground(style) == .white, "\(prefix.debugDescription)")
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

  @Test("w3ca1 the selection highlight is white on blue over every cell attribute")
  func w3ca1SelectionHighlightIsTheSameForEveryAttribute() async {
    let prefixes = [
      "", "\u{1B}[1m", "\u{1B}[2m", "\u{1B}[3m", "\u{1B}[4m", "\u{1B}[5m", "\u{1B}[7m",
      "\u{1B}[9m", "\u{1B}[1;7m", "\u{1B}[4;7m", "\u{1B}[31;7m", "\u{1B}[42;7m",
      "\u{1B}[31;42;7m", "\u{1B}[2;5;7m",
    ]
    for prefix in prefixes {
      let style = await highlightedStyle(after: prefix)
      #expect(presentedBackground(style) == .blue, "\(prefix.debugDescription)")
      #expect(presentedForeground(style) == .white, "\(prefix.debugDescription)")
      #expect(style?.emphasis.contains(.reverse) == false, "\(prefix.debugDescription)")
    }
    #expect(await highlightedStyle(after: "\u{1B}[1;7m")?.emphasis == .bold)
    #expect(await highlightedStyle(after: "\u{1B}[4;7m")?.underlineStyle == TextLineStyle())
  }

  @Test("w3ca1 cells outside the selection keep reverse video")
  func w3ca1CellsOutsideTheSelectionKeepReverseVideo() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 1))
    _ = await emulator.feed(Array("\u{1B}[7mABC".utf8))
    var selection = TerminalTextSelection(
      snapshot: await emulator.captureSnapshot(), anchor: CellPoint(x: 0, y: 0))
    selection.extend(to: CellPoint(x: 1, y: 0))
    let outside = selection.highlightedGrid.cells[0][2]
    #expect(outside.character == "C")
    #expect(outside.style == ResolvedTextStyle(emphasis: .reverse))
    #expect(selection.text == "AB")
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
    #expect(droppedModes.isEmpty, "published \(droppedModes) while the press encodes X10")
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
      #expect(modes == [.sgr], "\(name): published \(modes) while the press encodes SGR")
    }
  }

  @Test("w3ca1 encoding events follow every form in which the backend applies a control")
  func w3ca1EncodingEventsFollowEveryFormTheBackendApplies() async {
    let cases: [(name: String, input: [UInt8], expected: [TerminalEmulatorEvent])] = [
      ("C0 inside", Array("\u{1B}[?10\u{07}06h".utf8), [.bell, .mouseModeChanged(.sgr)]),
      ("ESC restarts", Array("\u{1B}[?10\u{1B}[?1006h".utf8), [.mouseModeChanged(.sgr)]),
      ("inside DCS", Array("\u{1B}P\u{1B}[?1006h\u{1B}\\".utf8), [.mouseModeChanged(.sgr)]),
      (
        "inside OSC", Array("\u{1B}]0;t\u{1B}\u{1B}[?1006h\u{07}".utf8),
        [.mouseModeChanged(.sgr), .bell]
      ),
      (
        "C1 introducer", [27, 0x9B] + Array("?1006h\u{07}".utf8), [.mouseModeChanged(.sgr), .bell]
      ),
    ]
    for (name, input, expected) in cases {
      let whole = await trackingHuntEmulator()
      #expect(modeAndBellEvents(await whole.feed(input)) == expected, "\(name)")
      #expect(await whole.send(mouse: huntPress) == Array("\u{1B}[<0;5;3M".utf8), "\(name)")
      for split in 1..<input.count {
        let emulator = await trackingHuntEmulator()
        var events = await emulator.feed(Array(input[..<split]))
        events += await emulator.feed(Array(input[split...]))
        #expect(modeAndBellEvents(events) == expected, "\(name), split at byte \(split)")
      }
    }
  }

  @Test("w3ca1 control strings end at ST or BEL and yield to an escape that does not end them")
  func w3ca1ControlStringsYieldToAnEscapeThatDoesNotEndThem() async {
    func titles(_ text: String) async -> [String] {
      (await drainedHuntEmulator().feed(Array(text.utf8))).compactMap { event in
        guard case .titleChanged(let title) = event else { return nil }
        return title
      }
    }
    #expect(await titles("\u{1B}]0;a\u{1B}\\") == ["a"])
    #expect(await titles("\u{1B}]0;b\u{07}") == ["b"])
    #expect(await titles("\u{1B}]0;c\u{1B}\u{07}") == ["c"])
    // UTF-8 text in a title may contain C1 bytes ("—" is E2 80 94, "Ü" is C3 9C).
    #expect(await titles("\u{1B}]0;a\u{2014}\u{DC}\u{07}") == ["a\u{2014}\u{DC}"])
    // An ESC that does not begin ST discards the string; it starts the next sequence.
    for text in ["\u{1B}]0;d\u{1B}[31mX", "\u{1B}Pq\u{1B}[31mX"] {
      let emulator = TerminalEmulator(size: CellSize(width: 4, height: 1))
      let events = await emulator.feed(Array(text.utf8))
      let cell = (await emulator.snapshot()).cells[0][0]
      #expect(!events.contains { if case .titleChanged = $0 { true } else { false } })
      #expect(
        cell.character == "X" && cell.style?.foregroundColor == .red, "\(text.debugDescription)")
    }
    // An 8-bit introducer opens its sequence; an escape with an intermediate stays whole.
    let c1 = TerminalEmulator(size: CellSize(width: 4, height: 1))
    _ = await c1.feed([27, 0x9B, 51, 49, 109] + Array("X".utf8))
    #expect((await c1.snapshot()).cells[0][0].style?.foregroundColor == .red)
    let graphics = TerminalEmulator(size: CellSize(width: 4, height: 1))
    _ = await graphics.feed(Array("\u{1B}(0q\u{1B}(Bq".utf8))
    #expect((await graphics.snapshot()).cells[0].prefix(2).map(\.character) == ["\u{2500}", "q"])
  }

  @Test("w3ca1 encoding events report changes of the encoding the backend applies")
  func w3ca1EncodingEventsReportChangesOfTheAppliedEncoding() async {
    func modes(_ controls: [String]) async -> [[TerminalMouseMode]] {
      let emulator = await trackingHuntEmulator()
      var result: [[TerminalMouseMode]] = []
      for control in controls {
        result.append(huntMouseModes(await emulator.feed(Array(control.utf8))))
      }
      return result
    }
    #expect(await modes(["\u{1B}[?1006h\u{1B}[?1006h"]) == [[.sgr]])
    #expect(await modes(["\u{1B}[?1006l", "\u{1B}[?1016l"]) == [[], []])
    #expect(
      await modes(["\u{1B}[?1006h", "\u{1B}[?1016h", "\u{1B}[?1006h"]) == [[.sgr], [.sgr], [.sgr]])
    #expect(await modes(["\u{1B}[?1006h", "\u{1B}[?1015h"]) == [[.sgr], [.disabled]])
    #expect(await modes(["\u{1B}[?1006h", "\u{1B}[?1005l"]) == [[.sgr], [.disabled]])
    #expect(await modes(["\u{1B}[?1005h", "\u{1B}[?1015h", "\u{1B}[?1015l"]) == [[], [], []])
    // One sequence publishes its net change.
    let pixels = await trackingHuntEmulator()
    #expect(huntMouseModes(await pixels.feed(Array("\u{1B}[?1006;1016h".utf8))) == [.sgr])
    #expect(await pixels.send(mouse: huntPress) == Array("\u{1B}[<0;32;32M".utf8))
    let urxvt = await trackingHuntEmulator()
    #expect(huntMouseModes(await urxvt.feed(Array("\u{1B}[?1006;1015h".utf8))).isEmpty)
    #expect(await urxvt.send(mouse: huntPress) == Array("\u{1B}[32;5;3M".utf8))
  }

  @Test("w3ca1 encoding probes leave replies and terminal resets alone")
  func w3ca1EncodingProbesLeaveRepliesAndResetsAlone() async {
    let emulator = await drainedHuntEmulator()
    let events = await emulator.feed(Array("\u{1B}[?1006h\u{1B}[5n".utf8))
    #expect(events == [.mouseModeChanged(.sgr), .clientReply(Array("\u{1B}[0n".utf8))])
    #expect(huntMouseModes(await emulator.feed(Array("\u{1B}c".utf8))) == [.disabled])
    #expect(await emulator.send(mouse: huntPress) == Array("\u{1B}[<0;5;3M".utf8))
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

/// A drained emulator whose child has enabled normal tracking (1000).
private func trackingHuntEmulator() async -> TerminalEmulator {
  let emulator = await drainedHuntEmulator()
  _ = await emulator.feed(Array("\u{1B}[?1000h".utf8))
  return emulator
}

private let huntPress = TerminalEmulatorMouse(kind: .down(.primary), cell: CellPoint(x: 4, y: 2))

private func modeAndBellEvents(_ events: [TerminalEmulatorEvent]) -> [TerminalEmulatorEvent] {
  events.filter { event in
    switch event {
    case .mouseModeChanged, .bell: true
    default: false
    }
  }
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
