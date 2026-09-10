# Getting started

## Add the package

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

