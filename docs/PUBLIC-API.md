# Public API

The `SwiftTUITerminalView` product exposes the view, session protocol, process
session, lifecycle and exit vocabulary, host key routing, and terminal event
modifiers. It re-exports `SwiftTUITerminalEmulation` for the emulator and its
key, mouse, event, immutable snapshot, image and notification vocabulary, and framework Runtime and PTYPrimitives.

`docs/.public-api-baseline.txt` records declarations owned by this package's two
modules. Re-exported framework declarations remain in the framework baseline.
Run `Scripts/generate_public_api_baseline.sh` for intentional API changes and
commit the diff alongside code. `Scripts/check_public_api_baseline.sh` rejects
unreviewed additions and removals. There is no compatibility product for the
former `SwiftTUITerminal` module.

`TerminalSession` adds `cachedTerminalSnapshot`, `scroll(by:)` and
`resumeFollowingOutput()` with defaults for grid-only conformers. Process and
emulator initializers add a defaulted `scrollbackLimit`; existing call sites
remain source-compatible. Event switches should handle the new
`contentChanged` and `notification` cases. This is an additive source release,
not an ABI compatibility guarantee for previously compiled binaries.
