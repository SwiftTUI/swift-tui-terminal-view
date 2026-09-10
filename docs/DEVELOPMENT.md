# Development

The pinned toolchain is in `.swift-version`. Run:

```sh
swiftly run swift build
swiftly run swift test
Scripts/native_gate.sh
Scripts/generate_public_api_baseline.sh
Scripts/build_docc_archive.sh
```

The native gate checks tests and both modules' public API baseline. Linux CI runs
on pushes and pull requests. Tags also build Release; macOS runs through the
verdict-controlled lane. There is no WASI lane: SwiftTerm and the PTY layer are
POSIX terminal dependencies. Tests launch real child processes and run as this
package's own suite, separate from the framework's larger test process.
