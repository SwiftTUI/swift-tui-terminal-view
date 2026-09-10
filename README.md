# SwiftTUI Terminal View

[![SwiftTUI](https://img.shields.io/badge/SwiftTUI-0.12.1-blue)](https://github.com/SwiftTUI/swift-tui)

Embed terminal programs inside SwiftTUI views. `SwiftTUITerminalView` provides
`TerminalView`, `TerminalProcessSession`, the `TerminalSession` protocol, and
SwiftTerm-backed terminal emulation. It supports macOS and Linux; Windows and
WASI are not supported.

## Install

```swift
.package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.12.1"),
.package(url: "https://github.com/SwiftTUI/swift-tui-terminal-view.git", exact: "0.12.1"),
```

Add `.product(name: "SwiftTUITerminalView", package: "swift-tui-terminal-view")`
to your target's dependencies, alongside the SwiftTUI product your app uses.

```swift
import SwiftTUI
import SwiftTUITerminalView

struct ShellPane: View {
  @State private var session = TerminalProcessSession(
    command: "/bin/sh", initialSize: CellSize(width: 80, height: 24)
  )

  var body: some View {
    TerminalView(session: session)
  }
}
```

## Migration

Add the `swift-tui-terminal-view` package dependency, change the old
`SwiftTUITerminal` product dependency to `SwiftTUITerminalView` from this package,
and change `import SwiftTUITerminal` to `import SwiftTUITerminalView`.
The view, session, emulator, event, key, and mouse APIs keep their names.
`ChildProcessPty` is supplied by the framework's `SwiftTUIPTYPrimitives` product,
which this module re-exports alongside `SwiftTUIRuntime` and emulation.

## Development

Use `swiftly run swift test` or `Scripts/native_gate.sh`. Native gates run the
suite and verify the public API baseline. See [docs](docs/README.md) for the
module boundary and development commands. SwiftTUI organization integration
uses a temporary dependency overlay; public manifests always use tagged HTTPS
package dependencies.
