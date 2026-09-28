# Architecture

`SwiftTUITerminalView` composes `ForeignSurface` through the public framework
runtime surface. `TerminalView` owns the view lifecycle, focused input routing,
host focus binding, and event callbacks. `TerminalSession` separates presentation
from process ownership. `TerminalProcessSession` connects a framework
`ChildProcessPty` to the emulator, pumps bytes, publishes events, and caches the
latest immutable `TerminalSnapshot`. A one-slot signal stream coalesces frame
work at 16 ms while the PTY consumer preserves all bytes and ordered events.
The draw payload captures a grid value so old frames cannot read newer state. PTY spawning and the C shim remain framework-owned because CLI
attach and entry-point tests also use them.

`SwiftTUITerminalEmulation` is an internal target re-exported by the umbrella.
It alone depends on SwiftTerm and translates terminal output into `ForeignGrid`
and typed events, keys, and mouse input. No SwiftTerm type crosses its public API.
Both targets consume public framework products, with no package-internal access.

The umbrella re-exports Runtime, PTYPrimitives, and Emulation. Tests use the
existing public testing support product for view input and lifecycle checks;
they never testably import framework internals. Presentation planner byte-budget
regressions live in the framework, while real-process output coverage lives here.

Pointer cancellation emits no terminal mouse packet: legacy terminal protocols
have no cancellation message, and a synthetic release could activate a child
control. New runtime event kinds map conservatively to cancellation while the
package remains buildable with its tagged framework dependency.

The emulator also owns a bounded history viewport, framed control strings,
validated Sixel decoding, Kitty direct-transfer image storage and OSC 99
assemblies. SwiftTerm remains private. `TerminalGraphic` values enter ordinary
SwiftTUI `Image` composition above the pane text and are clipped by the pane.
`TerminalTextSelection` freezes a frame and its wrap metadata for consistent
highlighting and copying. Host clipboard and notification callbacks own policy;
the embedding package never posts desktop notifications itself.

See [Terminal Embedding](../Sources/SwiftTUITerminalView/SwiftTUITerminalView.docc/TerminalEmbedding.md)
for the protocol subsets, limits, viewport behavior and lifecycle rules.
