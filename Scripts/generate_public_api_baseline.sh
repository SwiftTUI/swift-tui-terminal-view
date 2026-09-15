#!/usr/bin/env bash
set -euo pipefail

# Generates docs/.public-api-baseline.txt: the flat, sorted list of public
# `SwiftTUITerminalView.*` symbols, derived from `swift package dump-symbol-graph`.
# With --print, writes the list to stdout instead of updating the file.
#
# The committed file is the diff-checkable enumeration of this package's
# public Swift surface; Scripts/check_public_api_baseline.sh enforces it in
# the native gate.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

PRINT_ONLY=0
if [[ "${1:-}" == "--print" ]]; then
  PRINT_ONLY=1
fi

run_swift() {
  if command -v swiftly >/dev/null 2>&1; then
    swiftly run swift "$@"
  else
    swift "$@"
  fi
}

find .build \( -name 'SwiftTUITerminalView.symbols.json' -o -name 'SwiftTUITerminalView@*.symbols.json' -o -name 'SwiftTUITerminalEmulation.symbols.json' -o -name 'SwiftTUITerminalEmulation@*.symbols.json' \) -delete 2>/dev/null || true
# Swift Build includes dependency reexports and writes duplicate graph copies.
dump_log="$(mktemp)"
trap 'rm -f "$dump_log"' EXIT
if ! run_swift package --build-system native dump-symbol-graph \
  --minimum-access-level public --skip-synthesized-members >"$dump_log" 2>&1; then
  # SwiftPM can request a graph for a synthetic test runner that it did not build.
  # Only that diagnostic is harmless; library graphs are required below.
  expected_error="^error: Failed to emit symbol graph for '.*Package(Discovered)?Tests':"
  unexpected_errors="$(grep '^error:' "$dump_log" | grep -Ev "$expected_error" || true)"
  if ! grep -Eq "$expected_error" "$dump_log" || [[ -n "$unexpected_errors" ]]; then
    cat "$dump_log" >&2
    exit 1
  fi
fi

SYMBOLS="$(python3 - <<'PYTHON'
import json
from pathlib import Path

lines = set()
for module in ("SwiftTUITerminalView", "SwiftTUITerminalEmulation"):
    paths = list(Path(".build").rglob(module + ".symbols.json"))
    if len(paths) != 1:
        raise SystemExit(f"expected one {module} symbol graph, found {len(paths)}")
    # Extensions of framework protocols are emitted in @-qualified graphs.
    # They are owned here too (notably View.terminalTitleChanged).
    for path in paths + list(paths[0].parent.glob(module + "@*.symbols.json")):
        graph = json.loads(path.read_text())
        for symbol in graph.get("symbols", []):
            if symbol.get("accessLevel") == "public" and symbol.get("pathComponents"):
                lines.add(module + "." + ".".join(symbol["pathComponents"]))
print("\n".join(sorted(lines)))
PYTHON
)"

if [[ ${PRINT_ONLY} -eq 1 ]]; then
  printf '%s\n' "${SYMBOLS}"
else
  mkdir -p docs
  printf '%s\n' "${SYMBOLS}" > docs/.public-api-baseline.txt
  echo "generate_public_api_baseline: wrote docs/.public-api-baseline.txt ($(printf '%s\n' "${SYMBOLS}" | wc -l | tr -d ' ') symbols)." >&2
fi
