# Architecture

`SwiftTUITerminalView` composes `ForeignSurface` through the public framework
runtime surface. `TerminalView` owns the view lifecycle, focused input routing,
host focus binding, and event callbacks. `TerminalSession` separates presentation
from process ownership. `TerminalProcessSession` connects a framework
`ChildProcessPty` to the emulator, pumps bytes, publishes events, and caches the
latest grid. PTY spawning and the C shim remain framework-owned because CLI
attach and entry-point tests also use them.

`SwiftTUITerminalEmulation` is an internal target re-exported by the umbrella.
It alone depends on SwiftTerm and translates terminal output into `ForeignGrid`
and typed events, keys, and mouse input. No SwiftTerm type crosses its public API.
Both targets consume public framework products, with no package-internal access.

The umbrella re-exports Runtime, PTYPrimitives, and Emulation. Tests use the
existing public testing support product for view input and lifecycle checks;
they never testably import framework internals. Presentation planner byte-budget
regressions live in the framework, while real-process output coverage lives here.
