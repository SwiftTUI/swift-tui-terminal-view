public import SwiftTUIRuntime

/// An immutable viewport. Row numbers are stable within a buffer epoch; resize/reset starts a new epoch.
public struct TerminalSnapshot: Sendable, Equatable {
  public let generation: UInt64
  public let grid: ForeignGrid
  public let wrappedRows: [Bool]
  public let firstRow: Int
  public let retainedRows: ClosedRange<Int>
  public let epoch: UInt64
  public let buffer: TerminalBufferKind
  public let isFollowingOutput: Bool
  public let graphics: [TerminalGraphic]
  public let mouseTracking: Bool
  /// Child cursor in zero-based columns and absolute rows of this buffer epoch.
  /// This is the logical input position, independent of cursor paint visibility.
  public let caret: CellPoint?

  public init(
    generation: UInt64, grid: ForeignGrid, wrappedRows: [Bool] = [], firstRow: Int = 0,
    retainedRows: ClosedRange<Int> = 0...0, epoch: UInt64 = 0,
    buffer: TerminalBufferKind = .normal, isFollowingOutput: Bool = true,
    mouseTracking: Bool = false, graphics: [TerminalGraphic] = [], caret: CellPoint? = nil
  ) {
    self.generation = generation
    self.grid = grid
    self.wrappedRows = wrappedRows
    self.firstRow = firstRow
    self.retainedRows = retainedRows
    self.epoch = epoch
    self.buffer = buffer
    self.isFollowingOutput = isFollowingOutput
    self.mouseTracking = mouseTracking
    self.graphics = graphics
    self.caret = caret
  }
}
