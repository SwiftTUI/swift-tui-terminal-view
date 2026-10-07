import Dispatch
import Foundation
import Synchronization

// Separate files keep concurrent sessions independent. Synchronous writes bound
// diagnostic memory too; enable only in diagnostic runs, never acceptance timing.
final class TerminalSessionTrace: Sendable {
  private let file: Mutex<FileHandle>

  init?() {
    guard let directory = ProcessInfo.processInfo.environment["SWIFTTUI_PTY_DIAGNOSTICS"] else {
      return nil
    }
    let path = URL(fileURLWithPath: directory)
      .appendingPathComponent("session-\(UUID().uuidString).tsv").path
    guard FileManager.default.createFile(atPath: path, contents: nil),
      let handle = FileHandle(forWritingAtPath: path)
    else { return nil }
    file = Mutex(handle)
    try? handle.write(contentsOf: Data("time_ns\tevent\tbytes\n".utf8))
  }

  deinit { file.withLock { try? $0.close() } }

  func record(_ event: String, bytes: Int = 0) {
    let line = "\(DispatchTime.now().uptimeNanoseconds)\t\(event)\t\(bytes)\n"
    file.withLock { try? $0.write(contentsOf: Data(line.utf8)) }
  }
}
