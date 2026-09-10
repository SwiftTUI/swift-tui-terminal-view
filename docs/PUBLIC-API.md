# Public API

The `SwiftTUITerminalView` product exposes the view, session protocol, process
session, lifecycle and exit vocabulary, host key routing, and terminal event
modifiers. It re-exports `SwiftTUITerminalEmulation` for the emulator and its
key, mouse, and event vocabulary, and framework Runtime and PTYPrimitives.

`docs/.public-api-baseline.txt` records declarations owned by this package's two
modules. Re-exported framework declarations remain in the framework baseline.
Run `Scripts/generate_public_api_baseline.sh` for intentional API changes and
commit the diff alongside code. `Scripts/check_public_api_baseline.sh` rejects
unreviewed additions and removals. There is no compatibility product for the
former `SwiftTUITerminal` module.
