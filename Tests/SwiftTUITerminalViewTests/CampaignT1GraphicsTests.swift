import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

@Suite("Campaign T1 finite graphic lifecycle contracts", .serialized, .timeLimit(.minutes(1)))
struct CampaignT1GraphicsTests {
  @Test(arguments: Array(81...90))
  func graphics(id: Int) async throws {
    let emulator = TerminalEmulator(size: .init(width: 12, height: 4))
    let red = Data([255, 0, 0, 255]).base64EncodedString()
    let blue = Data([0, 0, 255, 255]).base64EncodedString()
    func packet(_ control: String, _ data: String = "") -> [UInt8] {
      Array("\u{1B}_G\(control);\(data)\u{1B}\\".utf8)
    }
    if id == 81 { _ = await emulator.feed(Array("\u{1B}[2;3H".utf8)) }
    if id == 90 { _ = await emulator.feed(Array("hello".utf8)) }
    _ = await emulator.feed(packet("a=T,f=32,s=1,v=1,i=1,p=1,C=1,c=2,r=1", red))
    let before = await emulator.captureSnapshot()
    let first = try #require(before.graphics.first)
    switch id {
    case 81:
      #expect(first.pixelSize == .init(width: 1, height: 1))
      #expect(first.bounds == .init(origin: .init(x: 2, y: 1), size: .init(width: 2, height: 1)))
    case 82:
      _ = await emulator.feed(Array("\u{1B}[3;5H".utf8))
      _ = await emulator.feed(packet("a=T,f=32,s=1,v=1,i=2,p=1,C=1", blue))
      let images = await emulator.captureSnapshot().graphics
      #expect(images.count == 2)
      #expect(Set(images.map(\.id)).count == 2)
      #expect(images.contains { $0.bounds.origin == .init(x: 4, y: 2) })
      #expect(images.contains { $0.id == first.id && $0.bounds == first.bounds })
    case 83:
      _ = await emulator.feed(packet("a=t,f=32,s=1,v=1,i=1", blue))
      let after = try #require(await emulator.captureSnapshot().graphics.first)
      #expect(after.id == first.id && after.bounds == first.bounds)
      #expect(after.png != first.png)
    case 84:
      _ = await emulator.feed(packet("a=T,f=32,s=1,v=1,i=2,p=1,C=1", blue))
      let both = await emulator.captureSnapshot().graphics
      let second = try #require(both.first { $0.id != first.id })
      _ = await emulator.feed(packet("a=d,d=I,i=1"))
      #expect(await emulator.captureSnapshot().graphics == [second])
    case 85, 86:
      _ = await emulator.feed(Array("\u{1B}[?1049h".utf8))
      _ = await emulator.feed(packet("a=T,f=32,s=1,v=1,i=2,p=1,C=1", blue))
      #expect(await emulator.captureSnapshot().graphics.count == 1)
      if id == 86 {
        _ = await emulator.feed(Array("\u{1B}[K".utf8))
        #expect(await emulator.captureSnapshot().graphics.isEmpty)
      }
      _ = await emulator.feed(Array("\u{1B}[?1049l".utf8))
      #expect(await emulator.captureSnapshot().graphics == [first])
    case 87:
      _ = await emulator.feed([27, 99])
      #expect(await emulator.captureSnapshot().graphics.isEmpty)
      #expect(before.graphics == [first])
    case 88:
      await emulator.resize(.init(width: 8, height: 3))
      let resized = await emulator.captureSnapshot()
      #expect(resized.graphics.isEmpty && resized.epoch != before.epoch)
    case 89:
      let chunked = TerminalEmulator(size: .init(width: 12, height: 4))
      _ = await chunked.feed(
        packet("a=T,f=32,s=1,v=1,i=1,p=1,C=1,c=2,r=1,m=1", String(red.prefix(4))))
      #expect(await chunked.captureSnapshot().graphics.isEmpty)
      _ = await chunked.feed(packet("m=0", String(red.dropFirst(4))))
      let assembled = try #require(await chunked.captureSnapshot().graphics.first)
      #expect(
        assembled.png == first.png && assembled.pixelSize == first.pixelSize
          && assembled.bounds == first.bounds)
    default:
      _ = await emulator.feed(packet("a=t,f=32,s=1,v=1,i=1", blue))
      let changed = await emulator.captureSnapshot()
      #expect(changed.grid == before.grid)
      #expect(before.graphics == [first] && changed.graphics.first?.png != first.png)
      #expect(changed.grid.cells[0].prefix(5).map(\.character) == Array("hello"))
    }
  }
}
