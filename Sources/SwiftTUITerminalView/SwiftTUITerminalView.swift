// Terminal program embedding requires POSIX; Windows is unsupported.
#if !os(Windows)
  @_exported import SwiftTUIPTYPrimitives
  @_exported import SwiftTUIRuntime
  @_exported import SwiftTUITerminalEmulation
#endif
