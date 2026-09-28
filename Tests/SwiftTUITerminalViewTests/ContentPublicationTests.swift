import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

@Suite("Terminal content publication", .timeLimit(.minutes(1)))
struct ContentPublicationTests {
  @Test("plain output wakes the host and final output is published before exit")
  func plainOutput() async throws {
    let session = TerminalProcessSession(
      command: "/bin/sh", arguments: ["-c", "printf READY; read line; printf '\\r\\nFINAL'"],
      initialSize: CellSize(width: 20, height: 3)
    )
    let events = session.events()
    try await session.start()
    var sawReady = false
    var sawFinal = false
    for await event in events {
      guard event == .contentChanged else { continue }
      let text = session.cachedSnapshot.cells.map { String($0.map(\.character)) }.joined()
      if text.contains("READY"), !sawReady {
        sawReady = true
        await session.send(paste: "continue\n")
      }
      if text.contains("FINAL") { sawFinal = true }
    }
    #expect(sawReady)
    #expect(sawFinal)
    #expect(await session.currentLifecycle() == .exited(reason: .normal(code: 0)))
  }

  @Test("retained payloads keep the exact frame captured by the view")
  func immutablePayload() {
    var grid = ForeignGrid(
      size: CellSize(width: 1, height: 1), cells: [[RasterCell(character: "a")]])
    let previous = SessionGridPayload(grid: grid)
    grid.cells[0][0] = RasterCell(character: "b")
    let current = SessionGridPayload(grid: grid)
    #expect(previous.grid.cells[0][0].character == "a")
    #expect(previous.grid != current.grid)
  }

  @Test("dirty-row snapshots match complete replay through text, styles, erase and buffers")
  func dirtyRows() async {
    let size = CellSize(width: 12, height: 4)
    let cached = TerminalEmulator(size: size)
    let replay = TerminalEmulator(size: size)
    let operations = [
      "hello", "\u{1B}[2;1Hworld", "\u{1B}[1;2H\u{1B}[31m界e\u{301}\u{1B}[0m",
      "\r\n" + String(repeating: "scroll\r\n", count: 12), "\u{1B}[2J",
      "\u{1B}[?1049hALT", "\u{1B}[?1049l", "\u{1B}cRESET",
    ]
    var replayed: [UInt8] = []
    for operation in operations {
      let bytes = Array(operation.utf8)
      replayed += bytes
      _ = await cached.feed(bytes)
      let fresh = TerminalEmulator(size: size)
      _ = await fresh.feed(replayed)
      #expect(await cached.snapshot() == fresh.snapshot())
      #expect(await cached.snapshot() == fresh.snapshot())
      _ = await replay.feed(bytes)
    }
    await cached.resize(CellSize(width: 8, height: 6))
    await replay.resize(CellSize(width: 8, height: 6))
    #expect(await cached.snapshot() == replay.snapshot())
  }
}
