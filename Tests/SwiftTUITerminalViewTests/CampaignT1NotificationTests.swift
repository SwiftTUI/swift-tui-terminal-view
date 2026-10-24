import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

@Suite("Campaign T1 notification contracts", .serialized, .timeLimit(.minutes(1)))
struct CampaignT1NotificationTests {
  @Test(arguments: Array(71...80))
  func notifications(id: Int) async throws {
    let emulator = TerminalEmulator(size: .init(width: 12, height: 4))
    func packet(_ metadata: String, _ text: String, bel: Bool = false) -> [UInt8] {
      Array("\u{1B}]99;\(metadata);\(text)\(bel ? "\u{7}" : "\u{1B}\\")".utf8)
    }
    func requests(_ events: [TerminalEmulatorEvent]) -> [TerminalNotification] {
      events.compactMap { if case .notification(let value) = $0 { value } else { nil } }
    }
    switch id {
    case 71:
      #expect(requests(await emulator.feed(packet("i=A:d=0", "界"))).isEmpty)
      let encoded = Data("body é".utf8).base64EncodedString()
      let result = try #require(
        requests(await emulator.feed(packet("i=A:p=body:e=1", encoded))).first)
      #expect(result.title == "界" && result.body == "body é")
    case 72:
      let first = try #require(requests(await emulator.feed(packet("", "same"))).first)
      let second = try #require(requests(await emulator.feed(packet("", "same"))).first)
      #expect(first.id != second.id && first.title == second.title)
    case 73:
      let first = try #require(requests(await emulator.feed(packet("i=A", "first"))).first)
      let second = try #require(requests(await emulator.feed(packet("i=A:p=body", "second"))).first)
      #expect(first.id == second.id)
      #expect(second.title.isEmpty && second.body == "second")
    case 74:
      _ = await emulator.feed(packet("i=A:d=0", "old"))
      #expect(requests(await emulator.feed(packet("i=A:p=close", ""))).isEmpty)
      let result = try #require(requests(await emulator.feed(packet("i=A", "new"))).first)
      #expect(result.title == "new")
    case 75:
      let first = try #require(requests(await emulator.feed(packet("i=A", "one"))).first)
      let second = try #require(requests(await emulator.feed(packet("i=B", "two"))).first)
      let closed = requests(await emulator.feed([27, 99]))
      #expect(Set(closed.map(\.id)) == [first.id, second.id])
      #expect(closed.allSatisfy { $0.kind == .close })
      #expect(requests(await emulator.feed([27, 99])).isEmpty)
    case 76:
      let first = try #require(
        requests(await emulator.feed(packet("i=A", "title", bel: true))).first)
      let second = try #require(requests(await emulator.feed(packet("i=B", "title"))).first)
      #expect(first.title == second.title && first.body == second.body)
    case 77:
      let result = try #require(
        requests(await emulator.feed(packet("i=A:unused=value", "title"))).first)
      #expect(result.title == "title")
    case 78:
      let result = try #require(requests(await emulator.feed(packet("i=A", "a\tb\nc"))).first)
      #expect(result.title == "a\tb\nc")
    case 79:
      _ = await emulator.feed(Array("plain".utf8))
      let before = await emulator.snapshot()
      let result = requests(await emulator.feed(packet("i=A", "message")))
      #expect(result.count == 1)
      #expect(await emulator.snapshot() == before)
    default:
      _ = await emulator.feed(packet("i=A:d=0", "A title"))
      _ = await emulator.feed(packet("i=B:d=0", "B title"))
      let b = try #require(requests(await emulator.feed(packet("i=B:p=body", "B body"))).first)
      let a = try #require(requests(await emulator.feed(packet("i=A:p=body", "A body"))).first)
      #expect(a.title == "A title" && a.body == "A body")
      #expect(b.title == "B title" && b.body == "B body")
    }
  }
}
