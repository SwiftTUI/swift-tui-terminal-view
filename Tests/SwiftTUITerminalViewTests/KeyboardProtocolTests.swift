import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

@Suite("Embedded keyboard protocol", .timeLimit(.minutes(1)))
struct KeyboardProtocolTests {
  @Test("legacy control, option, special keys and application cursor are byte exact")
  func legacy() async {
    let emulator = TerminalEmulator(size: .init(width: 20, height: 4))
    let cases: [(TerminalEmulatorKey, [UInt8])] = [
      (.init(code: .character("c"), modifiers: .control), [3]),
      (.init(code: .character("d"), modifiers: .control), [4]),
      (.init(code: .character(" "), modifiers: .control), [0]),
      (.init(code: .character("界"), modifiers: .option), [27] + Array("界".utf8)),
      (.init(code: .arrowUp, modifiers: [.control, .shift]), Array("\u{1B}[1;6A".utf8)),
      (.init(code: .tab, modifiers: .shift), Array("\u{1B}[Z".utf8)),
      (.init(code: .function(1)), Array("\u{1B}OP".utf8)),
      (.init(code: .function(12), modifiers: .option), Array("\u{1B}[24;3~".utf8)),
      (.init(code: .function(99)), []),
    ]
    for (key, expected) in cases { #expect(await emulator.encode(key: key) == expected) }
    _ = await emulator.feed(Array("\u{1B}[?1h".utf8))
    #expect(await emulator.encode(key: .init(code: .arrowUp)) == Array("\u{1B}OA".utf8))
  }

  @Test("split negotiation, stacks, buffer isolation, reset and honest capability replies")
  func negotiation() async {
    let first = TerminalEmulator(size: .init(width: 20, height: 4))
    let second = TerminalEmulator(size: .init(width: 20, height: 4))
    let controlC = TerminalEmulatorKey(code: .character("c"), modifiers: .control)
    var events: [TerminalEmulatorEvent] = []
    for byte in Array("\u{1B}[>31u\u{1B}[?u".utf8) {
      events += await first.feed([byte])
    }
    #expect(events.contains(.clientReply(Array("\u{1B}[?25u".utf8))))
    #expect(await first.encode(key: controlC) == Array("\u{1B}[99;5u".utf8))
    #expect(await second.encode(key: controlC) == [3])
    #expect(await first.encode(key: .init(code: .character("é"))) == Array("\u{1B}[233;;233u".utf8))
    #expect(await first.encode(key: .init(code: .function(3))) == Array("\u{1B}[13~".utf8))
    _ = await first.feed(Array("\u{1B}[?1049h".utf8))
    #expect(await first.encode(key: controlC) == [3])
    _ = await first.feed(Array("\u{1B}[?1049l".utf8))
    #expect(await first.encode(key: controlC) == Array("\u{1B}[99;5u".utf8))
    _ = await first.feed(Array("\u{1B}[<u".utf8))
    #expect(await first.encode(key: controlC) == [3])
    _ = await first.feed(Array("\u{1B}[>1u".utf8))
    #expect(await first.encode(key: .init(code: .tab, modifiers: .shift)) == Array("\u{1B}[Z".utf8))
    _ = await first.feed(Array("\u{1B}c".utf8))
    #expect(await first.encode(key: controlC) == [3])
  }

  @Test("negotiated input reaches a real child through the session")
  func childReceivesControl() async throws {
    let session = TerminalProcessSession(
      command: "/bin/sh",
      arguments: [
        "-c", "stty raw -echo; printf '\\033[>1uREADY'; dd bs=1 count=7 2>/dev/null | od -An -tx1",
      ],
      initialSize: .init(width: 80, height: 4)
    )
    let events = session.events()
    try await session.start()
    var sent = false
    for await event in events {
      if event == .contentChanged, !sent,
        session.cachedSnapshot.cells.map({ String($0.map(\.character)) }).joined().contains("READY")
      {
        sent = true
        await session.send(key: .init(code: .character("c"), modifiers: .control))
      }
    }
    #expect(sent)
    let text = session.cachedSnapshot.cells.map { String($0.map(\.character)) }.joined()
    #expect(
      text.split(whereSeparator: \.isWhitespace).suffix(7) == [
        "1b", "5b", "39", "39", "3b", "35", "75",
      ])
  }
}
