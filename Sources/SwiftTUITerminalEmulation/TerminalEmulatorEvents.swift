public import SwiftTUIRuntime

public enum TerminalEmulatorEvent: Sendable, Equatable {
  /// The session has published a new immutable frame, independently of metadata.
  case contentChanged
  case notification(TerminalNotification)
  case titleChanged(String)
  case workingDirectoryChanged(String)
  case clipboardWriteRequested([UInt8])
  case hyperlinkChanged(String?)
  case bell
  /// The child sent a mouse-reporting control. This records the control in input order;
  /// it is not a state record, and the most recent value can misstate the current mode.
  ///
  /// Every tracking control (DECSET or DECRST 9, 1000, 1002, 1003) publishes the resulting
  /// tracking mode, including repeats; a reset publishes ``TerminalMouseMode/disabled``.
  /// A control that changes the encoding the backend applies publishes
  /// ``TerminalMouseMode/sgr`` when the encoding becomes SGR (1006) or SGR-Pixels (1016),
  /// and ``TerminalMouseMode/disabled`` when it changes from either to X10, UTF-8 (1005) or
  /// URXVT (1015), while tracking continues. Other encoding controls publish nothing: a
  /// repeat, a change among X10, UTF-8 and URXVT, or a sequence the backend does not
  /// accept. Reply controls (S8C1T, S7C1T, DECSCL) change only the report introducer and
  /// publish nothing. Within one control sequence, tracking values precede the encoding
  /// value, which reflects the sequence's net change: `ESC[?1006;1000h` publishes
  /// `.button`, then `.sgr`.
  ///
  /// Read whether the child is tracking from ``TerminalSnapshot/mouseTracking``. While it
  /// is, the most recent ``TerminalMouseMode/x10``, ``TerminalMouseMode/button`` or
  /// ``TerminalMouseMode/anyEvent`` value is the tracking mode.
  /// ``TerminalEmulator/send(mouse:)`` applies the child's encoding itself.
  case mouseModeChanged(TerminalMouseMode)
  case clientReply([UInt8])
  case bufferActivated(TerminalBufferKind)
  case sizeReported(CellSize)
}

public enum TerminalBufferKind: Sendable, Equatable {
  case normal
  case alternate
}

/// The value of a ``TerminalEmulatorEvent/mouseModeChanged(_:)`` notification.
///
/// XTerm mouse reporting has two independent settings: tracking selects which pointer
/// events the child receives, and encoding selects how each report is written. Each value
/// describes the control that produced it, not both settings.
public enum TerminalMouseMode: Sendable, Equatable {
  /// Tracking stopped: a reset of 9, 1000, 1002 or 1003, a terminal reset, or the initial
  /// mode reported by the first feed. Also published when the encoding changes from SGR
  /// (1006) or SGR-Pixels (1016) to another encoding, which leaves tracking unchanged.
  case disabled
  /// X10 compatibility tracking (9): the child requested button presses only.
  case x10
  /// Normal (1000) or button-event (1002) tracking: presses and releases, plus motion with
  /// a button held for 1002. The value does not distinguish the two modes.
  case button
  /// Any-event tracking (1003): presses, releases and all pointer motion.
  case anyEvent
  /// The encoding became SGR (1006) or SGR-Pixels (1016), including a switch between the
  /// two. Tracking is unchanged.
  case sgr
}
