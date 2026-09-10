#!/usr/bin/env bash
set -euo pipefail

# macOS and Linux gate: real PTY tests plus both modules' API baselines.
# SwiftTerm and the PTY layer do not support Windows or WASI.

script_source="${BASH_SOURCE[0]}"
if command -v realpath >/dev/null 2>&1; then
  script_path="$(realpath "$script_source")"
else
  script_path="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$script_source")"
fi

# Structural resolution (script lives at Scripts/): the coordination overlay
# materializes this repo WITHOUT .git and nested inside the org checkout, so a
# git-toplevel lookup would escape to the wrong root.
repo_root="$(cd "$(dirname "$script_path")/.." && pwd)"

cd "$repo_root"

run_swift() {
  if command -v swiftly >/dev/null 2>&1; then
    swiftly run swift "$@"
  else
    swift "$@"
  fi
}

run_swift test

Scripts/check_public_api_baseline.sh
