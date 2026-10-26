import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

// Wave-3 regression hunt, part CA (STUI-1167): neighbours of the 0.19.4
// TerminalView repairs (STUI-1214 documentation, STUI-1253 highlight, STUI-1254
// encoding probe and framer, STUI-1258 backend filter). Cases w3ca001-w3ca012;
// the hypotheses precede these tests in the hunt's evidence directory. The wave-4
// repair of STUI-1287 promoted w3ca001-w3ca004 and added w4tv01-w4tv02. Stdout is
// process-wide, so the suite is serialized and recorded runs use --no-parallel.
@Suite("Wave-3 hunt CA: TerminalView repair neighbours", .serialized)
struct Wave3RegressionHuntTests {
  // MARK: Encoding probe under 8-bit reply controls (STUI-1254, STUI-1287)

  @Test("w3ca001 under 8-bit controls DECSET 1006 still publishes the SGR encoding")
  func w3ca001EightBitControlsStillPublishTheSGREncoding() async {
    let emulator = await w3TrackingEmulator()
    #expect(w3Modes(await emulator.feed(w3Bytes("\u{1B} G"))).isEmpty)
    let modes = w3Modes(await emulator.feed(w3Bytes("\u{1B}[?1006h")))
    let packet = await emulator.send(mouse: w3Press)
    // The press is SGR, introduced by the 8-bit CSI the child selected (STUI-1287).
    #expect(packet == [0x9B] + w3Bytes("<0;5;3M"))
    #expect(modes == [.sgr], "published \(modes) while the press encodes SGR")
  }

  @Test("w3ca002 entering 8-bit controls with SGR set publishes no encoding change")
  func w3ca002EnteringEightBitControlsPublishesNoEncodingChange() async {
    let emulator = await w3TrackingEmulator()
    #expect(w3Modes(await emulator.feed(w3Bytes("\u{1B}[?1006h"))) == [.sgr])
    #expect(w3Modes(await emulator.feed(w3Bytes("\u{1B} G"))).isEmpty)
    let modes = w3Modes(await emulator.feed(w3Bytes("\u{1B}[?25l")))
    #expect(await emulator.send(mouse: w3Press) == [0x9B] + w3Bytes("<0;5;3M"))
    // A change of the report introducer alone is no encoding change (STUI-1287).
    #expect(modes.isEmpty, "published \(modes) for a cursor control")
  }

  @Test("w3ca003 leaving 8-bit controls publishes no encoding change")
  func w3ca003LeavingEightBitControlsPublishesNoEncodingChange() async {
    // (a) A terminal reset restores 7-bit replies and keeps the SGR encoding.
    let reset = await w3EightBitSGREmulator()
    let resetModes = w3Modes(await reset.feed(w3Bytes("\u{1B}c")))
    #expect(await reset.send(mouse: w3Press) == w3Bytes("\u{1B}[<0;5;3M"))
    // (b) S7C1T restores 7-bit replies; the next unrelated DECSET probes again.
    let sevenBit = await w3EightBitSGREmulator()
    let s7c1tModes = w3Modes(await sevenBit.feed(w3Bytes("\u{1B} F")))
    let cursorModes = w3Modes(await sevenBit.feed(w3Bytes("\u{1B}[?25h")))
    #expect(await sevenBit.send(mouse: w3Press) == w3Bytes("\u{1B}[<0;5;3M"))
    #expect(s7c1tModes.isEmpty)
    // The encoding stayed SGR throughout, so neither publishes .sgr (STUI-1287).
    #expect(resetModes == [.disabled], "RIS published \(resetModes)")
    #expect(cursorModes.isEmpty, "?25h after S7C1T published \(cursorModes)")
  }

  @Test("w3ca004 DECSCL with 8-bit controls still publishes the SGR encoding")
  func w3ca004ConformanceLevelEightBitStillPublishesTheSGREncoding() async {
    let emulator = await w3TrackingEmulator()
    #expect(w3Modes(await emulator.feed(w3Bytes("\u{1B}[62;0\"p"))).isEmpty)
    let modes = w3Modes(await emulator.feed(w3Bytes("\u{1B}[?1006h")))
    #expect(await emulator.send(mouse: w3Press) == [0x9B] + w3Bytes("<0;5;3M"))
    #expect(modes == [.sgr], "published \(modes) while the press encodes SGR")
  }

  @Test("w3ca005 encoding probes stay off the reply stream under 8-bit controls")
  func w3ca005EncodingProbesStayOffEightBitReplies() async {
    let emulator = await w3DrainedEmulator()
    let events = await emulator.feed(w3Bytes("\u{1B} G\u{1B}[?1006h\u{1B}[5n"))
    let replies = events.compactMap { event -> [UInt8]? in
      guard case .clientReply(let bytes) = event else { return nil }
      return bytes
    }
    #expect(replies == [[0x9B] + w3Bytes("0n")])
  }

  // MARK: Reply controls against 7-bit runs (wave 4, STUI-1287)

  @Test("w4tv01 encoding events under 8-bit replies match the 7-bit run at every step")
  func w4tv01EncodingEventsUnderEightBitRepliesMatchSevenBitRuns() async {
    let steps: [(control: [UInt8], modes: [TerminalMouseMode])] = [
      (w3Bytes("\u{1B}[?1006h"), [.sgr]),
      (w3Bytes("\u{1B}[?1006h"), []),
      (w3Bytes("\u{1B}[?1016h"), [.sgr]),
      ([27, 0x9B] + w3Bytes("?1006h"), [.sgr]),
      (w3Bytes("\u{1B}[?25l"), []),
      (w3Bytes("\u{1B}[?1015h"), [.disabled]),
      (w3Bytes("\u{1B}[?1006h"), [.sgr]),
      (w3Bytes("\u{1B}[?1006l"), [.disabled]),
      (w3Bytes("\u{1B}[?1005h"), []),
      (w3Bytes("\u{1B}[?1006;1000h"), [.button, .sgr]),
      (w3Bytes("\u{1B}c"), [.disabled]),
      (w3Bytes("\u{1B}[?25h"), []),
    ]
    let resetStep = 10
    func run(_ prefix: [UInt8]) async -> (modes: [[TerminalMouseMode]], presses: [[UInt8]]) {
      let emulator = await w3TrackingEmulator()
      #expect(w3Modes(await emulator.feed(prefix)).isEmpty, "\(prefix)")
      var modes: [[TerminalMouseMode]] = []
      var presses: [[UInt8]] = []
      for step in steps {
        modes.append(w3Modes(await emulator.feed(step.control)))
        presses.append(await emulator.send(mouse: w3Press))
      }
      return (modes, presses)
    }
    let sevenBit = await run([])
    #expect(sevenBit.modes == steps.map(\.modes))
    #expect(sevenBit.presses.allSatisfy { $0.starts(with: [27, 91]) })
    let prefixes: [(name: String, bytes: [UInt8])] = [
      ("S8C1T", w3Bytes("\u{1B} G")), ("DECSCL 62;0", w3Bytes("\u{1B}[62;0\"p")),
      ("DECSCL 63;2", w3Bytes("\u{1B}[63;2\"p")), ("DECSCL 65;0", w3Bytes("\u{1B}[65;0\"p")),
    ]
    for (name, prefix) in prefixes {
      let eightBit = await run(prefix)
      #expect(eightBit.modes == sevenBit.modes, "\(name) published \(eightBit.modes)")
      for index in steps.indices {
        // RIS restores 7-bit replies; until then only the introducer differs.
        let expected =
          index < resetStep
          ? [0x9B] + sevenBit.presses[index].dropFirst(2) : sevenBit.presses[index]
        #expect(eightBit.presses[index] == expected, "\(name), step \(index)")
      }
    }
  }

  @Test("w4tv02 reply controls publish no encoding change for any encoding")
  func w4tv02ReplyControlsPublishNoEncodingChange() async {
    let steps: [(control: String, eightBit: Bool)] = [
      ("\u{1B} G", true), ("\u{1B}[?25l", true), ("\u{1B} F", false), ("\u{1B}[?25h", false),
      ("\u{1B}[62;0\"p", true), ("\u{1B}[?25l", true), ("\u{1B}[61\"p", false),
      ("\u{1B}[?25h", false), ("\u{1B}[63;2\"p", true), ("\u{1B}[?25l", true),
      ("\u{1B}[62;1\"p", false), ("\u{1B}[?25h", false), ("\u{1B} G", true),
      ("\u{1B}[?25l", true), ("\u{1B}c", false), ("\u{1B}[?25h", false),
    ]
    for encoding in ["", "\u{1B}[?1005h", "\u{1B}[?1006h", "\u{1B}[?1016h", "\u{1B}[?1015h"] {
      let reference = await w3TrackingEmulator()
      _ = await reference.feed(w3Bytes(encoding))
      let packet = await reference.send(mouse: w3Press)
      #expect(packet.starts(with: [27, 91]), "\(encoding.debugDescription)")
      let body = packet.dropFirst(2)
      let emulator = await w3TrackingEmulator()
      _ = await emulator.feed(w3Bytes(encoding))
      for (control, eightBit) in steps {
        let modes = w3Modes(await emulator.feed(w3Bytes(control)))
        let name = "\(encoding.debugDescription), \(control.debugDescription)"
        #expect(modes == (control == "\u{1B}c" ? [.disabled] : []), "\(name) published \(modes)")
        let introducer: [UInt8] = eightBit ? [0x9B] : [27, 91]
        #expect(await emulator.send(mouse: w3Press) == introducer + body, "\(name)")
      }
    }
  }

  // MARK: Framer alignment (STUI-1254, STUI-1258)

  @Test("w3ca006 SOS and PM strings are discarded up to ST")
  func w3ca006SOSAndPMStringsAreDiscarded() async {
    let inputs: [(name: String, bytes: [UInt8], row: String)] = [
      ("PM ended by ESC \\", w3Bytes("\u{1B}^hidden\u{1B}\\X"), "X"),
      ("SOS ended by 8-bit ST", w3Bytes("\u{1B}Xhidden") + [0x9C] + w3Bytes("Y"), "Y"),
      ("SOS then PM", w3Bytes("\u{1B}Xa\u{1B}\\\u{1B}^b\u{1B}\\Z"), "Z"),
    ]
    for (name, bytes, row) in inputs {
      let emulator = TerminalEmulator(size: CellSize(width: 10, height: 1))
      _ = await emulator.feed([])
      let events = await emulator.feed(bytes)
      #expect(events.isEmpty, "\(name): \(events)")
      #expect(await w3RowText(emulator) == row, "\(name)")
    }
  }

  @Test("w3ca009 CAN or SUB inside a DECSET abandons it at every split")
  func w3ca009CancelInsideADecsetAbandonsIt() async {
    for cancel: UInt8 in [0x18, 0x1A] {
      let input = w3Bytes("\u{1B}[?10") + [cancel] + w3Bytes("06h")
      let whole = await w3TrackingEmulator()
      #expect(w3Modes(await whole.feed(input)).isEmpty, "\(cancel)")
      #expect(await whole.send(mouse: w3Press) == w3Bytes("\u{1B}[M %#"), "\(cancel)")
      #expect((await w3RowText(whole)).hasPrefix("06h"), "\(cancel)")
      for split in 1..<input.count {
        let emulator = await w3TrackingEmulator()
        var events = await emulator.feed(Array(input[..<split]))
        events += await emulator.feed(Array(input[split...]))
        #expect(w3Modes(events).isEmpty, "\(cancel), split at byte \(split)")
      }
    }
  }

  @Test("w3ca010 a DCS request ended by the 8-bit ST is answered as with ESC \\")
  func w3ca010DCSRequestEndedByEightBitSTIsAnswered() async {
    func replies(_ bytes: [UInt8]) async -> [[UInt8]] {
      (await w3DrainedEmulator().feed(bytes)).compactMap { event -> [UInt8]? in
        guard case .clientReply(let reply) = event else { return nil }
        return reply
      }
    }
    let sevenBit = await replies(w3Bytes("\u{1B}P$qm\u{1B}\\"))
    let eightBit = await replies(w3Bytes("\u{1B}P$qm") + [0x9C])
    #expect(sevenBit.count == 1)
    #expect(sevenBit.first?.starts(with: w3Bytes("\u{1B}P1$r")) == true, "\(sevenBit)")
    #expect(sevenBit.first?.suffix(2).elementsEqual(w3Bytes("\u{1B}\\")) == true, "\(sevenBit)")
    #expect(eightBit == sevenBit)
  }

  // MARK: Backend filter (STUI-1258)

  @Test("w3ca007 filtered SGR keeps the attributes of colon forms and short colour chains")
  func w3ca007FilteredSGRKeepsColonAndShortChainAttributes() async throws {
    var styles: [ResolvedTextStyle?] = []
    let output = try await w3CaptureStandardOutput {
      for sgr in ["6:1", "1:6", "38:5;6", "38;2;1;6", "4;6;3"] {
        styles.append(await w3FirstStyle(after: "\u{1B}[\(sgr)mX"))
      }
    }
    #expect(output.isEmpty, "host stdout: \(output.debugDescription)")
    #expect(styles[0] == ResolvedTextStyle(emphasis: .bold))
    #expect(styles[1] == ResolvedTextStyle(emphasis: .bold))
    #expect(styles[2] == nil)
    #expect(styles[3] == ResolvedTextStyle(emphasis: .bold))
    #expect(styles[4] == ResolvedTextStyle(emphasis: .italic, underlineStyle: TextLineStyle()))
  }

  @Test("w3ca008 private-marker, intermediate and 24-parameter SGR forms stay quiet")
  func w3ca008PrivateAndIntermediateSGRFormsStayQuiet() async throws {
    let inputs = [
      "\u{1B}[>6mX", "\u{1B}[?6mX", "\u{1B}[=6mX", "\u{1B}[6 mX",
      "\u{1B}[" + String(repeating: "1;", count: 23) + "6mX",
      "\u{1B}[" + String(repeating: "1;", count: 24) + "6mX",
    ]
    var styles: [ResolvedTextStyle?] = []
    let output = try await w3CaptureStandardOutput {
      for input in inputs { styles.append(await w3FirstStyle(after: input)) }
    }
    #expect(output.isEmpty, "host stdout: \(output.debugDescription)")
    #expect(styles == [nil, nil, nil, nil, ResolvedTextStyle(emphasis: .bold), nil])
  }

  @Test("w3ca012 a session child's DECELR and unknown SGR stay off host stdout")
  func w3ca012SessionChildSequencesStayOffHostStandardOutput() async throws {
    let script = "printf 'A\\033[6mB\\033[1;1\\047zC\\033[53mD\\033[0m DONE'"
    let session = TerminalProcessSession(
      command: "/bin/sh", arguments: ["-c", script], initialSize: CellSize(width: 20, height: 3)
    )
    var text = ""
    let output = try await w3CaptureStandardOutput {
      let events = session.events()
      do {
        try await session.start()
      } catch {
        Issue.record("session did not start: \(error)")
        return
      }
      // The stream ends after the child exits and its final output is published.
      for await event in events where event == .contentChanged {
        text = session.cachedSnapshot.cells.map { String($0.map(\.character)) }.joined()
      }
    }
    #expect(output.isEmpty, "host stdout: \(output.debugDescription)")
    #expect(text.contains("ABCD DONE"), "\(text)")
    #expect(await session.currentLifecycle() == .exited(reason: .normal(code: 0)))
  }

  // MARK: Selection highlight (STUI-1253)

  @Test("w3ca011 the highlight keeps underline colour and strikethrough without reverse")
  func w3ca011HighlightKeepsUnderlineColourAndStrikethrough() async {
    let emulator = TerminalEmulator(size: CellSize(width: 10, height: 1))
    _ = await emulator.feed(w3Bytes("\u{1B}[4;58;5;1;9;7mAB"))
    let selection = TerminalTextSelection(
      snapshot: await emulator.captureSnapshot(), anchor: CellPoint(x: 0, y: 0))
    let grid = selection.highlightedGrid
    let selected = grid.cells[0][0].style
    let unselected = grid.cells[0][1].style
    #expect(selected?.backgroundColor == .blue)
    #expect(selected?.foregroundColor == .white)
    #expect(selected?.emphasis.contains(.reverse) == false)
    #expect(unselected?.emphasis.contains(.reverse) == true)
    #expect(unselected?.underlineStyle?.color != nil)
    #expect(selected?.underlineStyle == unselected?.underlineStyle)
    #expect(selected?.strikethroughStyle == TextLineStyle())
  }
}

// MARK: Helpers

private let w3Press = TerminalEmulatorMouse(kind: .down(.primary), cell: CellPoint(x: 4, y: 2))

private func w3Bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

/// SwiftTerm announces its initial mouse mode during construction; drain it.
private func w3DrainedEmulator() async -> TerminalEmulator {
  let emulator = TerminalEmulator(size: CellSize(width: 10, height: 3))
  _ = await emulator.feed([])
  return emulator
}

/// A drained emulator whose child has enabled normal tracking (1000).
private func w3TrackingEmulator() async -> TerminalEmulator {
  let emulator = await w3DrainedEmulator()
  _ = await emulator.feed(w3Bytes("\u{1B}[?1000h"))
  return emulator
}

/// SGR encoding set under 7-bit replies, then 8-bit replies selected and one
/// unrelated private mode reset; the events of these steps are drained.
private func w3EightBitSGREmulator() async -> TerminalEmulator {
  let emulator = await w3TrackingEmulator()
  _ = await emulator.feed(w3Bytes("\u{1B}[?1006h"))
  _ = await emulator.feed(w3Bytes("\u{1B} G"))
  _ = await emulator.feed(w3Bytes("\u{1B}[?25l"))
  return emulator
}

private func w3Modes(_ events: [TerminalEmulatorEvent]) -> [TerminalMouseMode] {
  events.compactMap { event -> TerminalMouseMode? in
    guard case .mouseModeChanged(let mode) = event else { return nil }
    return mode
  }
}

private func w3RowText(_ emulator: TerminalEmulator) async -> String {
  let row = (await emulator.snapshot()).cells[0].map(\.character)
  return String(String(row).reversed().drop { $0 == " " }.reversed())
}

private func w3FirstStyle(after input: String) async -> ResolvedTextStyle? {
  let emulator = TerminalEmulator(size: CellSize(width: 10, height: 1))
  _ = await emulator.feed(w3Bytes(input))
  return (await emulator.snapshot()).cells[0][0].style
}

/// Copied from `EmulatorWrapperTests.captureStandardOutput`: a regular file cannot
/// fill like an undrained pipe, and the recorded runs serialize every test.
private func w3CaptureStandardOutput(
  _ operation: () async -> Void
) async throws -> String {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("terminal-view-w3hunt-stdout-\(UUID().uuidString)")
  try Data().write(to: url)
  defer { try? FileManager.default.removeItem(at: url) }
  let capture = try FileHandle(forWritingTo: url)
  fflush(nil)
  let original = dup(STDOUT_FILENO)
  guard original >= 0 else { throw POSIXError(.EBADF) }
  defer {
    fflush(nil)
    dup2(original, STDOUT_FILENO)
    close(original)
    try? capture.close()
  }
  guard dup2(capture.fileDescriptor, STDOUT_FILENO) >= 0 else { throw POSIXError(.EBADF) }
  await operation()
  fflush(nil)
  return String(decoding: try Data(contentsOf: url), as: UTF8.self)
}
