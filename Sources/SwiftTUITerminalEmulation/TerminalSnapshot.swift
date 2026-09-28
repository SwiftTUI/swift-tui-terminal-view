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

  public init(
    generation: UInt64, grid: ForeignGrid, wrappedRows: [Bool] = [], firstRow: Int = 0,
    retainedRows: ClosedRange<Int> = 0...0, epoch: UInt64 = 0,
    buffer: TerminalBufferKind = .normal, isFollowingOutput: Bool = true,
    mouseTracking: Bool = false, graphics: [TerminalGraphic] = []
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
  }
}
