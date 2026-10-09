import SwiftTUIRuntime
import SwiftTUITerminalEmulation

/// Text review is deliberately separate from arbitrary child widget semantics.
struct TerminalPaneReview<Session: TerminalSession>: View {
  let session: Session
  let frame: TerminalSnapshot
  let title: String
  let clipboard: ClipboardWriteAction
  let handlers: TerminalEventHandlers
  @State private var frozen: TerminalSnapshot?
  @State private var editing = false
  @State private var draft = ""
  @State private var privateInput = false
  @State private var status = ""
  @State private var pending = false
  @AccessibilityFocusState private var reviewFocus: String?

  private var reviewed: TerminalSnapshot { frozen ?? frame }
  private var text: String { TerminalReviewText.output(reviewed) }

  private func reading(_ text: String) -> some View {
    Text(text).accessibilityLabel(text).accessibilityProperties(.init(textKind: .plain))
      .accessibilityAddTraits(.isStaticText)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      reading(TerminalReviewText.sanitized(title, limit: 256))
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($reviewFocus, equals: "title")
      reading(
        "Rows \(reviewed.firstRow + 1) through \(reviewed.firstRow + reviewed.grid.size.height); \(reviewed.buffer == .alternate ? "alternate screen" : "normal screen")"
      )
      if let caret = frame.caret {
        reading("Child caret: row \(caret.y + 1), column \(caret.x + 1)")
      } else {
        reading("Child caret unavailable")
      }
      reading(text.isEmpty ? "No terminal output" : text)
      reading(
        frozen == nil ? "Following output" : "Review frozen; new output does not change this copy")
      if let frozen, frozen.epoch != frame.epoch {
        reading("The terminal buffer changed; this is a saved review")
      } else if let frozen, frozen.firstRow < frame.retainedRows.lowerBound {
        reading("Reviewed rows have left retained history; this copy is preserved")
      }
      Button("Freeze output review") { frozen = frame }
      Button("Earlier output") { move(by: -max(1, reviewed.grid.size.height - 1)) }
        .disabled(
          pending || frame.buffer == .alternate
            || reviewed.firstRow <= frame.retainedRows.lowerBound)
      Button("Later output") { move(by: max(1, reviewed.grid.size.height - 1)) }
        .disabled(
          pending || frame.buffer == .alternate
            || reviewed.firstRow + reviewed.grid.size.height > frame.retainedRows.upperBound)
      Button("Follow latest output") {
        guard !pending else { return }
        pending = true
        Task {
          await session.resumeFollowingOutput()
          frozen = nil
          pending = false
        }
      }.disabled(pending)
      Button("Copy reviewed output") {
        let copied = clipboard(text)
        handlers.copyCompleted?(copied)
        report(copied ? "Output copied" : "Clipboard unavailable; select the review text to copy")
      }
      if editing {
        reading(
          "Line input sends text followed by Return. Use the child program's accessible alternative for full-screen controls."
        )
        Toggle("Hide input", isOn: $privateInput)
        if privateInput {
          SecureField("Child input", text: $draft)
            .accessibilityFocused($reviewFocus, equals: "input")
        } else {
          TextField("Child input", text: $draft)
            .accessibilityFocused($reviewFocus, equals: "input")
        }
        Button("Send line to child") { sendLine() }.disabled(pending)
        Button("Leave child input") {
          editing = false
          draft = ""
          privateInput = false
          reviewFocus = "title"
        }
      } else {
        Button("Enter child line input") {
          editing = true
          reviewFocus = "input"
        }
      }
      if !status.isEmpty { reading(status) }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Terminal pane")
    .accessibilityNavigationCategory("Terminal panes")
  }

  private func move(by lines: Int) {
    guard !pending else { return }
    pending = true
    Task {
      await session.scroll(by: lines)
      frozen = session.cachedTerminalSnapshot
      pending = false
    }
  }

  private func sendLine() {
    guard !pending else { return }
    guard draft.unicodeScalars.count <= 16_384,
      !draft.unicodeScalars.contains(where: { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) })
    else {
      report("Input must be one line without control characters, at most 16384 characters")
      return
    }
    let line = draft
    draft = ""
    pending = true
    Task {
      await session.send(paste: line)
      await session.send(key: .init(code: .enter))
      report("Line sent to child")
      pending = false
    }
  }

  private func report(_ message: String) {
    status = message
    AccessibilityAnnouncer.announce(message)
  }
}

enum TerminalReviewText {
  static func output(_ frame: TerminalSnapshot) -> String {
    var selection = TerminalTextSelection(snapshot: frame, anchor: .zero)
    selection.extend(to: CellPoint(x: frame.grid.size.width - 1, y: frame.grid.size.height - 1))
    return sanitized(selection.text, limit: 16_384)
  }

  /// Cells are already VT-decoded. Also reject control and bidi formatting from custom sessions.
  static func sanitized(_ value: String, limit: Int) -> String {
    let safe = value.unicodeScalars.filter { scalar in
      switch scalar.value {
      case 0x0A: true
      case 0...0x1F, 0x7F...0x9F, 0x202A...0x202E, 0x2066...0x2069: false
      default: true
      }
    }
    let result = String(String.UnicodeScalarView(safe.prefix(limit)))
    return safe.count > limit ? result + "\nReview truncated" : result
  }
}
