public import SwiftTUIRuntime
public import SwiftTUITerminalEmulation

/// A selection freezes its source frame, so new output cannot change what is copied.
public struct TerminalTextSelection: Sendable, Equatable {
  public let snapshot: TerminalSnapshot
  public let anchor: CellPoint
  public private(set) var focus: CellPoint

  public init(snapshot: TerminalSnapshot, anchor: CellPoint) {
    self.snapshot = snapshot
    self.anchor = Self.clamp(anchor, to: snapshot.grid.size)
    self.focus = self.anchor
  }

  public mutating func extend(to point: CellPoint) {
    focus = Self.clamp(point, to: snapshot.grid.size)
  }

  public var text: String {
    let (start, end) = bounds
    var result = ""
    guard !snapshot.grid.cells.isEmpty else { return result }
    for y in start.y...end.y where snapshot.grid.cells.indices.contains(y) {
      let row = snapshot.grid.cells[y]
      let left = y == start.y ? start.x : 0
      let right = y == end.y ? end.x : row.count - 1
      var text = ""
      for x in row.indices where x >= left && x <= right {
        if !row[x].isContinuation { text.append(row[x].character) }
      }
      let continues =
        y < end.y && snapshot.wrappedRows.indices.contains(y + 1) && snapshot.wrappedRows[y + 1]
      if !continues {
        while text.last == " " { text.removeLast() }
      }
      result += text
      if y < end.y && !continues { result += "\n" }
    }
    return result
  }

  public var highlightedGrid: ForeignGrid {
    var grid = snapshot.grid
    let (start, end) = bounds
    for y in grid.cells.indices where y >= start.y && y <= end.y {
      for x in grid.cells[y].indices {
        guard (y != start.y || x >= start.x) && (y != end.y || x <= end.x) else { continue }
        var style = grid.cells[y][x].style ?? ResolvedTextStyle()
        style.backgroundColor = .blue
        style.foregroundColor = .white
        grid.cells[y][x].style = style
      }
    }
    return grid
  }

  private var bounds: (CellPoint, CellPoint) {
    let forward = anchor.y < focus.y || (anchor.y == focus.y && anchor.x <= focus.x)
    var start = forward ? anchor : focus
    var end = forward ? focus : anchor
    if snapshot.grid.cells.indices.contains(start.y),
      snapshot.grid.cells[start.y].indices.contains(start.x),
      let lead = snapshot.grid.cells[start.y][start.x].continuationLeadX
    {
      start.x = lead
    }
    if snapshot.grid.cells.indices.contains(end.y),
      snapshot.grid.cells[end.y].indices.contains(end.x)
    {
      end.x = min(
        snapshot.grid.size.width - 1, end.x + snapshot.grid.cells[end.y][end.x].spanWidth - 1)
    }
    return (start, end)
  }

  private static func clamp(_ point: CellPoint, to size: CellSize) -> CellPoint {
    CellPoint(
      x: max(0, min(max(0, size.width - 1), point.x)),
      y: max(0, min(max(0, size.height - 1), point.y)))
  }
}
