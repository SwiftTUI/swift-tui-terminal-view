import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

@Suite("Campaign T1 finite session contracts", .serialized, .timeLimit(.minutes(1)))
struct CampaignT1SessionTests {
  @Test(arguments: Array(61...70))
  func sessions(id: Int) async throws {
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-tui-absent-\(UUID().uuidString)").path
    let text = id == 63 ? "a界e\u{301}" : (id == 68 ? "first\r\nlast" : "FINAL")
    let session = TerminalProcessSession(
      command: id == 61 ? missing : "/usr/bin/printf", arguments: ["%s", text],
      workingDirectory: id == 62 ? missing : nil, initialSize: .init(width: 12, height: 4))
    let events = session.events()
    if id == 61 || id == 62 {
      var failedBeforeLaunch = false
      do {
        try await session.start()
      } catch { failedBeforeLaunch = true }
      for await _ in events {}
      // POSIX chdir/exec failures happen in the child and return exit 127.
      // A host that rejects startup before launch closes the session instead.
      let expected: TerminalExitReason = failedBeforeLaunch ? .sessionClosed : .normal(code: 127)
      #expect(await session.currentLifecycle() == .exited(reason: expected))
      for await _ in session.events() {}
      return
    }
    if id == 66 {
      await session.terminate()
      await session.terminate()
      try await session.start()
      for await _ in events {}
      #expect(await session.currentLifecycle() == .exited(reason: .sessionClosed))
      #expect(
        !session.cachedSnapshot.cells.map { String($0.map(\.character)) }.joined().contains("FINAL")
      )
      return
    }
    if id == 70 {
      let failed = TerminalProcessSession(
        command: missing, initialSize: .init(width: 12, height: 4))
      let failedEvents = failed.events()
      var failedBeforeLaunch = false
      do {
        try await failed.start()
      } catch { failedBeforeLaunch = true }
      for await _ in failedEvents {}
      let expected: TerminalExitReason = failedBeforeLaunch ? .sessionClosed : .normal(code: 127)
      #expect(await failed.currentLifecycle() == .exited(reason: expected))
    }
    let secondSubscriber = id == 64 ? session.events() : nil
    try await session.start()
    for await _ in events {}
    if let secondSubscriber { for await _ in secondSubscriber {} }
    #expect(await session.currentLifecycle() == .exited(reason: .normal(code: 0)))
    let frame = session.cachedTerminalSnapshot
    let output = frame.grid.cells.map { String($0.map(\.character)) }.joined(separator: "\n")
    switch id {
    case 63:
      #expect(frame.grid.cells[0][0].character == "a")
      #expect(frame.grid.cells[0][1].character == "界" && frame.grid.cells[0][1].spanWidth == 2)
      #expect(frame.grid.cells[0][3].character == "e\u{301}")
    case 65:
      try await session.start()
      for await _ in session.events() {}
      #expect(session.cachedTerminalSnapshot == frame)
    case 67:
      await session.terminate()
      await session.terminate()
      #expect(await session.currentLifecycle() == .exited(reason: .normal(code: 0)))
      #expect(session.cachedTerminalSnapshot == frame)
    case 68:
      #expect(output.contains("first") && output.contains("last"))
      #expect(await session.snapshot() == frame.grid)
    case 69:
      let other = TerminalProcessSession(
        command: "/usr/bin/printf", arguments: ["%s", "OTHER"],
        initialSize: .init(width: 12, height: 4))
      let otherEvents = other.events()
      try await other.start()
      for await _ in otherEvents {}
      #expect(
        other.cachedSnapshot.cells.map { String($0.map(\.character)) }.joined().contains("OTHER"))
      #expect(output.contains("FINAL") && session.cachedTerminalSnapshot == frame)
    default: #expect(output.contains("FINAL"))
    }
  }
}
