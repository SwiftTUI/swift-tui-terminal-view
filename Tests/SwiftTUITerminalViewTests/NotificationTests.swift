import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

@Suite("Pane notification policy", .timeLimit(.minutes(1)))
struct NotificationTests {
  @Test("chunked OSC 99 produces typed requests with isolated identifiers and updates")
  func paneIdentity() async throws {
    let first = TerminalEmulator(size: .init(width: 10, height: 2))
    let second = TerminalEmulator(size: .init(width: 10, height: 2))
    var requests: [TerminalNotification] = []
    for byte in Array(
      "\u{1B}]99;i=same:d=0;Build\u{1B}\\\u{1B}]99;i=same:p=body;Finished\u{07}".utf8)
    {
      requests += notifications(await first.feed([byte]))
    }
    let show = try #require(requests.first)
    #expect(requests.count == 1)
    #expect(show.kind == .show && show.title == "Build" && show.body == "Finished")
    let other = try #require(notifications(await second.feed(osc("i=same", "Other"))).first)
    #expect(other.id != show.id)
    let update = try #require(notifications(await first.feed(osc("i=same", "Updated"))).first)
    #expect(update.id == show.id)
    #expect(update.title == "Updated")
    let close = try #require(notifications(await first.feed(osc("i=same:p=close", ""))).first)
    #expect(close.id == show.id && close.kind == .close)
    #expect(notifications(await first.feed(osc("i=same:p=close", ""))).isEmpty)
  }

  @Test(
    "invalid, oversized and unsupported notifications are swallowed; rate and reset are bounded")
  func bounds() async {
    let emulator = TerminalEmulator(size: .init(width: 10, height: 2))
    #expect(notifications(await emulator.feed(osc("i=x:e=1", "%%%"))).isEmpty)
    #expect(
      notifications(await emulator.feed(osc("i=x", String(repeating: "x", count: 8193)))).isEmpty)
    #expect(notifications(await emulator.feed(osc("i=x:p=icon", "abc"))).isEmpty)
    var delivered: [TerminalNotification] = []
    for index in 0..<20 {
      delivered += notifications(await emulator.feed(osc("i=n\(index)", "message")))
    }
    #expect(delivered.count == 8)
    let closed = notifications(await emulator.feed([27, 99]))
    #expect(closed.count == 8)
    #expect(closed.allSatisfy { $0.kind == .close })
    #expect(await emulator.snapshot().cells.allSatisfy { $0.allSatisfy { $0.character == " " } })
  }

  private func notifications(_ events: [TerminalEmulatorEvent]) -> [TerminalNotification] {
    events.compactMap { if case .notification(let value) = $0 { value } else { nil } }
  }
  private func osc(_ metadata: String, _ payload: String) -> [UInt8] {
    Array("\u{1B}]99;\(metadata);\(payload)\u{1B}\\".utf8)
  }
}
