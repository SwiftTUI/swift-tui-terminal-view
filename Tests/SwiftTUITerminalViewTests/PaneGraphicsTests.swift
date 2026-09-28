import Foundation
import SwiftTUIRuntime
import Testing

@testable import SwiftTUITerminalView

@Suite("Pane graphics", .timeLimit(.minutes(1)))
struct PaneGraphicsTests {
  @Test("Sixel is bounded, incremental, pane-owned and cleared by erase or resize")
  func sixel() async throws {
    let emulator = TerminalEmulator(size: .init(width: 10, height: 4))
    for byte in Array("\u{1B}Pq#1;2;100;0;0!8~\u{1B}\\".utf8) { _ = await emulator.feed([byte]) }
    let image = try #require(await emulator.captureSnapshot().graphics.first)
    #expect(image.pixelSize == PixelSize(width: 8, height: 6))
    #expect(Array(image.png.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    _ = await emulator.feed(Array("\u{1B}Pq#1!999999999999999999~\u{1B}\\".utf8))
    #expect(await emulator.captureSnapshot().graphics.count == 1)
    _ = await emulator.feed(Array("\u{1B}[2J".utf8))
    #expect(await emulator.captureSnapshot().graphics.isEmpty)
    _ = await emulator.feed(Array("\u{1B}Pq#1!8~\u{1B}\\".utf8))
    await emulator.resize(.init(width: 8, height: 3))
    #expect(await emulator.captureSnapshot().graphics.isEmpty)
  }

  @Test("Kitty IDs, replies, replacement, chunk assembly and deletion stay within a session")
  func kittyIsolation() async throws {
    let first = TerminalEmulator(size: .init(width: 10, height: 4))
    let second = TerminalEmulator(size: .init(width: 10, height: 4))
    let red = Data([255, 0, 0, 255]).base64EncodedString()
    let blue = Data([0, 0, 255, 255]).base64EncodedString()
    let firstReply = await first.feed(kitty("a=T,f=32,s=1,v=1,i=7,p=2,C=1", red))
    _ = await second.feed(kitty("a=T,f=32,s=1,v=1,i=7,p=2,C=1", blue))
    #expect(firstReply.contains(.clientReply(Array("\u{1B}_Gi=7,p=2;OK\u{1B}\\".utf8))))
    let before = try #require(await first.captureSnapshot().graphics.first)
    #expect(
      await first.captureSnapshot().graphics.first?.png
        != second.captureSnapshot().graphics.first?.png)
    _ = await first.feed(kitty("a=t,f=32,s=1,v=1,i=7,m=1", String(blue.prefix(4))))
    _ = await first.feed(kitty("m=0", String(blue.dropFirst(4))))
    let after = try #require(await first.captureSnapshot().graphics.first)
    #expect(before.id == after.id)
    #expect(before.png != after.png)
    _ = await first.feed(kitty("a=d,d=I,i=7", ""))
    #expect(await first.captureSnapshot().graphics.isEmpty)
    #expect(await second.captureSnapshot().graphics.count == 1)
    let rejected = await first.feed(
      kitty("a=T,t=f,f=32,s=1,v=1,i=8,C=1", Data("/etc/passwd".utf8).base64EncodedString()))
    #expect(
      rejected.contains {
        if case .clientReply(let bytes) = $0 {
          return String(decoding: bytes, as: UTF8.self).contains("ENOTSUP")
        }
        return false
      })
  }

  @Test("graphics survive normal scroll, are isolated by alternate buffer, and dispose on reset")
  func lifecycle() async {
    let emulator = TerminalEmulator(size: .init(width: 10, height: 3), scrollbackLimit: 8)
    let packet = kitty("a=T,f=32,s=1,v=1,i=7,C=1", "/////w==")
    _ = await emulator.feed(packet)
    _ = await emulator.feed(Array("\r\n\r\n\r\n".utf8))
    #expect(await emulator.captureSnapshot().graphics.first?.bounds.origin.y == -1)
    await emulator.scroll(by: -1)
    #expect(await emulator.captureSnapshot().graphics.first?.bounds.origin.y == 0)
    _ = await emulator.feed(Array("\u{1B}[?1049h".utf8))
    #expect(await emulator.captureSnapshot().graphics.isEmpty)
    _ = await emulator.feed(Array("\u{1B}[?1049l".utf8))
    #expect(await emulator.captureSnapshot().graphics.count == 1)
    for _ in 0..<50 {
      _ = await emulator.feed(packet)
      _ = await emulator.feed(Array("\u{1B}c".utf8))
      #expect(await emulator.captureSnapshot().graphics.isEmpty)
    }
  }

  @Test("resource exhaustion and truncated transfers cannot leak into terminal text")
  func boundsAndCancellation() async {
    let emulator = TerminalEmulator(size: .init(width: 10, height: 3))
    for id in 1...40 { _ = await emulator.feed(kitty("a=T,f=32,s=1,v=1,i=\(id),C=1", "/////w==")) }
    #expect(await emulator.captureSnapshot().graphics.count == 32)
    _ = await emulator.feed(Array("\u{1B}_Ga=T,i=90;unfinished".utf8))
    _ = await emulator.feed([24] + Array("OK".utf8))
    #expect(await emulator.snapshot().cells[0].prefix(2).map(\.character) == ["O", "K"])
    _ = await emulator.feed(kitty("a=d,d=A", ""))
    #expect(await emulator.captureSnapshot().graphics.isEmpty)
    let bad = await emulator.feed(kitty("a=T,f=32,s=1025,v=1,i=1,C=1", "/////w=="))
    #expect(
      bad.contains {
        if case .clientReply(let bytes) = $0 {
          return String(decoding: bytes, as: UTF8.self).contains("EINVAL")
        }
        return false
      })
  }

  @Test("non-image DCS status queries remain available")
  func statusQuery() async {
    let emulator = TerminalEmulator(size: .init(width: 10, height: 3))
    let events = await emulator.feed(Array("\u{1B}P$qm\u{1B}\\".utf8))
    #expect(
      events.contains {
        if case .clientReply(let bytes) = $0 {
          return String(decoding: bytes, as: UTF8.self).contains("$r")
        }
        return false
      })
  }

  @MainActor
  @Test(
    "ordinary image composition clips to each pane and gives equal child IDs distinct render identities"
  )
  func composition() async throws {
    let emulator = TerminalEmulator(size: .init(width: 4, height: 2))
    _ = await emulator.feed(kitty("a=T,f=32,s=1,v=1,i=7,C=1,c=20,r=10", "/////w=="))
    let frame = await emulator.captureSnapshot()
    let rendered = DefaultRenderer().render(
      HStack(spacing: 0) {
        TerminalView(session: GraphicSession(frame: frame)).frame(width: 4, height: 2)
        TerminalView(session: GraphicSession(frame: frame)).frame(width: 4, height: 2)
        Text("sibling").frame(width: 7, height: 2)
      }, proposal: ProposedSize(width: 15, height: 2)
    )
    let attachments = rendered.rasterSurface.imageAttachments
    #expect(attachments.count == 2)
    #expect(attachments[0].identity != attachments[1].identity)
    #expect(
      attachments.allSatisfy {
        $0.visibleBounds.size.width <= 4 && $0.visibleBounds.size.height <= 2
      })
    #expect(
      rendered.rasterSurface.cells.map { String($0.map(\.character)) }.joined().contains("sibling"))
  }

  private func kitty(_ control: String, _ payload: String) -> [UInt8] {
    Array("\u{1B}_G\(control);\(payload)\u{1B}\\".utf8)
  }
}

private final class GraphicSession: TerminalSession {
  let frame: TerminalSnapshot
  init(frame: TerminalSnapshot) { self.frame = frame }
  var cachedSnapshot: ForeignGrid { frame.grid }
  var cachedTerminalSnapshot: TerminalSnapshot { frame }
  func start() async throws {}
  func snapshot() async -> ForeignGrid { frame.grid }
  func currentTitle() async -> String? { nil }
  func currentWorkingDirectory() async -> String? { nil }
  func currentLifecycle() async -> TerminalLifecycle { .running }
  func send(key: TerminalEmulatorKey) async {}
  func send(paste: String) async {}
  func send(mouse: TerminalEmulatorMouse) async {}
  func resize(_ size: CellSize) async throws {}
  func events() -> AsyncStream<TerminalEmulatorEvent> { AsyncStream { $0.finish() } }
}
