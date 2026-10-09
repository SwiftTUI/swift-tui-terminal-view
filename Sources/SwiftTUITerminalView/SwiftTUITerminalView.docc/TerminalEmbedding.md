# Terminal Embedding

Host external terminal programs inside SwiftTUI layout with the
`SwiftTUITerminalView` product.

## Overview

Terminal embedding is implemented in the separate `swift-tui-terminal-view`
package's `SwiftTUITerminalView` product. Apps import `SwiftTUI` for the
convenience surface or `SwiftTUIRuntime` for explicit composition, and
import `SwiftTUITerminalView` for `TerminalView<Session>`, `TerminalSession`, and
`TerminalProcessSession`.

`TerminalView` participates in the normal SwiftTUI frame pipeline. It measures
from its parent proposal and draws a foreign terminal grid through the existing
raster path. While focused, it forwards keyboard input to the child session.
The child program does not own a separate commit path.

For the product boundary context, see [Architecture](https://swifttui.sh/docs/documentation/swifttuiruntime/architecture) and
[Host Integration](https://swifttui.sh/docs/documentation/swifttuiruntime/host-integration).

## Authoring

Use `TerminalProcessSession` when the embedded program is a local child process:

```swift
import SwiftTUI
import SwiftTUITerminalView

struct ShellPane: View {
  @State private var session = TerminalProcessSession(
    command: "/bin/zsh",
    initialSize: CellSize(width: 80, height: 24)
  )

  var body: some View {
    TerminalView(session: session)
      .frame(minWidth: 40, minHeight: 12)
  }
}
```

The initial cell size seeds the emulator before layout reports the placed view
size. `TerminalView` starts the session, resizes the pty from layout, and
invalidates itself as emulator events arrive.

When a host owns an enum-valued focus model, bind that focus to the terminal's
framework-owned input member:

```swift
enum PaneFocus: Hashable {
  case browser
  case preview
}

@FocusState private var focus: PaneFocus?

TerminalView(
  session: session,
  keyRouting: { keyPress in
    keyPress == KeyPress(.escape) ? .handledByHost : .forwardToChild
  }
)
.hostFocused($focus, equals: .preview)
```

`keyRouting` receives the original `KeyPress` before terminal conversion.
Returning `.handledByHost` consumes the key. `.forwardToChild` preserves the
ordinary terminal input path. Replace an application-owned `.focusable` and
`.onKeyPress` forwarding layer with `hostFocused`.

Supply arguments, the environment, and the working directory during
construction:

```swift
@State private var preview = TerminalProcessSession(
  command: "/usr/bin/less",
  arguments: ["/tmp/report.txt"],
  environment: ["LESS": "-R"],
  workingDirectory: "/tmp",
  initialSize: CellSize(width: 80, height: 24)
)
```

## Custom Sessions

Implement `TerminalSession` for non-local-process sources such as SSH,
recorded terminal streams, or remote multiplexer panes.

The protocol exposes a synchronous `cachedSnapshot` plus async control and input
methods:

```swift
public protocol TerminalSession: AnyObject, Sendable {
  var cachedSnapshot: ForeignGrid { get }
  var cachedTerminalSnapshot: TerminalSnapshot { get }
  func scroll(by lines: Int) async
  func resumeFollowingOutput() async

  func start() async throws
  func snapshot() async -> ForeignGrid
  func currentTitle() async -> String?
  func currentWorkingDirectory() async -> String?
  func currentLifecycle() async -> TerminalLifecycle
  func send(key: TerminalEmulatorKey) async
  func send(paste: String) async
  func send(mouse: TerminalEmulatorMouse) async
  func resize(_ size: CellSize) async throws
  func events() -> AsyncStream<TerminalEmulatorEvent>
}
```

`cachedSnapshot` is synchronous so draw extraction can create the
foreign-surface payload without awaiting an actor. Session implementations
must refresh it as terminal output arrives and publish `.contentChanged` even
when no metadata changed. `cachedTerminalSnapshot` carries an immutable grid,
wrap flags, absolute history rows, buffer epoch, mouse tracking, and pane images.
Legacy conformers receive a live-grid default and no-op history methods. A
session wrapper must forward these requirements or open its underlying
`any TerminalSession` before constructing the view; otherwise it loses those
capabilities. Render payloads retain the captured grid, never a live session.

The process session feeds every PTY byte and forwards ordered metadata/replies.
It coalesces pending **snapshot requests** into one slot at a 16 ms cadence,
reuses unchanged emulator rows, and flushes the last frame before exit. An idle
session does not poll. The PTY reader's byte stream is not bounded by that
snapshot slot; consumers should not interpret the cadence as byte backpressure.

## Metadata And Exit

Title and working-directory changes can be observed with modifiers:

```swift
TerminalView(session: session)
  .terminalTitleChanged { title in
    windowTitle = title
  }
  .terminalWorkingDirectoryChanged { directory in
    currentDirectory = directory
  }
```

`TerminalView` also accepts direct `onTitleChange` and `onExit` closures in its
initializer when the terminal pane owns the response locally.

## Keyboard, selection, and history

Legacy encoding preserves Control-C/D, Control punctuation and space, Option
prefixes, shifted Tab, modified navigation and F1–F12, application-cursor mode,
Unicode text, and bracketed paste. Kitty keyboard negotiation uses the backend's
per-buffer flag stack. Supported flags are 1 (disambiguation), 8 (all supplied
keys), and 16 (associated text); queries report only these bits. The host key API
does not supply release/repeat phases or alternate layout codes, so flags 2 and
4 are not advertised. A host interceptor runs before selection/history handling
and before terminal encoding. Focused input reaches only its owning pane.

Click and drag to select visible text. Control-Shift-S enters explicit keyboard
selection, arrows extend it, Home/End move to row edges, Enter or Control-C copies,
and Escape exits. The blue highlight and copied text use one frozen snapshot:
continued output cannot change a selection mid-copy. Selection normalizes wide
character boundaries, preserves graphemes, skips continuation cells, trims
hard-line trailing blanks, and joins soft wraps. Styles and escape bytes are
never copied. The host's clipboard action decides whether the copy succeeds;
`.terminalCopyCompleted { accepted in ... }` optionally reports the result.
The write occurs even without that callback.

The normal buffer retains 2,000 scrollback lines by default; `scrollbackLimit`
accepts 0 through 100,000. Wheel scrolling in the focused pane or Shift-PageUp/
PageDown enters history. In history, arrows and pages move the viewport, Home
moves to the oldest retained row, and End/Escape resumes following output.
Ordinary keys are consumed while browsing; they do not unexpectedly type into
the live child. Reaching the live edge still requires End/Escape to resume.
History stays anchored by absolute row while output continues and clamps when
old rows expire. Alternate screens have no scrollback. Resize, reset and buffer
switches return to live output and invalidate selection; resize uses the
backend's normal text reflow.

Child mouse reporting suppresses automatic drag selection and wheel history.
Control-Shift-S explicitly overrides it for local selection. `send(mouse:)`
provides X10/1000/1002/SGR encoding for hosts that route child pointer input.
`TerminalView` does not itself forward pointer events to the child. A pointer
press can focus its pane; wheel history requires that pane already be focused.

## Semantic pane review

The default accessibility representation names the pane and child title,
reports the live logical caret, and supplies bounded Unicode output review.
Freeze output review keeps a stable copy during child updates. Earlier output,
Later output and Follow latest output navigate retained normal-buffer history;
Copy reviewed output reports the host clipboard result. Buffer resets and
history eviction are described without replacing a frozen review silently.

Enter child line input offers a standard editable field, Hide input, a separate
Send line to child action, and Leave child input. Sending uses paste followed by
Return; leaving clears the draft and restores assistive focus to the pane title.
Browser Tab can return to surrounding app controls. This line path does not
infer a full-screen subprocess's widgets or password prompts. Hosts should
provide that program's accessible line mode or an authored equivalent task path.
The native keyboard interceptor and ordinary child Escape behavior are unchanged.

Review removes control and bidi formatting characters and caps output at 16384
Unicode scalars with an explicit truncation notice. It preserves soft wraps and
wide-cell text. Real reader speech and clipboard permission remain host-level
qualification responsibilities.

## Pane graphics

Images are decoded into package-owned `TerminalGraphic` PNG values and composed
with ordinary SwiftTUI `Image` views above terminal text, clipped to the pane.
Child escapes are never written directly to the outer terminal. The host image
renderer chooses Kitty, Sixel, or its cell-image fallback on a text-only host.
Equal child IDs in different sessions receive distinct render identities.

Sixel reuses SwiftTerm's bitmap decoder after bounded validation. RGB/HLS
palettes, repeats, and transparent pixels are supported. Placement begins at the
child cursor; a virtual 8×16 pixel cell determines its cell extent. The cursor
stays in place. Raster hints are validated but do not scale the bitmap. The
accepted payload is at most 1 MiB, each dimension at most 1,024 pixels, palettes
at most 256 entries, and cumulative column work at most 2,097,152 operations.
This is a stationary bitmap subset, not complete DEC printer emulation.

Kitty graphics supports direct (`t=d`) raw RGB (`f=24`) and RGBA (`f=32`) data,
explicit nonzero image IDs, transmit (`a=t`), transmit/display (`a=T`), placement
(`a=p`), query (`a=q`), and deletion (`a=d`, selectors a/A/i/I). Display requires
`C=1` (stationary cursor). `c` and `r` specify the cell extent; otherwise the same
8×16 virtual cell applies. Each placement may specify `p`; replacement retains
its rendering identity. Queries validate the submitted format and data and
return OK only for supported input. Replies go only to the originating child;
`q=1` suppresses successful replies and `q=2` suppresses all replies.
File/shared-memory transfer, compression, PNG input, virtual/relative placement,
pixel offsets and z-order are rejected. Unsupported controls receive ENOTSUP;
invalid data receives EINVAL; exhausted storage receives ENOSPC.

Chunked Kitty transfers use `m=1` followed by `m=0`; continuation headers contain
only `m` and `q`. One assembly per session is allowed, up to 6 MiB of encoded
data and five seconds from its first chunk. Expiry is checked on subsequent
input without an idle timer. Each image is at most 1,024×1,024 pixels. A session
retains at most 32 assets, 64 placements and 16 MiB of encoded PNG assets;
transient decoder and renderer allocations are additional. Images scroll with
their absolute row and disappear when their bounds leave retained history.
Normal-buffer placements survive an alternate-screen visit; alternate-buffer
placements are discarded on buffer switches. J/K erase removes all placements
in the active buffer, including partial-line erase. Reset and resize discard
all images/assemblies. After the process pump ends, releasing the session releases its storage.
Detaching the view removes its rendered image attachments but does not terminate
the child: the host owns that lifecycle and calls `terminate()` when closing a
process pane. Keeping a session for a hidden tab keeps its bounded image store.

Control strings are incrementally framed across PTY reads, capped at 6 MiB and
five seconds on subsequent input. CAN/SUB cancel a string. Truncated strings
remain invisible and are discarded when cancelled, expired, oversized, or the
session is disposed. These resource limits apply independently to each session.

## Host-controlled notifications

OSC 99 title/body chunks (`p=title` or `p=body`, `d=0` continuation, `d=1` final),
UTF-8 or base64 (`e=1`), identifier replacement (`i`), and explicit close
(`p=close`) become typed `TerminalNotification` events. IDs combine a generated
session identifier with the child identifier. There are no desktop side effects,
activation acknowledgments, sound, icon, or focus-stealing operations. Other
metadata is ignored; unsupported payload types and malformed data are dropped.

```swift
TerminalView(session: session)
  .terminalNotification { request in
    // This is host policy: suppress, render an in-app banner, or call a host API.
    if request.kind == .show && allowNotifications {
      banners[request.id] = request.title + " — " + request.body
    } else if request.kind == .close {
      banners.removeValue(forKey: request.id)
    }
  }
```

Without a handler requests are suppressed. Mounted foreground and background
panes receive events equally; the host closure can filter using its own focus
model. A detached pane has no view subscriber. Task cancellation (detach or
resize), session exit, and terminal reset close outstanding delivered IDs.
Updates replace the same ID. At most eight completed notifications per second,
32 active IDs, 16 pending assemblies and 8 KiB of combined title/body per request
are accepted. Pending chunks expire after five seconds on subsequent input.
Identifiers use ASCII letters, digits, hyphen and underscore, up to 128 bytes.
Anonymous single requests are assigned unique IDs. Control characters other
than tab and newline are rejected. No child notification escape passes through
to the outer terminal.

## Platform and metadata support

The local PTY implementation supports macOS and Linux. Windows, iOS process
hosting and WASI are unsupported. OSC 52 clipboard requests, OSC 0/2 titles,
OSC 7 directories and OSC 8 hyperlinks remain available. The host owns all
clipboard/notification permission and presentation policy.

Protocol references: [Kitty keyboard](https://sw.kovidgoyal.net/kitty/keyboard-protocol/),
[Kitty graphics](https://sw.kovidgoyal.net/kitty/graphics-protocol/), and
[OSC 99 notifications](https://sw.kovidgoyal.net/kitty/desktop-notifications/).
