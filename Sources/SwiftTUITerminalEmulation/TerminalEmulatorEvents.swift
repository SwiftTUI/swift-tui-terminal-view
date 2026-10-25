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
  /// Setting SGR encoding (1006 or 1016) publishes ``TerminalMouseMode/sgr``, and resetting
  /// it publishes ``TerminalMouseMode/disabled`` while tracking continues. UTF-8 (1005) and
  /// URXVT (1015) encoding controls publish nothing. Within one control sequence, tracking
  /// values precede encoding values: `ESC[?1006;1000h` publishes `.button`, then `.sgr`.
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
  /// mode reported by the first feed. Also published when SGR encoding (1006 or 1016) is
  /// reset, which leaves tracking unchanged.
  case disabled
  /// X10 compatibility tracking (9): the child requested button presses only.
  case x10
  /// Normal (1000) or button-event (1002) tracking: presses and releases, plus motion with
  /// a button held for 1002. The value does not distinguish the two modes.
  case button
  /// Any-event tracking (1003): presses, releases and all pointer motion.
  case anyEvent
  /// SGR (1006) or SGR-Pixels (1016) encoding was selected. Tracking is unchanged.
  case sgr
}
